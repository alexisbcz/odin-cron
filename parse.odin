package cron

import "core:strings"

/*
parse reads a cron expression into a Schedule.

The expression is either a macro or a list of fields separated by spaces or
tabs. With the default Field_Mode.Auto, five fields mean
`minute hour day-of-month month day-of-week` and six fields put `second`
first.

Macros, case insensitive:
- `@yearly`, `@annually`: `0 0 1 1 *`
- `@monthly`: `0 0 1 * *`
- `@weekly`: `0 0 * * 0`
- `@daily`, `@midnight`: `0 0 * * *`
- `@hourly`: `0 * * * *`

Each field is a comma-separated list of items. An item is `*`, a value `n`, a
range `a-b`, or one of those followed by `/step`. A bare value with a step,
`n/step`, runs from `n` to the end of the field. Months accept `JAN` to `DEC`
and weekdays `SUN` to `SAT`, in any case. Day of week 7 also means Sunday.

Extensions:
- `?` as the whole day-of-month or day-of-week field means the same as `*`.
- Day of month `L` is the last day, `L-n` is n days before it, `LW` is the
  last weekday (Monday to Friday) and `nW` is the weekday nearest to day n
  without leaving the month.
- Day of week `nL` is the last weekday n of the month, and `n#k` is the k-th
  weekday n of the month, with k from 1 to 5.

When both day fields are restricted, that is, neither starts with `*` or `?`,
a day matches if either field matches. Otherwise both must match. This is the
classic Vixie cron rule.

Inputs:
- expr: the expression; leading and trailing whitespace is ignored.
- mode: how many fields to accept.

Returns:
- schedule: the parsed schedule. It owns no memory.
- err: `nil`, or a Parse_Error that names the problem.

parse never allocates. Use parse_with_location to also learn where the error is.
*/
parse :: proc(expr: string, mode := Field_Mode.Auto) -> (schedule: Schedule, err: Error) {
	schedule, err, _ = parse_with_location(expr, mode)
	return
}

/*
parse_with_location is parse, plus the location of the first problem.

Returns:
- schedule: the parsed schedule, or the zero value on error.
- err: `nil`, or a Parse_Error that names the problem.
- loc: where the problem is. It's the zero value on success.
*/
parse_with_location :: proc(
	expr: string,
	field_mode := Field_Mode.Auto,
) -> (
	schedule: Schedule,
	err: Error,
	loc: Location,
) {
	mode := field_mode
	text := strings.trim(expr, " \t\r\n")
	if len(text) == 0 {
		return {}, .Empty_Expression, {}
	}
	if text[0] == '@' {
		macro, ok := expand_macro(text)
		if !ok {
			return {}, .Unknown_Macro, {offset = leading_space(expr)}
		}
		text = macro
		mode = .Auto
	}

	// Split into fields, remembering where each starts in the original.
	MAX_FIELDS :: 6
	fields: [MAX_FIELDS]string
	starts: [MAX_FIELDS]int
	count := 0
	base := leading_space(expr)
	i := 0
	for i < len(text) {
		for i < len(text) && is_space(text[i]) {
			i += 1
		}
		if i >= len(text) {
			break
		}
		j := i
		for j < len(text) && !is_space(text[j]) {
			j += 1
		}
		if count == MAX_FIELDS {
			return {}, .Wrong_Field_Count, {}
		}
		fields[count] = text[i:j]
		starts[count] = base + i
		count += 1
		i = j
	}

	first: Field
	switch {
	case count == 5 && mode != .Six:
		first = .Minute
		schedule.seconds = {0}
	case count == 6 && mode != .Five:
		first = .Second
	case:
		return {}, .Wrong_Field_Count, {}
	}

	for k in 0 ..< count {
		field := Field(int(first) + k)
		perr, offset := parse_field(&schedule, field, fields[k], starts[k])
		if perr != .None {
			return {}, perr, {field = field, offset = offset}
		}
	}
	return schedule, nil, {}
}

@(private = "file")
Field_Spec :: struct {
	lo, hi:   int, // Inclusive bounds of a plain value.
	open_hi:  int, // Upper bound for `*` and `n/step`.
	names:    []string, // Three-letter names, the first one meaning `name_lo`.
	name_lo:  int,
}

@(private = "file", rodata)
MONTH_NAMES := [12]string{"JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"}

@(private = "file", rodata)
WEEKDAY_NAMES := [7]string{"SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"}

