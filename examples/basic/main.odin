// Example basic parses a few cron expressions and prints their fire times. Run it with `odin run examples/basic`.
package main

import cron "../.."
import "core:fmt"
import "core:os"
import "core:time"

main :: proc() {
	from, _ := time.components_to_time(2026, 10, 29, 12, 7, 0)

	// Every 15 minutes during office hours, Monday to Friday.
	office, err := cron.parse("0,15,30,45 9-17 * * MON-FRI")
	if err != nil {
		fmt.eprintln("parse failed:", err)
		os.exit(1)
	}
	if fire, ok := cron.next(office, from); ok {
		fmt.println("next office tick:", fire)
	}
	if fire, ok := cron.prev(office, from); ok {
		fmt.println("last office tick:", fire)
	}

	// The next three runs of a job on the last Friday of each month.
	payroll, _ := cron.parse("0 18 * * 5L")
	runs, alloc_err := cron.next_n(payroll, from, 3)
	if alloc_err != nil {
		fmt.eprintln("next_n failed:", alloc_err)
		os.exit(1)
	}
	defer delete(runs)
	for run in runs {
		fmt.println("payroll:", run)
	}

	// Walk a six-field schedule with an iterator; it needs no cleanup.
	ticks, _ := cron.parse("*/20 * * * * *")
	it := cron.iterator_make(ticks, from)
	count := 0
	for fire in cron.iterate(&it) {
		fmt.println("tick:", fire)
		count += 1
		if count == 3 {
			break
		}
	}

	// Run a schedule at midnight in UTC+02:00 by shifting into that offset and back.
	offset := 2 * time.Hour
	morning, _ := cron.parse("@daily")
	if local, ok := cron.next(morning, time.time_add(from, offset)); ok {
		fmt.println("midnight in UTC+02:00 is", time.time_add(local, -offset))
	}

	// Errors name the problem, the field and the byte offset.
	_, bad, loc := cron.parse_with_location("0 25 * * *")
	fmt.printfln("%v in %v at byte %d", bad, loc.field, loc.offset)
}
