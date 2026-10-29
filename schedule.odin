package cron

import "core:time"

// The widest range of whole seconds that a time.Time (int64 nanoseconds) can hold.
@(private = "file")
MIN_UNIX_SECOND :: -9_223_372_036
@(private = "file")
MAX_UNIX_SECOND :: 9_223_372_036

// The Gregorian calendar, weekdays included, repeats every 400 years.
@(private = "file")
SEARCH_YEARS :: 400

@(private = "file")
SECONDS_PER_DAY :: 86_400

@(private = "file")
NS_PER_SECOND :: 1_000_000_000

/*
matches reports whether `s` fires at the second that contains `t`.

`t` is read as UTC, and its fraction of a second is ignored, so a schedule
that fires at 12:00:00 also matches 12:00:00.5.
*/
matches :: proc(s: Schedule, t: time.Time) -> bool {
	sec := floor_div(time.to_unix_nanoseconds(t), NS_PER_SECOND)
	c := civil_from_unix(sec)
	return(
		c.second in s.seconds &&
		c.minute in s.minutes &&
		c.hour in s.hours &&
		c.month in s.months &&
		day_matches(s, c.year, c.month, c.day) \
	)
}

/*
next returns the first fire time of `s` strictly after `t`.

`t` and the result are UTC. The result always falls on a whole second.

Returns:
- fire: the next fire time.
- ok: false when the schedule never fires after `t`, such as `0 0 30 2 *`,
  or when the next fire time is past the year 2262, the end of time.Time.
*/
next :: proc(s: Schedule, t: time.Time) -> (fire: time.Time, ok: bool) {
	if is_empty(s) {
		return {}, false
	}
	start := floor_div(time.to_unix_nanoseconds(t), NS_PER_SECOND) + 1
	if start > MAX_UNIX_SECOND {
		return {}, false
	}
	c := civil_from_unix(start)

	for year in c.year ..= c.year + SEARCH_YEARS {
		first_year := year == c.year
		for month in (c.month if first_year else 1) ..= 12 {
			if month not_in s.months {
				continue
			}
			first_month := first_year && month == c.month
			for day in (c.day if first_month else 1) ..= days_in_month(year, month) {
				if !day_matches(s, year, month, day) {
					continue
				}
				first_day := first_month && day == c.day
				for hour in (c.hour if first_day else 0) ..< 24 {
					if hour not_in s.hours {
						continue
					}
					first_hour := first_day && hour == c.hour
					for minute in (c.minute if first_hour else 0) ..< 60 {
						if minute not_in s.minutes {
							continue
						}
						first_minute := first_hour && minute == c.minute
						for second in (c.second if first_minute else 0) ..< 60 {
							if second in s.seconds {
								return to_time({year, month, day, hour, minute, second})
							}
						}
					}
				}
			}
		}
	}
	return {}, false
}

/*
prev returns the last fire time of `s` strictly before `t`.

`t` and the result are UTC. The result always falls on a whole second.

Returns:
- fire: the previous fire time.
- ok: false when the schedule never fired before `t`, or when that time is
  before the year 1678, the start of time.Time.
*/
prev :: proc(s: Schedule, t: time.Time) -> (fire: time.Time, ok: bool) {
	if is_empty(s) {
		return {}, false
	}
	ns := time.to_unix_nanoseconds(t)
	start := floor_div(ns, NS_PER_SECOND)
	if start * NS_PER_SECOND == ns {
		start -= 1
	}
	if start < MIN_UNIX_SECOND {
		return {}, false
	}
	c := civil_from_unix(start)

	for year := c.year; year >= c.year - SEARCH_YEARS; year -= 1 {
		first_year := year == c.year
		for month := c.month if first_year else 12; month >= 1; month -= 1 {
			if month not_in s.months {
				continue
			}
			first_month := first_year && month == c.month
			for day := c.day if first_month else days_in_month(year, month); day >= 1; day -= 1 {
				if !day_matches(s, year, month, day) {
					continue
				}
				first_day := first_month && day == c.day
				for hour := c.hour if first_day else 23; hour >= 0; hour -= 1 {
					if hour not_in s.hours {
						continue
					}
					first_hour := first_day && hour == c.hour
					for minute := c.minute if first_hour else 59; minute >= 0; minute -= 1 {
						if minute not_in s.minutes {
							continue
						}
						first_minute := first_hour && minute == c.minute
						for second := c.second if first_minute else 59; second >= 0; second -= 1 {
							if second in s.seconds {
								return to_time({year, month, day, hour, minute, second})
							}
						}
					}
				}
			}
		}
	}
	return {}, false
}