@(private = "file")
field_spec :: proc(field: Field) -> Field_Spec {
	switch field {
	case .Second, .Minute:
		return {lo = 0, hi = 59, open_hi = 59}
	case .Hour:
		return {lo = 0, hi = 23, open_hi = 23}
	case .Day_Of_Month:
		return {lo = 1, hi = 31, open_hi = 31}
	case .Month:
		return {lo = 1, hi = 12, open_hi = 12, names = MONTH_NAMES[:], name_lo = 1}
	case .Day_Of_Week:
		return {lo = 0, hi = 7, open_hi = 6, names = WEEKDAY_NAMES[:], name_lo = 0}
	}
	return {}
}

@(private = "file")
expand_macro :: proc(text: string) -> (fields: string, ok: bool) {
	MACROS :: [?][2]string {
		{"@yearly", "0 0 1 1 *"},
		{"@annually", "0 0 1 1 *"},
		{"@monthly", "0 0 1 * *"},
		{"@weekly", "0 0 * * 0"},
		{"@daily", "0 0 * * *"},
		{"@midnight", "0 0 * * *"},
		{"@hourly", "0 * * * *"},
	}
	macros := MACROS
	for m in macros {
		if strings.equal_fold(text, m[0]) {
			return m[1], true
		}
	}
	return "", false
}

@(private = "file")
is_space :: proc(c: byte) -> bool {
	return c == ' ' || c == '\t' || c == '\r' || c == '\n'
}

@(private = "file")
leading_space :: proc(s: string) -> int {
	n := 0
	for n < len(s) && is_space(s[n]) {
		n += 1
	}
	return n
}

// parse_field parses one field into `s`. On error it returns the byte offset of the failing item.
@(private = "file")
parse_field :: proc(s: ^Schedule, field: Field, text: string, start: int) -> (err: Parse_Error, offset: int) {
	spec := field_spec(field)
	is_day := field == .Day_Of_Month || field == .Day_Of_Week

	if text[0] == '?' {
		if !is_day || len(text) != 1 {
			return .Invalid_Question_Mark, start
		}
	}
	unrestricted := text[0] == '*' || text[0] == '?'

	mask: u64
	rest := "*" if text == "?" else text
	item_start := start
	for {
		comma := strings.index_byte(rest, ',')
		item := rest if comma < 0 else rest[:comma]
		if e := parse_item(s, field, spec, item, &mask); e != .None {
			return e, item_start
		}
		if comma < 0 {
			break
		}
		rest = rest[comma + 1:]
		item_start += comma + 1
	}

	switch field {
	case .Second:
		for v in 0 ..< 60 {
			if mask & (1 << uint(v)) != 0 {
				s.seconds += {v}
			}
		}
	case .Minute:
		for v in 0 ..< 60 {
			if mask & (1 << uint(v)) != 0 {
				s.minutes += {v}
			}
		}
	case .Hour:
		for v in 0 ..< 24 {
			if mask & (1 << uint(v)) != 0 {
				s.hours += {v}
			}
		}
	case .Day_Of_Month:
		for v in 1 ..= 31 {
			if mask & (1 << uint(v)) != 0 {
				s.days += {v}
			}
		}
		s.any_day = unrestricted
	case .Month:
		for v in 1 ..= 12 {
			if mask & (1 << uint(v)) != 0 {
				s.months += {v}
			}
		}
	case .Day_Of_Week:
		if mask & (1 << 7) != 0 {
			mask |= 1
		}
		for v in 0 ..= 6 {
			if mask & (1 << uint(v)) != 0 {
				s.weekdays += {v}
			}
		}
		s.any_weekday = unrestricted
	}
	return .None, 0
}

// parse_item parses one list item. Plain values go into `mask`; extensions go straight into `s`.
@(private = "file")
parse_item :: proc(s: ^Schedule, field: Field, spec: Field_Spec, item: string, mask: ^u64) -> Parse_Error {
	if len(item) == 0 {
		return .Empty_Item
	}

	body := item
	step := 0
	has_step := false
	if slash := strings.index_byte(item, '/'); slash >= 0 {
		body = item[:slash]
		has_step = true
		n, ok := parse_number(item[slash + 1:])
		if !ok || n < 1 || n > spec.open_hi - spec.lo + 1 {
			return .Invalid_Step
		}
		step = n
	}

	if body == "?" {
		return .Invalid_Question_Mark
	}

	if !has_step {
		if handled, e := parse_extension(s, field, spec, body); handled {
			return e
		}
	}

	lo, hi: int
	if body == "*" {
		lo, hi = spec.lo, spec.open_hi
	} else if dash := strings.index_byte(body, '-'); dash >= 0 {
		a, ea := parse_value(spec, body[:dash])
		if ea != .None {
			return classify(body, ea)
		}
		b, eb := parse_value(spec, body[dash + 1:])
		if eb != .None {
			return classify(body, eb)
		}
		if a > b {
			return .Invalid_Range
		}
		lo, hi = a, b
	} else {
		v, e := parse_value(spec, body)
		if e != .None {
			return classify(body, e)
		}
		lo, hi = v, v
		if has_step {
			// `n/step` runs to the end of the field. Day of week 7 is past
			// open_hi, so `7/step` keeps 7, which means Sunday.
			hi = max(spec.open_hi, v)
		}
	}

	if !has_step {
		step = 1
	}
	for v := lo; v <= hi; v += step {
		mask^ |= 1 << uint(v)
	}
	return .None
}

