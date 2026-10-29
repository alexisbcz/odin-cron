package cron_tests

import cron ".."
import "core:mem"
import "core:testing"
import "core:time"

// at builds a UTC time and fails the test if the components are invalid.
at :: proc(t: ^testing.T, year, month, day, hour, minute, second: int, nsec := 0, loc := #caller_location) -> time.Time {
	tm, ok := time.components_to_time(year, month, day, hour, minute, second, nsec)
	testing.expect(t, ok, "invalid test time", loc = loc)
	return tm
}

// expect_next checks that `expr` next fires at `want` after `from`.
expect_next :: proc(t: ^testing.T, expr: string, from, want: time.Time, loc := #caller_location) {
	s := must_parse(t, expr, loc = loc)
	got, ok := cron.next(s, from)
	testing.expectf(t, ok, "next(%q) found nothing", expr, loc = loc)
	testing.expectf(t, got == want, "next(%q) = %v, want %v", expr, got, want, loc = loc)
}

// expect_prev checks that `expr` last fired at `want` before `from`.
expect_prev :: proc(t: ^testing.T, expr: string, from, want: time.Time, loc := #caller_location) {
	s := must_parse(t, expr, loc = loc)
	got, ok := cron.prev(s, from)
	testing.expectf(t, ok, "prev(%q) found nothing", expr, loc = loc)
	testing.expectf(t, got == want, "prev(%q) = %v, want %v", expr, got, want, loc = loc)
}

@(test)
test_next_every_minute :: proc(t: ^testing.T) {
	expect_next(t, "* * * * *", at(t, 2026, 10, 29, 12, 7, 30), at(t, 2026, 10, 29, 12, 8, 0))
}

@(test)
test_next_is_strictly_after_a_match :: proc(t: ^testing.T) {
	expect_next(t, "0 12 * * *", at(t, 2026, 10, 29, 12, 0, 0), at(t, 2026, 10, 30, 12, 0, 0))
}

@(test)
test_next_ignores_fraction_of_a_second :: proc(t: ^testing.T) {
	expect_next(t, "* * * * * *", at(t, 2026, 10, 29, 12, 0, 0, 999_999_999), at(t, 2026, 10, 29, 12, 0, 1))
}

@(test)
test_next_rolls_over_into_next_year :: proc(t: ^testing.T) {
	expect_next(t, "*/30 * * * *", at(t, 2026, 12, 31, 23, 45, 0), at(t, 2027, 1, 1, 0, 0, 0))
}

@(test)
test_next_skips_to_monday_for_weekdays :: proc(t: ^testing.T) {
	// 2026-10-30 is a Friday.
	expect_next(t, "0 18 * * MON-FRI", at(t, 2026, 10, 30, 19, 0, 0), at(t, 2026, 11, 2, 18, 0, 0))
}

@(test)
test_next_restricted_day_fields_use_or :: proc(t: ^testing.T) {
	// Day 1 or any Friday: November 1st, a Sunday, comes before Friday the 6th.
	expect_next(t, "0 0 1 * FRI", at(t, 2026, 10, 30, 0, 0, 0), at(t, 2026, 11, 1, 0, 0, 0))
}

@(test)
test_next_star_day_field_uses_and :: proc(t: ^testing.T) {
	// Odd days that are also Mondays. November 2nd is even, November 9th is odd.
	expect_next(t, "0 0 */2 * MON", at(t, 2026, 10, 29, 0, 0, 0), at(t, 2026, 11, 9, 0, 0, 0))
}

@(test)
test_next_question_mark_matches_any_day :: proc(t: ^testing.T) {
	expect_next(t, "0 0 ? * WED", at(t, 2026, 10, 29, 0, 0, 0), at(t, 2026, 11, 4, 0, 0, 0))
}

@(test)
test_next_finds_leap_day :: proc(t: ^testing.T) {
	expect_next(t, "0 0 29 2 *", at(t, 2026, 10, 29, 0, 0, 0), at(t, 2028, 2, 29, 0, 0, 0))
}

@(test)
test_next_century_leap_rules :: proc(t: ^testing.T) {
	// 2100 isn't a leap year, so after 2096 the next February 29th is in 2104.
	expect_next(t, "0 0 29 2 *", at(t, 2096, 3, 1, 0, 0, 0), at(t, 2104, 2, 29, 0, 0, 0))
}

