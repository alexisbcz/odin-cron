# Changelog

This file records all notable changes to this project.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.1] - 2026-10-29

### Fixed

- A day-of-week `7/n` item, such as `7/2`, now means Sunday. It used to match no day, so the schedule never fired on it.
- Numbers with more than four digits, such as `00005` or `*/000015`, now parse by value. They used to fail with `Value_Out_Of_Range` or `Invalid_Step`.
- `next_n` now returns a slice whose allocation is exactly `len(times)` long, and `nil` with nothing allocated when there are no fire times. It used to keep `count` elements allocated and return a shorter slice, so `delete` freed it with the wrong size.

## [0.1.0] - 2026-10-29

### Added

- `parse` and `parse_with_location` for five-field and six-field cron expressions, with lists, ranges, steps, month and weekday names, and `?` in the day fields.
- The `@yearly`, `@annually`, `@monthly`, `@weekly`, `@daily`, `@midnight` and `@hourly` macros.
- The Quartz extensions `L`, `L-n`, `LW` and `nW` for the day of month, and `nL` and `n#k` for the day of week.
- `next`, `prev` and `matches`, which treat every `time.Time` as UTC.
- `Iterator`, `iterator_make` and `iterate` for walking fire times forward or backward.
- `next_n`, which collects fire times into a slice from the allocator you pass.
- A `Parse_Error` value for each kind of malformed input, and a `Location` with the field and byte offset.

[Unreleased]: https://github.com/alexisbcz/odin-cron/compare/v0.1.1...HEAD
[0.1.1]: https://github.com/alexisbcz/odin-cron/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/alexisbcz/odin-cron/releases/tag/v0.1.0