/*
parse_extension handles `L`, `W` and `#` items. It reports `handled = false`
when the item uses none of them, so that the caller parses it as a plain value.
*/
@(private = "file")
parse_extension :: proc(s: ^Schedule, field: Field, spec: Field_Spec, body: string) -> (handled: bool, err: Parse_Error) {
	#partial switch field {
	case .Day_Of_Month:
		upper_l := body[0] == 'L' || body[0] == 'l'
		last := body[len(body) - 1]
		switch {
		case upper_l && len(body) == 1:
			s.last_days += {0}
			return true, .None
		case upper_l && len(body) == 2 && (last == 'W' || last == 'w'):
			s.last_weekday = true
			return true, .None
		case upper_l && len(body) > 2 && body[1] == '-':
			n, ok := parse_number(body[2:])
			if !ok {
				return true, .Invalid_Last
			}
			if n > 30 {
				return true, .Value_Out_Of_Range
			}
			s.last_days += {n}
			return true, .None
		case upper_l:
			return true, .Invalid_Last
		case last == 'W' || last == 'w':
			n, ok := parse_number(body[:len(body) - 1])
			if !ok {
				return true, .Invalid_Nearest_Weekday
			}
			if n < 1 || n > 31 {
				return true, .Value_Out_Of_Range
			}
			s.nearest_weekday += {n}
			return true, .None
		}
	case .Day_Of_Week:
		if hash := strings.index_byte(body, '#'); hash >= 0 {
			wd, e := parse_value(spec, body[:hash])
			if e != .None {
				return true, .Invalid_Nth_Weekday if e == .Invalid_Value else e
			}
			k, ok := parse_number(body[hash + 1:])
			if !ok || k < 1 || k > 5 {
				return true, .Invalid_Nth_Weekday
			}
			s.nth_weekday[wd % 7] += {k}
			return true, .None
		}
		last := body[len(body) - 1]
		if last == 'L' || last == 'l' {
			if len(body) == 1 {
				return true, .Invalid_Last
			}
			wd, e := parse_value(spec, body[:len(body) - 1])
			if e != .None {
				return true, .Invalid_Last if e == .Invalid_Value else e
			}
			s.last_of_weekday += {wd % 7}
			return true, .None
		}
	}
	return false, .None
}

// classify turns a generic Invalid_Value into a more helpful error when the item misuses an extension.
@(private = "file")
classify :: proc(body: string, err: Parse_Error) -> Parse_Error {
	if err != .Invalid_Value {
		return err
	}
	switch {
	case strings.index_byte(body, '#') >= 0:
		return .Invalid_Nth_Weekday
	case strings.index_byte(body, '?') >= 0:
		return .Invalid_Question_Mark
	case strings.has_suffix(body, "W"), strings.has_suffix(body, "w"):
		return .Invalid_Nearest_Weekday
	case body == "L", body == "l", strings.has_prefix(body, "L-"), strings.has_suffix(body, "L"):
		return .Invalid_Last
	}
	return err
}

// parse_value reads a number or a name and checks it against the field's bounds.
@(private = "file")
parse_value :: proc(spec: Field_Spec, text: string) -> (value: int, err: Parse_Error) {
	if n, ok := parse_number(text); ok {
		if n < spec.lo || n > spec.hi {
			return 0, .Value_Out_Of_Range
		}
		return n, .None
	}
	if len(text) > 0 && is_digit(text[0]) {
		// Digits that overflow parse_number are still a number, just too large.
		for c in transmute([]byte)text {
			if !is_digit(c) {
				return 0, .Invalid_Value
			}
		}
		return 0, .Value_Out_Of_Range
	}
	for name, i in spec.names {
		if strings.equal_fold(text, name) {
			return spec.name_lo + i, .None
		}
	}
	return 0, .Invalid_Value
}

// parse_number reads a short run of ASCII digits. It rejects signs, spaces and more than four digits.
@(private = "file")
parse_number :: proc(text: string) -> (n: int, ok: bool) {
	if len(text) == 0 || len(text) > 4 {
		return 0, false
	}
	for c in transmute([]byte)text {
		if !is_digit(c) {
			return 0, false
		}
		n = n * 10 + int(c - '0')
	}
	return n, true
}

@(private = "file")
is_digit :: proc(c: byte) -> bool {
	return c >= '0' && c <= '9'
}