@(test)
test_next_impossible_date_returns_false :: proc(t: ^testing.T) {
	s := must_parse(t, "0 0 30 2 *")
	_, ok := cron.next(s, at(t, 2026, 1, 1, 0, 0, 0))
	testing.expect(t, !ok)
}

@(test)
test_next_day_31_skips_short_months :: proc(t: ^testing.T) {
	expect_next(t, "0 0 31 * *", at(t, 2026, 10, 31, 0, 0, 0), at(t, 2026, 12, 31, 0, 0, 0))
}

@(test)
test_next_last_day_of_month :: proc(t: ^testing.T) {
	expect_next(t, "0 0 L * *", at(t, 2027, 2, 1, 0, 0, 0), at(t, 2027, 2, 28, 0, 0, 0))
	expect_next(t, "0 0 L * *", at(t, 2028, 2, 1, 0, 0, 0), at(t, 2028, 2, 29, 0, 0, 0))
}

@(test)
test_next_last_day_offset :: proc(t: ^testing.T) {
	expect_next(t, "0 0 L-2 * *", at(t, 2026, 10, 1, 0, 0, 0), at(t, 2026, 10, 29, 0, 0, 0))
}

@(test)
test_next_last_weekday_of_month :: proc(t: ^testing.T) {
	// January 31st, 2026 is a Saturday; October 31st, 2027 is a Sunday.
	expect_next(t, "0 0 LW * *", at(t, 2026, 1, 1, 0, 0, 0), at(t, 2026, 1, 30, 0, 0, 0))
	expect_next(t, "0 0 LW * *", at(t, 2027, 10, 1, 0, 0, 0), at(t, 2027, 10, 29, 0, 0, 0))
}

@(test)
test_next_nearest_weekday_moves_off_weekends :: proc(t: ^testing.T) {
	// 2026-08-15 is a Saturday, so 15W fires on Friday the 14th.
	expect_next(t, "0 0 15W * *", at(t, 2026, 8, 1, 0, 0, 0), at(t, 2026, 8, 14, 0, 0, 0))
	// 2026-11-15 is a Sunday, so 15W fires on Monday the 16th.
	expect_next(t, "0 0 15W * *", at(t, 2026, 11, 1, 0, 0, 0), at(t, 2026, 11, 16, 0, 0, 0))
	// 2026-10-15 is a Thursday, so 15W stays put.
	expect_next(t, "0 0 15W * *", at(t, 2026, 10, 1, 0, 0, 0), at(t, 2026, 10, 15, 0, 0, 0))
}

@(test)
test_next_nearest_weekday_stays_in_month :: proc(t: ^testing.T) {
	// 2026-08-01 is a Saturday: 1W moves forward to Monday the 3rd, not back into July.
	expect_next(t, "0 0 1W * *", at(t, 2026, 7, 31, 0, 0, 0), at(t, 2026, 8, 3, 0, 0, 0))
	// 2026-05-31 is a Sunday: 31W moves back to Friday the 29th, not into June.
	expect_next(t, "0 0 31W * *", at(t, 2026, 5, 1, 0, 0, 0), at(t, 2026, 5, 29, 0, 0, 0))
}

@(test)
test_next_last_friday_of_month :: proc(t: ^testing.T) {
	expect_next(t, "0 0 * * 5L", at(t, 2026, 10, 1, 0, 0, 0), at(t, 2026, 10, 30, 0, 0, 0))
	expect_next(t, "0 0 * * FRIL", at(t, 2026, 10, 31, 0, 0, 0), at(t, 2026, 11, 27, 0, 0, 0))
}

@(test)
test_next_first_monday_of_month :: proc(t: ^testing.T) {
	expect_next(t, "0 9 * * MON#1", at(t, 2026, 10, 29, 0, 0, 0), at(t, 2026, 11, 2, 9, 0, 0))
}

