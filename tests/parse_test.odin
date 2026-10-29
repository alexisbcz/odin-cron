// Package cron_tests holds the unit tests for cron. Run them with `odin test tests`.
package cron_tests

import cron ".."
import "core:fmt"
import "core:testing"

// must_parse parses `expr` and fails the test if that doesn't succeed.
must_parse :: proc(t: ^testing.T, expr: string, mode := cron.Field_Mode.Auto, loc := #caller_location) -> cron.Schedule {
	s, err := cron.parse(expr, mode)
	testing.expectf(t, err == nil, "parse(%q) failed: %v", expr, err, loc = loc)
	return s
}

// expect_error checks that parsing `expr` fails with `want`.
expect_error :: proc(t: ^testing.T, expr: string, want: cron.Parse_Error, loc := #caller_location) {
	_, err := cron.parse(expr)
	testing.expectf(t, err == cron.Error(want), "parse(%q): got %v, want %v", expr, err, want, loc = loc)
}

@(test)
test_parse_five_fields_fires_at_second_zero :: proc(t: ^testing.T) {
	s := must_parse(t, "30 4 * * *")
	testing.expect_value(t, s.seconds, cron.Second_Set{0})
	testing.expect_value(t, s.minutes, cron.Minute_Set{30})
	testing.expect_value(t, s.hours, cron.Hour_Set{4})
}

@(test)
test_parse_six_fields_reads_seconds_first :: proc(t: ^testing.T) {
	s := must_parse(t, "15 30 4 * * *")
	testing.expect_value(t, s.seconds, cron.Second_Set{15})
	testing.expect_value(t, s.minutes, cron.Minute_Set{30})
	testing.expect_value(t, s.hours, cron.Hour_Set{4})
}

@(test)
test_parse_star_fills_every_field :: proc(t: ^testing.T) {
	s := must_parse(t, "* * * * * *")
	testing.expect_value(t, card(s.seconds), 60)
	testing.expect_value(t, card(s.minutes), 60)
	testing.expect_value(t, card(s.hours), 24)
	testing.expect_value(t, card(s.days), 31)
	testing.expect_value(t, card(s.months), 12)
	testing.expect_value(t, card(s.weekdays), 7)
	testing.expect(t, s.any_day)
	testing.expect(t, s.any_weekday)
}

@(test)
test_parse_list :: proc(t: ^testing.T) {
	s := must_parse(t, "0,15,45 * * * *")
	testing.expect_value(t, s.minutes, cron.Minute_Set{0, 15, 45})
}

@(test)
test_parse_range :: proc(t: ^testing.T) {
	s := must_parse(t, "* 9-12 * * *")
	testing.expect_value(t, s.hours, cron.Hour_Set{9, 10, 11, 12})
}

@(test)
test_parse_step_on_star :: proc(t: ^testing.T) {
	s := must_parse(t, "*/20 * * * *")
	testing.expect_value(t, s.minutes, cron.Minute_Set{0, 20, 40})
}

@(test)
test_parse_step_on_range :: proc(t: ^testing.T) {
	s := must_parse(t, "10-30/10 * * * *")
	testing.expect_value(t, s.minutes, cron.Minute_Set{10, 20, 30})
}

@(test)
test_parse_value_with_step_runs_to_field_end :: proc(t: ^testing.T) {
	s := must_parse(t, "* 18/2 * * *")
	testing.expect_value(t, s.hours, cron.Hour_Set{18, 20, 22})
}

@(test)
test_parse_mixed_list_of_ranges_and_steps :: proc(t: ^testing.T) {
	s := must_parse(t, "1,5-7,50/5 * * * *")
	testing.expect_value(t, s.minutes, cron.Minute_Set{1, 5, 6, 7, 50, 55})
}

@(test)
test_parse_month_names_ignore_case :: proc(t: ^testing.T) {
	s := must_parse(t, "0 0 1 jan,Mar,DEC *")
	testing.expect_value(t, s.months, cron.Month_Set{1, 3, 12})
}

@(test)
test_parse_month_name_range :: proc(t: ^testing.T) {
	s := must_parse(t, "0 0 1 JUN-AUG *")
	testing.expect_value(t, s.months, cron.Month_Set{6, 7, 8})
}

