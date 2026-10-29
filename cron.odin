/*
Package cron parses cron expressions and computes their next and previous
fire times.

It reads the classic five-field form (minute, hour, day of month, month, day of
week), a six-field form with a leading seconds field, and the `@daily` style
macros. Fields accept lists, ranges, steps, month and weekday names, and the
Quartz extensions `L`, `W` and `#`.

Time zones: every computation treats a `time.Time` as a UTC wall clock. The
package never reads the local time zone, so results don't depend on the host
and there are no daylight saving gaps or repeats. To run a schedule in a fixed
offset such as UTC+02:00, shift the input by the offset, call next or prev,
and shift the result back.

Parsing never allocates. A Schedule is a plain value that you can copy, store
and share between threads.

Example:
	import "core:fmt"
	import "core:time"
	import "shared:cron"

	main :: proc() {
		s, err := cron.parse("0,15,30,45 9-17 * * MON-FRI")
		if err != nil {
			fmt.eprintln("bad expression:", err)
			return
		}
		from, _ := time.components_to_time(2026, 10, 30, 12, 7, 0)
		when_next, ok := cron.next(s, from)
		if ok {
			fmt.println(when_next) // 2026-10-30 12:15:00.000000000 +0000 UTC
		}
	}
*/
package cron

import "base:runtime"

// Second_Set holds the seconds, 0 to 59, at which a schedule fires.
Second_Set :: bit_set[0 ..< 60;u64]
// Minute_Set holds the minutes, 0 to 59, at which a schedule fires.
Minute_Set :: bit_set[0 ..< 60;u64]
// Hour_Set holds the hours, 0 to 23, at which a schedule fires.
Hour_Set :: bit_set[0 ..< 24;u32]
// Day_Set holds days of the month, 1 to 31.
Day_Set :: bit_set[1 ..= 31;u32]
// Month_Set holds months, 1 (January) to 12 (December).
Month_Set :: bit_set[1 ..= 12;u16]
// Weekday_Set holds days of the week, 0 (Sunday) to 6 (Saturday).
Weekday_Set :: bit_set[0 ..= 6;u8]
// Last_Offset_Set holds offsets back from the last day of the month: 0 is `L`, 3 is `L-3`.
Last_Offset_Set :: bit_set[0 ..< 31;u32]
// Week_Set holds week numbers within a month, 1 to 5, as used by `#`.
Week_Set :: bit_set[1 ..= 5;u8]

/*
Schedule is a parsed cron expression.

Build one with parse or parse_with_location. The fields are public so that you
can inspect or construct a schedule by hand, but most code only passes a
Schedule to next, prev and matches.

A Schedule owns no memory. It's safe to copy and to read from several threads
at once.
*/
Schedule :: struct {
	// Seconds at which the schedule fires. A five-field expression sets only second 0.
	seconds:         Second_Set,
	// Minutes at which the schedule fires.
	minutes:         Minute_Set,
	// Hours at which the schedule fires.
	hours:           Hour_Set,
	// Plain days of the month, from numbers, ranges and steps.
	days:            Day_Set,
	// Months in which the schedule fires.
	months:          Month_Set,
	// Plain days of the week, from numbers, names, ranges and steps.
	weekdays:        Weekday_Set,
	// Day-of-month `L` and `L-n` items, stored as offsets from the last day.
	last_days:       Last_Offset_Set,
	// Day-of-month `nW` items: the weekday nearest to day n, within the same month.
	nearest_weekday: Day_Set,
	// Day-of-month `LW`: the last Monday to Friday of the month.
	last_weekday:    bool,
	// Day-of-week `nL` items: the last such weekday of the month.
	last_of_weekday: Weekday_Set,
	// Day-of-week `n#k` items: index n is the weekday, the set holds each k.
	nth_weekday:     [7]Week_Set,
	// True when the day-of-month field started with `*` or `?`.
	any_day:         bool,
	// True when the day-of-week field started with `*` or `?`.
	any_weekday:     bool,
}

// Field names one field of a cron expression. Locations in parse errors use it.
Field :: enum u8 {
	Second,
	Minute,
	Hour,
	Day_Of_Month,
	Month,
	Day_Of_Week,
}

// Field_Mode selects how many fields parse accepts.
Field_Mode :: enum u8 {
	// Accept five fields (no seconds) or six fields (seconds first).
	Auto,
	// Accept only the classic five fields; seconds are always 0.
	Five,
	// Accept only six fields, with seconds first.
	Six,
}

// Parse_Error lists the ways a cron expression can be malformed.
Parse_Error :: enum u8 {
	None,
	// The expression is empty or only whitespace.
	Empty_Expression,
	// The expression has the wrong number of fields for the Field_Mode.
	Wrong_Field_Count,
	// The expression starts with `@` but names no known macro, or names `@reboot`.
	Unknown_Macro,
	// A list has an empty item, as in `1,,2` or a trailing comma.
	Empty_Item,
	// A value is neither a number nor a name valid in its field.
	Invalid_Value,
	// A number is outside the field's range, such as minute 60 or month 0.
	Value_Out_Of_Range,
	// A range runs backwards, as in `5-1`.
	Invalid_Range,
	// A step is missing, not a number, zero or wider than the field.
	Invalid_Step,
	// `?` appears outside the day fields, or with a step or range.
	Invalid_Question_Mark,
	// `L` is malformed or used in a field or position that doesn't allow it.
	Invalid_Last,
	// `W` is malformed or used outside the day-of-month field.
	Invalid_Nearest_Weekday,
	// `#` is malformed, used outside the day-of-week field, or not followed by 1 to 5.
	Invalid_Nth_Weekday,
}

/*
Error is the error type for fallible procedures in this package. `nil` means
success. parse returns only Parse_Error values; procedures that allocate can
also return a runtime.Allocator_Error.
*/
Error :: union #shared_nil {
	Parse_Error,
	runtime.Allocator_Error,
}

/*
Location says where parse_with_location found a problem.

`offset` is the byte offset into the original expression of the item that
failed, and `field` is the field that holds it. For errors that concern the
whole expression, such as Wrong_Field_Count, both are zero.
*/
Location :: struct {
	field:  Field,
	offset: int,
}