@(test)
test_next_fifth_weekday_is_rare :: proc(t: ^testing.T) {
	// October 2026 has five Fridays; November 2026 has none on the fifth week.
	expect_next(t, "0 0 * * 5#5", at(t, 2026, 10, 1, 0, 0, 0), at(t, 2026, 10, 30, 0, 0, 0))
	expect_next(t, "0 0 * * 5#5", at(t, 2026, 10, 30, 0, 0, 0), at(t, 2027, 1, 29, 0, 0, 0))
}

@(test)
test_next_with_seconds_field :: proc(t: ^testing.T) {
	expect_next(t, "*/15 * * * * *", at(t, 2026, 10, 29, 12, 0, 46), at(t, 2026, 10, 29, 12, 1, 0))
	expect_next(t, "5,10 30 * * * *", at(t, 2026, 10, 29, 12, 30, 5), at(t, 2026, 10, 29, 12, 30, 10))
}

@(test)
test_next_macro_weekly :: proc(t: ^testing.T) {
	// 2026-10-29 is a Thursday; @weekly fires at midnight on Sundays.
	expect_next(t, "@weekly", at(t, 2026, 10, 29, 8, 0, 0), at(t, 2026, 11, 1, 0, 0, 0))
}

@(test)
test_next_before_unix_epoch :: proc(t: ^testing.T) {
	expect_next(t, "* * * * *", at(t, 1969, 12, 31, 23, 59, 30), at(t, 1970, 1, 1, 0, 0, 0))
	expect_next(t, "0 0 1 1 *", at(t, 1900, 6, 1, 0, 0, 0), at(t, 1901, 1, 1, 0, 0, 0))
}

@(test)
test_next_past_end_of_time_returns_false :: proc(t: ^testing.T) {
	s := must_parse(t, "0 0 1 1 *")
	_, ok := cron.next(s, at(t, 2262, 1, 1, 0, 0, 0))
	testing.expect(t, !ok)
}

@(test)
test_next_empty_schedule_returns_false :: proc(t: ^testing.T) {
	_, ok := cron.next(cron.Schedule{}, at(t, 2026, 1, 1, 0, 0, 0))
	testing.expect(t, !ok)
	_, ok = cron.prev(cron.Schedule{}, at(t, 2026, 1, 1, 0, 0, 0))
	testing.expect(t, !ok)
}

@(test)
test_prev_every_minute :: proc(t: ^testing.T) {
	expect_prev(t, "* * * * *", at(t, 2026, 10, 29, 12, 7, 30), at(t, 2026, 10, 29, 12, 7, 0))
}

@(test)
test_prev_is_strictly_before_a_match :: proc(t: ^testing.T) {
	expect_prev(t, "0 12 * * *", at(t, 2026, 10, 29, 12, 0, 0), at(t, 2026, 10, 28, 12, 0, 0))
}

@(test)
test_prev_with_fraction_returns_same_second :: proc(t: ^testing.T) {
	expect_prev(t, "0 12 * * *", at(t, 2026, 10, 29, 12, 0, 0, 1), at(t, 2026, 10, 29, 12, 0, 0))
}

@(test)
test_prev_rolls_back_into_previous_year :: proc(t: ^testing.T) {
	expect_prev(t, "59 23 L * *", at(t, 2027, 1, 15, 0, 0, 0), at(t, 2026, 12, 31, 23, 59, 0))
}

@(test)
test_prev_extensions :: proc(t: ^testing.T) {
	expect_prev(t, "0 0 * * 5L", at(t, 2026, 10, 29, 0, 0, 0), at(t, 2026, 9, 25, 0, 0, 0))
	expect_prev(t, "0 0 15W * *", at(t, 2026, 11, 30, 0, 0, 0), at(t, 2026, 11, 16, 0, 0, 0))
}

@(test)
test_prev_impossible_date_returns_false :: proc(t: ^testing.T) {
	s := must_parse(t, "0 0 31 4 *")
	_, ok := cron.prev(s, at(t, 2026, 1, 1, 0, 0, 0))
	testing.expect(t, !ok)
}

@(test)
test_prev_before_start_of_time_returns_false :: proc(t: ^testing.T) {
	s := must_parse(t, "0 0 1 1 *")
	_, ok := cron.prev(s, at(t, 1678, 1, 1, 0, 0, 0))
	testing.expect(t, !ok)
}