@(test)
test_parse_weekday_name_range :: proc(t: ^testing.T) {
	s := must_parse(t, "0 0 * * MON-FRI")
	testing.expect_value(t, s.weekdays, cron.Weekday_Set{1, 2, 3, 4, 5})
	testing.expect(t, !s.any_weekday)
}

@(test)
test_parse_weekday_seven_is_sunday :: proc(t: ^testing.T) {
	s := must_parse(t, "0 0 * * 7")
	testing.expect_value(t, s.weekdays, cron.Weekday_Set{0})
	s = must_parse(t, "0 0 * * 5-7")
	testing.expect_value(t, s.weekdays, cron.Weekday_Set{0, 5, 6})
}

@(test)
test_parse_weekday_seven_with_step_is_sunday :: proc(t: ^testing.T) {
	// `7/n` runs from 7 to the end of the field, so it can only mean Sunday.
	s := must_parse(t, "0 0 * * 7/2")
	testing.expect_value(t, s.weekdays, cron.Weekday_Set{0})
	s = must_parse(t, "0 0 * * SUN,7/1")
	testing.expect_value(t, s.weekdays, cron.Weekday_Set{0})
}

@(test)
test_parse_accepts_leading_zeros :: proc(t: ^testing.T) {
	s := must_parse(t, "00005 0 * * *")
	testing.expect_value(t, s.minutes, cron.Minute_Set{5})
	s = must_parse(t, "0 0 * * 0000001")
	testing.expect_value(t, s.weekdays, cron.Weekday_Set{1})
	s = must_parse(t, "*/000015 0 * * *")
	testing.expect_value(t, s.minutes, cron.Minute_Set{0, 15, 30, 45})
	expect_error(t, "*/99999999999999999999 * * * *", .Invalid_Step)
}

@(test)
test_parse_weekday_star_step_stays_in_week :: proc(t: ^testing.T) {
	s := must_parse(t, "0 0 * * */2")
	testing.expect_value(t, s.weekdays, cron.Weekday_Set{0, 2, 4, 6})
}

@(test)
test_parse_question_mark_is_unrestricted :: proc(t: ^testing.T) {
	s := must_parse(t, "0 0 ? * MON")
	testing.expect(t, s.any_day)
	testing.expect_value(t, card(s.days), 31)
	s = must_parse(t, "0 0 1 * ?")
	testing.expect(t, s.any_weekday)
	testing.expect_value(t, card(s.weekdays), 7)
}

@(test)
test_parse_macros :: proc(t: ^testing.T) {
	Case :: struct {
		macro, equivalent: string,
	}
	cases := [?]Case {
		{"@yearly", "0 0 1 1 *"},
		{"@annually", "0 0 1 1 *"},
		{"@monthly", "0 0 1 * *"},
		{"@weekly", "0 0 * * 0"},
		{"@daily", "0 0 * * *"},
		{"@midnight", "0 0 * * *"},
		{"@hourly", "0 * * * *"},
	}
	for c in cases {
		got := must_parse(t, c.macro)
		want := must_parse(t, c.equivalent)
		testing.expectf(t, got == want, "%s should equal %q", c.macro, c.equivalent)
	}
}

@(test)
test_parse_macro_ignores_case_and_mode :: proc(t: ^testing.T) {
	a := must_parse(t, "@DAILY", .Six)
	b := must_parse(t, "0 0 * * *")
	testing.expect(t, a == b)
}

@(test)
test_parse_accepts_tabs_and_extra_spaces :: proc(t: ^testing.T) {
	a := must_parse(t, "  5\t\t4   *  * *\n")
	b := must_parse(t, "5 4 * * *")
	testing.expect(t, a == b)
}

@(test)
test_parse_last_day_of_month :: proc(t: ^testing.T) {
	s := must_parse(t, "0 0 L * *")
	testing.expect_value(t, s.last_days, cron.Last_Offset_Set{0})
	testing.expect_value(t, s.days, cron.Day_Set{})
	testing.expect(t, !s.any_day)
}

@(test)
test_parse_last_day_offset_in_list :: proc(t: ^testing.T) {
	s := must_parse(t, "0 0 1,L-3,l * *")
	testing.expect_value(t, s.days, cron.Day_Set{1})
	testing.expect_value(t, s.last_days, cron.Last_Offset_Set{0, 3})
}