/*
Iterator walks the fire times of a schedule, forward or backward.

Create one with iterator_make and call iterate until it reports false. An
Iterator owns no memory and needs no cleanup.

Example:
	it := cron.iterator_make(s, from)
	for fire, i in cron.iterate(&it) {
		fmt.println(fire)
		if i == 9 {
			break
		}
	}
*/
Iterator :: struct {
	// The schedule being walked.
	schedule: Schedule,
	// The last time returned, or the starting point before the first call.
	cursor:   time.Time,
	// True to walk toward the past with prev instead of next.
	reverse:  bool,
	// True once the schedule has no more fire times in the walking direction.
	done:     bool,
}

/*
iterator_make returns an Iterator over `s` that starts at `from`.

The first call to iterate returns the first fire time strictly after `from`,
or strictly before it when `reverse` is true.
*/
iterator_make :: proc(s: Schedule, from: time.Time, reverse := false) -> Iterator {
	return {schedule = s, cursor = from, reverse = reverse}
}

/*
iterate returns the next fire time from `it` and advances it.

It returns `ok = false` once the schedule has no more fire times, and keeps
returning false after that. Use it in a `for fire in cron.iterate(&it)` loop.
*/
iterate :: proc(it: ^Iterator) -> (fire: time.Time, ok: bool) {
	if it.done {
		return {}, false
	}
	if it.reverse {
		fire, ok = prev(it.schedule, it.cursor)
	} else {
		fire, ok = next(it.schedule, it.cursor)
	}
	if !ok {
		it.done = true
		return {}, false
	}
	it.cursor = fire
	return fire, true
}

/*
next_n returns up to `count` fire times of `s` strictly after `from`, in order.

Inputs:
- s: the schedule.
- from: the starting point, read as UTC.
- count: how many fire times to collect. Zero or less returns an empty result.
- allocator: allocates the result.

Returns:
- times: the fire times, owned by the caller; free with `delete(times, allocator)`.
  It's shorter than `count` when the schedule runs out of fire times.
- err: `nil`, or an allocator error.
*/
next_n :: proc(
	s: Schedule,
	from: time.Time,
	count: int,
	allocator := context.allocator,
) -> (
	times: []time.Time,
	err: Error,
) {
	if count <= 0 {
		return nil, nil
	}
	times = make([]time.Time, count, allocator) or_return
	it := iterator_make(s, from)
	n := 0
	for fire in iterate(&it) {
		times[n] = fire
		n += 1
		if n == count {
			break
		}
	}
	return times[:n], nil
}

@(private = "file")
Civil :: struct {
	year, month, day, hour, minute, second: int,
}

@(private = "file")
is_empty :: proc(s: Schedule) -> bool {
	no_day :=
		s.days == {} &&
		s.weekdays == {} &&
		s.last_days == {} &&
		s.nearest_weekday == {} &&
		!s.last_weekday &&
		s.last_of_weekday == {} &&
		s.nth_weekday == {}
	return s.seconds == {} || s.minutes == {} || s.hours == {} || s.months == {} || no_day
}

/*
day_matches applies the day-of-month and day-of-week fields to one date.
When either field is unrestricted both must match; otherwise either may.
*/
@(private = "file")
day_matches :: proc(s: Schedule, year, month, day: int) -> bool {
	dim := days_in_month(year, month)
	wd := weekday(year, month, day)

	dom :=
		day in s.days ||
		(dim - day) in s.last_days ||
		(s.last_weekday && day == last_weekday_of(year, month, dim)) ||
		nearest_weekday_matches(s.nearest_weekday, year, month, day, dim)

	dow :=
		wd in s.weekdays ||
		(wd in s.last_of_weekday && day + 7 > dim) ||
		((day - 1) / 7 + 1) in s.nth_weekday[wd]

	if s.any_day || s.any_weekday {
		return dom && dow
	}
	return dom || dow
}