@(test)
test_next_and_prev_are_inverse :: proc(t: ^testing.T) {
	s := must_parse(t, "7 */3 1-10 * MON")
	cursor := at(t, 2026, 1, 1, 0, 0, 0)
	for _ in 0 ..< 50 {
		fire, ok := cron.next(s, cursor)
		testing.expect(t, ok)
		back, back_ok := cron.prev(s, time.time_add(fire, time.Second))
		testing.expect(t, back_ok)
		testing.expect_value(t, back, fire)
		testing.expect(t, cron.matches(s, fire))
		cursor = fire
	}
}

@(test)
test_matches :: proc(t: ^testing.T) {
	s := must_parse(t, "30 9 * * MON-FRI")
	testing.expect(t, cron.matches(s, at(t, 2026, 10, 29, 9, 30, 0)))
	testing.expect(t, cron.matches(s, at(t, 2026, 10, 29, 9, 30, 0, 500_000_000)))
	testing.expect(t, !cron.matches(s, at(t, 2026, 10, 29, 9, 30, 1)))
	testing.expect(t, !cron.matches(s, at(t, 2026, 10, 31, 9, 30, 0)))
}

@(test)
test_iterator_walks_forward :: proc(t: ^testing.T) {
	s := must_parse(t, "0 0 1 * *")
	it := cron.iterator_make(s, at(t, 2026, 10, 29, 0, 0, 0))
	want := [?]time.Time{at(t, 2026, 11, 1, 0, 0, 0), at(t, 2026, 12, 1, 0, 0, 0), at(t, 2027, 1, 1, 0, 0, 0)}
	for w in want {
		got, ok := cron.iterate(&it)
		testing.expect(t, ok)
		testing.expect_value(t, got, w)
	}
}

@(test)
test_iterator_walks_backward :: proc(t: ^testing.T) {
	s := must_parse(t, "@hourly")
	it := cron.iterator_make(s, at(t, 2026, 10, 29, 1, 30, 0), reverse = true)
	a, _ := cron.iterate(&it)
	b, _ := cron.iterate(&it)
	testing.expect_value(t, a, at(t, 2026, 10, 29, 1, 0, 0))
	testing.expect_value(t, b, at(t, 2026, 10, 29, 0, 0, 0))
}

@(test)
test_iterator_stays_done :: proc(t: ^testing.T) {
	s := must_parse(t, "0 0 1 1 *")
	it := cron.iterator_make(s, at(t, 2261, 6, 1, 0, 0, 0))
	count := 0
	for _ in cron.iterate(&it) {
		count += 1
	}
	testing.expect_value(t, count, 1) // 2262-01-01; 2263 is past the end of time.Time.
	testing.expect(t, it.done)
	_, ok := cron.iterate(&it)
	testing.expect(t, !ok)
}

@(test)
test_next_n_collects_in_order_without_leaks :: proc(t: ^testing.T) {
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	defer mem.tracking_allocator_destroy(&track)
	allocator := mem.tracking_allocator(&track)

	s := must_parse(t, "0 */6 * * *")
	times, err := cron.next_n(s, at(t, 2026, 10, 29, 5, 0, 0), 4, allocator)
	testing.expect_value(t, err, nil)
	testing.expect_value(t, len(times), 4)
	if len(times) == 4 {
		testing.expect_value(t, times[0], at(t, 2026, 10, 29, 6, 0, 0))
		testing.expect_value(t, times[3], at(t, 2026, 10, 30, 0, 0, 0))
	}
	delete(times, allocator)

	testing.expect_value(t, len(track.allocation_map), 0)
	testing.expect_value(t, len(track.bad_free_array), 0)
}

@(test)
test_next_n_stops_when_schedule_runs_out :: proc(t: ^testing.T) {
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	defer mem.tracking_allocator_destroy(&track)
	allocator := mem.tracking_allocator(&track)

	s := must_parse(t, "0 0 1 1 *")
	times, err := cron.next_n(s, at(t, 2260, 6, 1, 0, 0, 0), 5, allocator)
	testing.expect_value(t, err, nil)
	testing.expect_value(t, len(times), 2)
	delete(times, allocator)

	testing.expect_value(t, len(track.allocation_map), 0)
	testing.expect_value(t, len(track.bad_free_array), 0)
}