@(test)
test_parse_last_weekday_of_month :: proc(t: ^testing.T) {
	s := must_parse(t, "0 0 LW * *")
	testing.expect(t, s.last_weekday)
}

@(test)
test_parse_nearest_weekday :: proc(t: ^testing.T) {
	s := must_parse(t, "0 0 1W,15w * *")
	testing.expect_value(t, s.nearest_weekday, cron.Day_Set{1, 15})
}

@(test)
test_parse_last_of_weekday :: proc(t: ^testing.T) {
	s := must_parse(t, "0 0 * * 5L,SUNL")
	testing.expect_value(t, s.last_of_weekday, cron.Weekday_Set{0, 5})
}

@(test)
test_parse_nth_weekday :: proc(t: ^testing.T) {
	s := must_parse(t, "0 0 * * MON#1,1#3,7#5")
	testing.expect_value(t, s.nth_weekday[1], cron.Week_Set{1, 3})
	testing.expect_value(t, s.nth_weekday[0], cron.Week_Set{5})
}

@(test)
test_parse_mode_five_rejects_six_fields :: proc(t: ^testing.T) {
	_, err := cron.parse("0 0 0 * * *", .Five)
	testing.expect_value(t, err, cron.Error(cron.Parse_Error.Wrong_Field_Count))
	_, err = cron.parse("0 0 * * *", .Five)
	testing.expect_value(t, err, nil)
}

@(test)
test_parse_mode_six_rejects_five_fields :: proc(t: ^testing.T) {
	_, err := cron.parse("0 0 * * *", .Six)
	testing.expect_value(t, err, cron.Error(cron.Parse_Error.Wrong_Field_Count))
}

@(test)
test_parse_rejects_empty_expression :: proc(t: ^testing.T) {
	expect_error(t, "", .Empty_Expression)
	expect_error(t, " \t\n", .Empty_Expression)
}

@(test)
test_parse_rejects_wrong_field_count :: proc(t: ^testing.T) {
	expect_error(t, "* * * *", .Wrong_Field_Count)
	expect_error(t, "* * * * * * *", .Wrong_Field_Count)
	expect_error(t, "*", .Wrong_Field_Count)
}

@(test)
test_parse_rejects_unknown_macro :: proc(t: ^testing.T) {
	expect_error(t, "@reboot", .Unknown_Macro)
	expect_error(t, "@every 5m", .Unknown_Macro)
	expect_error(t, "@", .Unknown_Macro)
	expect_error(t, "@daily *", .Unknown_Macro)
}

@(test)
test_parse_rejects_empty_list_item :: proc(t: ^testing.T) {
	expect_error(t, "1,,2 * * * *", .Empty_Item)
	expect_error(t, "1, * * * *", .Empty_Item)
	expect_error(t, ",1 * * * *", .Empty_Item)
}

@(test)
test_parse_rejects_invalid_values :: proc(t: ^testing.T) {
	expect_error(t, "abc * * * *", .Invalid_Value)
	expect_error(t, "1x * * * *", .Invalid_Value)
	expect_error(t, "-5 * * * *", .Invalid_Value)
	expect_error(t, "5- * * * *", .Invalid_Value)
	expect_error(t, "+5 * * * *", .Invalid_Value)
	expect_error(t, "0 0 * MON *", .Invalid_Value)
	expect_error(t, "0 0 * * JAN", .Invalid_Value)
	expect_error(t, "0 0 * * MONDAY", .Invalid_Value)
}

@(test)
test_parse_rejects_values_out_of_range :: proc(t: ^testing.T) {
	expect_error(t, "60 * * * *", .Value_Out_Of_Range)
	expect_error(t, "* 24 * * *", .Value_Out_Of_Range)
	expect_error(t, "* * 0 * *", .Value_Out_Of_Range)
	expect_error(t, "* * 32 * *", .Value_Out_Of_Range)
	expect_error(t, "* * * 0 *", .Value_Out_Of_Range)
	expect_error(t, "* * * 13 *", .Value_Out_Of_Range)
	expect_error(t, "* * * * 8", .Value_Out_Of_Range)
	expect_error(t, "60 * * * * *", .Value_Out_Of_Range)
	expect_error(t, "99999999999999999999 * * * *", .Value_Out_Of_Range)
}

@(test)
test_parse_rejects_backward_range :: proc(t: ^testing.T) {
	expect_error(t, "30-10 * * * *", .Invalid_Range)
	expect_error(t, "0 0 * * FRI-MON", .Invalid_Range)
}