// nearest_weekday_matches reports whether some `nW` item in `set` lands on `day`.
@(private = "file")
nearest_weekday_matches :: proc(set: Day_Set, year, month, day, dim: int) -> bool {
	if set == {} {
		return false
	}
	// A `nW` item moves at most two days, so only nearby n can land here.
	for n in max(day - 2, 1) ..= min(day + 2, dim) {
		if n not_in set {
			continue
		}
		target := n
		switch weekday(year, month, n) {
		case 6:
			// Saturday: use Friday, or Monday when Friday is in the previous month.
			target = n - 1 if n > 1 else n + 2
		case 0:
			// Sunday: use Monday, or Friday when Monday is in the next month.
			target = n + 1 if n < dim else n - 2
		}
		if target == day {
			return true
		}
	}
	return false
}

@(private = "file")
last_weekday_of :: proc(year, month, dim: int) -> int {
	switch weekday(year, month, dim) {
	case 6:
		return dim - 1
	case 0:
		return dim - 2
	}
	return dim
}

@(private = "file")
is_leap :: proc(year: int) -> bool {
	return year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
}

@(private = "file")
days_in_month :: proc(year, month: int) -> int {
	switch month {
	case 2:
		return 29 if is_leap(year) else 28
	case 4, 6, 9, 11:
		return 30
	}
	return 31
}

// weekday returns 0 for Sunday through 6 for Saturday.
@(private = "file")
weekday :: proc(year, month, day: int) -> int {
	// 1970-01-01 was a Thursday.
	return int(floor_mod(days_from_civil(year, month, day) + 4, 7))
}

@(private = "file")
floor_div :: proc(a, b: i64) -> i64 {
	q := a / b
	if (a % b != 0) && ((a < 0) != (b < 0)) {
		q -= 1
	}
	return q
}

@(private = "file")
floor_mod :: proc(a, b: i64) -> i64 {
	return a - floor_div(a, b) * b
}

// days_from_civil counts days since 1970-01-01 in the proleptic Gregorian calendar.
@(private = "file")
days_from_civil :: proc(year, month, day: int) -> i64 {
	y := i64(year) - (1 if month <= 2 else 0)
	era := floor_div(y, 400)
	yoe := y - era * 400
	m := i64(month)
	doy := (153 * (m + (-3 if m > 2 else 9)) + 2) / 5 + i64(day) - 1
	doe := yoe * 365 + yoe / 4 - yoe / 100 + doy
	return era * 146_097 + doe - 719_468
}

@(private = "file")
civil_from_unix :: proc(sec: i64) -> Civil {
	days := floor_div(sec, SECONDS_PER_DAY)
	rem := int(sec - days * SECONDS_PER_DAY)

	z := days + 719_468
	era := floor_div(z, 146_097)
	doe := z - era * 146_097
	yoe := (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365
	doy := doe - (365 * yoe + yoe / 4 - yoe / 100)
	mp := (5 * doy + 2) / 153
	d := doy - (153 * mp + 2) / 5 + 1
	m := mp + (3 if mp < 10 else -9)
	y := yoe + era * 400 + (1 if m <= 2 else 0)

	return {
		year = int(y),
		month = int(m),
		day = int(d),
		hour = rem / 3600,
		minute = rem / 60 % 60,
		second = rem % 60,
	}
}

@(private = "file")
to_time :: proc(c: Civil) -> (t: time.Time, ok: bool) {
	sec := days_from_civil(c.year, c.month, c.day) * SECONDS_PER_DAY + i64(c.hour * 3600 + c.minute * 60 + c.second)
	if sec < MIN_UNIX_SECOND || sec > MAX_UNIX_SECOND {
		return {}, false
	}
	return time.unix(sec, 0), true
}