@(test)
test_next_n_with_zero_count_allocates_nothing :: proc(t: ^testing.T) {
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	defer mem.tracking_allocator_destroy(&track)

	s := must_parse(t, "* * * * *")
	times, err := cron.next_n(s, at(t, 2026, 1, 1, 0, 0, 0), 0, mem.tracking_allocator(&track))
	testing.expect_value(t, err, nil)
	testing.expect(t, times == nil)
	testing.expect_value(t, track.total_allocation_count, 0)
}

@(test)
test_next_n_reports_allocator_failure :: proc(t: ^testing.T) {
	s := must_parse(t, "* * * * *")
	failing := mem.Allocator{procedure = out_of_memory_allocator_proc}
	times, err := cron.next_n(s, at(t, 2026, 1, 1, 0, 0, 0), 3, failing)
	testing.expect(t, times == nil)
	testing.expect_value(t, err, cron.Error(mem.Allocator_Error.Out_Of_Memory))
}

// out_of_memory_allocator_proc refuses every allocation, to exercise error paths.
out_of_memory_allocator_proc :: proc(
	allocator_data: rawptr,
	mode: mem.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	loc := #caller_location,
) -> (
	[]byte,
	mem.Allocator_Error,
) {
	#partial switch mode {
	case .Free, .Free_All:
		return nil, .None
	}
	return nil, .Out_Of_Memory
}

@(test)
test_next_and_prev_agree_with_minute_scan :: proc(t: ^testing.T) {
	exprs := [?]string{"*/7 3-5 * * *", "0 0 L,15 * *", "30 12 * * MON#2,FRIL", "0 9 1W,LW * *", "@daily", "15 */5 */3 * SAT,SUN"}
	start := at(t, 2026, 2, 20, 0, 0, 0)
	MINUTES :: 60 * 24 * 45
	for expr in exprs {
		s := must_parse(t, expr)
		// fires holds every matching minute in the window, found by brute force.
		fires: [dynamic]time.Time
		defer delete(fires)
		for i in 0 ..< MINUTES {
			m := time.time_add(start, time.Duration(i) * time.Minute)
			if cron.matches(s, m) {
				append(&fires, m)
			}
		}
		testing.expectf(t, len(fires) > 1, "%q never fired in the window", expr)
		for k in 0 ..< len(fires) - 1 {
			got, _ := cron.next(s, fires[k])
			testing.expectf(t, got == fires[k + 1], "next(%q, %v) = %v, want %v", expr, fires[k], got, fires[k + 1])
			back, _ := cron.prev(s, fires[k + 1])
			testing.expectf(t, back == fires[k], "prev(%q, %v) = %v, want %v", expr, fires[k + 1], back, fires[k])
		}
	}
}

@(test)
test_next_n_allocation_matches_result_length :: proc(t: ^testing.T) {
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	defer mem.tracking_allocator_destroy(&track)
	allocator := mem.tracking_allocator(&track)

	// Only two fire times remain before the end of time.Time, out of five asked for.
	s := must_parse(t, "0 0 1 1 *")
	times, err := cron.next_n(s, at(t, 2260, 6, 1, 0, 0, 0), 5, allocator)
	testing.expect_value(t, err, nil)
	testing.expect_value(t, len(times), 2)
	// The caller frees with `delete(times)`, which passes len(times) as the size,
	// so the block must be exactly that long.
	testing.expect_value(t, track.current_memory_allocated, i64(len(times) * size_of(time.Time)))
	delete(times, allocator)
	testing.expect_value(t, len(track.allocation_map), 0)
}

@(test)
test_next_n_with_no_fire_times_keeps_no_memory :: proc(t: ^testing.T) {
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	defer mem.tracking_allocator_destroy(&track)

	s := must_parse(t, "0 0 30 2 *")
	times, err := cron.next_n(s, at(t, 2026, 1, 1, 0, 0, 0), 1000, mem.tracking_allocator(&track))
	testing.expect_value(t, err, nil)
	testing.expect(t, times == nil)
	testing.expect_value(t, len(track.allocation_map), 0)
	testing.expect_value(t, len(track.bad_free_array), 0)
}
