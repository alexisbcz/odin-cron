# cron

[![CI](https://github.com/alexisbcz/odin-cron/actions/workflows/ci.yml/badge.svg)](https://github.com/alexisbcz/odin-cron/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Odin](https://img.shields.io/badge/Odin-dev--2026--09-1e5a99.svg)](https://odin-lang.org)

Parse cron expressions and compute their next and previous fire times in Odin, with no allocations, no global state and predictable UTC semantics.

## Install

The repository root is the package, so you can vendor it in two ways.

As a Git submodule inside your project:

```sh
git submodule add https://github.com/alexisbcz/odin-cron libs/cron
```

```odin
import "libs/cron"
```

As a copy in a shared collection that all your projects use:

```sh
git clone https://github.com/alexisbcz/odin-cron ~/odin-shared/cron
odin build . -collection:shared=$HOME/odin-shared
```

```odin
import "shared:cron"
```

## Quick start

```odin
package main

import "core:fmt"
import "core:time"
import "shared:cron"

main :: proc() {
	s, err := cron.parse("0,15,30,45 9-17 * * MON-FRI")
	if err != nil {
		fmt.eprintln("bad expression:", err)
		return
	}

	from, _ := time.components_to_time(2026, 10, 29, 12, 7, 0)
	if fire, ok := cron.next(s, from); ok {
		fmt.println("next:", fire) // 2026-10-29 12:15:00.000000000 +0000 UTC
	}
	if fire, ok := cron.prev(s, from); ok {
		fmt.println("prev:", fire) // 2026-10-29 12:00:00.000000000 +0000 UTC
	}
}
```

## Syntax

An expression has five fields, or six with a leading seconds field:

```text
┌───────────── second (0-59, six-field form only)
│ ┌─────────── minute (0-59)
│ │ ┌───────── hour (0-23)
│ │ │ ┌─────── day of month (1-31)
│ │ │ │ ┌───── month (1-12 or JAN-DEC)
│ │ │ │ │ ┌─── day of week (0-7 or SUN-SAT; 0 and 7 are Sunday)
│ │ │ │ │ │
* * * * * *
```

| Item | Meaning | Example |
| --- | --- | --- |
| `*` | Every value | `* * * * *` fires every minute |
| `a,b` | A list | `0,30 * * * *` fires on the hour and the half hour |
| `a-b` | A range, inclusive | `0 9-17 * * *` fires hourly from 09:00 to 17:00 |
| `*/n`, `a-b/n` | Every n-th value | `*/15 * * * *` fires every 15 minutes |
| `a/n` | Every n-th value from `a` to the end of the field | `0 18/2 * * *` fires at 18:00, 20:00 and 22:00 |
| Names | Months and weekdays, in any case | `0 0 1 JAN,JUL *`, `0 9 * * mon-fri` |
| `?` | Same as `*`, for a whole day field | `0 0 ? * MON` |

Extensions from Quartz:

| Field | Item | Meaning |
| --- | --- | --- |
| Day of month | `L` | The last day of the month |
| Day of month | `L-n` | n days before the last day; `L-1` is the second to last |
| Day of month | `LW` | The last weekday, Monday to Friday, of the month |
| Day of month | `nW` | The weekday nearest to day n, without leaving the month |
| Day of week | `nL` | The last weekday n of the month; `5L` is the last Friday |
| Day of week | `n#k` | The k-th weekday n of the month; `MON#1` is the first Monday |

Macros: `@yearly` and `@annually` (`0 0 1 1 *`), `@monthly` (`0 0 1 * *`), `@weekly` (`0 0 * * 0`), `@daily` and `@midnight` (`0 0 * * *`), and `@hourly` (`0 * * * *`). The library rejects `@reboot` with `Unknown_Macro` because it isn't a time.

When you restrict both day fields, that is, neither starts with `*` or `?`, a day matches if either field matches. So `0 0 1 * FRI` fires on the first of the month and on every Friday. When one of them starts with `*` or `?`, both must match. This is the rule of Vixie cron, the cron most Linux systems run.

## Time zones

The library treats every `time.Time` as a UTC wall clock. It never reads the local time zone, so results are the same on every machine and there are no daylight saving gaps or repeated hours.

To run a schedule in a fixed offset, shift into the offset, compute, and shift back:

```odin
offset := 2 * time.Hour // UTC+02:00
if local, ok := cron.next(s, time.time_add(from, offset)); ok {
	fire := time.time_add(local, -offset) // back in UTC
	fmt.println(fire)
}
```

For a zone with daylight saving time, convert with a time zone library and decide how to handle the skipped and repeated hours yourself.

## API overview

| Declaration | Purpose | Allocates | Free with |
| --- | --- | --- | --- |
| `parse(expr, mode)` | Parse an expression into a `Schedule` | No | Not needed |
| `parse_with_location(expr, mode)` | Parse, and report the field and byte offset of an error | No | Not needed |
| `next(s, t)` | First fire time strictly after `t` | No | Not needed |
| `prev(s, t)` | Last fire time strictly before `t` | No | Not needed |
| `matches(s, t)` | Whether `s` fires at the second that contains `t` | No | Not needed |
| `iterator_make(s, from, reverse)` | Start an `Iterator` over fire times | No | Not needed |
| `iterate(it)` | Next fire time from an `Iterator`, for use in `for` loops | No | Not needed |
| `next_n(s, from, count, allocator)` | Collect up to `count` fire times into a slice | Yes | `delete` |
| `Schedule` | A parsed expression, stored as bit sets; safe to copy and share | No | Not needed |
| `Field_Mode` | `.Auto`, `.Five` or `.Six` fields | No | Not needed |
| `Error` | Union of `Parse_Error` and `runtime.Allocator_Error` | No | Not needed |
| `Location` | The `Field` and byte offset of a parse error | No | Not needed |

`next` and `prev` return `ok = false` when the schedule never fires, as with `0 0 30 2 *`, or when the answer is outside the years 1678 to 2262 that `time.Time` can hold. The search covers one full 400-year cycle of the Gregorian calendar, so a schedule that doesn't fire within it never fires at all.

Errors print as their names, so `fmt.println(err)` shows `Value_Out_Of_Range`. To show where the problem is:

```odin
_, err, loc := cron.parse_with_location("0 25 * * *")
fmt.printfln("%v in %v at byte %d", err, loc.field, loc.offset)
// Value_Out_Of_Range in Hour at byte 2
```

## Examples

Each directory under `examples/` is a runnable program:

```sh
odin run examples/basic
```

## Design notes

- Parsing, `next`, `prev` and `matches` never allocate. Only `next_n` does, through the allocator you pass.
- A `Schedule` is a plain value made of bit sets, so you can copy it, compare it with `==` and read it from several threads at once.
- Fallible procedures return `(T, Error)`. The library never panics on bad input.
- The package keeps no global mutable state and starts no threads. Running jobs on time is up to you: sleep until `next` returns, then run.

## Testing

```sh
odin check . -vet -strict-style -disallow-do -no-entry-point
odin test tests -vet -strict-style -disallow-do
vale sync && vale *.md
```

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md). Commits follow Conventional Commits, and every change that users can see gets a line in [CHANGELOG.md](CHANGELOG.md).

## License

MIT. See [LICENSE](LICENSE).