@(test)
test_parse_rejects_invalid_steps :: proc(t: ^testing.T) {
	expect_error(t, "*/0 * * * *", .Invalid_Step)
	expect_error(t, "*/ * * * *", .Invalid_Step)
	expect_error(t, "*/x * * * *", .Invalid_Step)
	expect_error(t, "*/61 * * * *", .Invalid_Step)
	expect_error(t, "* */25 * * *", .Invalid_Step)
	expect_error(t, "1/2/3 * * * *", .Invalid_Step)
	expect_error(t, "0 0 * * */8", .Invalid_Step)
}

@(test)
test_parse_rejects_misplaced_question_mark :: proc(t: ^testing.T) {
	expect_error(t, "? * * * *", .Invalid_Question_Mark)
	expect_error(t, "0 0 ?/2 * *", .Invalid_Question_Mark)
	expect_error(t, "0 0 ?,1 * *", .Invalid_Question_Mark)
	expect_error(t, "0 0 1,? * *", .Invalid_Question_Mark)
}

@(test)
test_parse_rejects_misused_last :: proc(t: ^testing.T) {
	expect_error(t, "0 L * * *", .Invalid_Last)
	expect_error(t, "0 0 * * L", .Invalid_Last)
	expect_error(t, "0 0 LX * *", .Invalid_Last)
	expect_error(t, "0 0 L-x * *", .Invalid_Last)
	expect_error(t, "0 0 5L * *", .Invalid_Last)
	expect_error(t, "0 0 L/2 * *", .Invalid_Last)
	expect_error(t, "0 0 * * XL", .Invalid_Last)
	expect_error(t, "0 0 L-31 * *", .Value_Out_Of_Range)
	expect_error(t, "0 0 * * 8L", .Value_Out_Of_Range)
}

@(test)
test_parse_rejects_misused_nearest_weekday :: proc(t: ^testing.T) {
	expect_error(t, "0 0 W * *", .Invalid_Nearest_Weekday)
	expect_error(t, "0 0 xW * *", .Invalid_Nearest_Weekday)
	expect_error(t, "0 0 * * 5W", .Invalid_Nearest_Weekday)
	expect_error(t, "0 0 0W * *", .Value_Out_Of_Range)
	expect_error(t, "0 0 32W * *", .Value_Out_Of_Range)
}

@(test)
test_parse_rejects_misused_nth_weekday :: proc(t: ^testing.T) {
	expect_error(t, "0 0 * * 5#0", .Invalid_Nth_Weekday)
	expect_error(t, "0 0 * * 5#6", .Invalid_Nth_Weekday)
	expect_error(t, "0 0 * * 5#", .Invalid_Nth_Weekday)
	expect_error(t, "0 0 * * #2", .Invalid_Nth_Weekday)
	expect_error(t, "0 0 1#2 * *", .Invalid_Nth_Weekday)
	expect_error(t, "0 0 * * 9#2", .Value_Out_Of_Range)
}

@(test)
test_parse_with_location_reports_field_and_offset :: proc(t: ^testing.T) {
	_, err, loc := cron.parse_with_location("0 12 * 1,13 *")
	testing.expect_value(t, err, cron.Error(cron.Parse_Error.Value_Out_Of_Range))
	testing.expect_value(t, loc.field, cron.Field.Month)
	testing.expect_value(t, loc.offset, 9)

	_, err, loc = cron.parse_with_location("  5 0 0 * * MON#9")
	testing.expect_value(t, err, cron.Error(cron.Parse_Error.Invalid_Nth_Weekday))
	testing.expect_value(t, loc.field, cron.Field.Day_Of_Week)
	testing.expect_value(t, loc.offset, 12)
}

@(test)
test_parse_with_location_is_zero_on_success :: proc(t: ^testing.T) {
	_, err, loc := cron.parse_with_location("0 0 * * *")
	testing.expect_value(t, err, nil)
	testing.expect_value(t, loc, cron.Location{})
}

@(test)
test_parse_error_prints_its_name :: proc(t: ^testing.T) {
	_, err := cron.parse("5-1 * * * *")
	testing.expect_value(t, fmt.tprint(err), "Invalid_Range")
	free_all(context.temp_allocator)
}
