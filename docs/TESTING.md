# Testing

**Read this before trusting any claim about correctness in this repo.**

---

## Status: nothing has ever been executed

The test suites below were written but **never run**. The environment had no
Flutter or Dart SDK. Treat them as unverified specifications of intent, not as
passing tests.

```bash
flutter pub get
flutter test                          # all suites
flutter test test/fuel_calculator_test.dart   # the one that matters most
```

---

## What was verified, and how

Since compilation was impossible, these mechanical checks were run instead over
the whole tree. All passed at the last commit.

| Check | Method |
|---|---|
| Every relative import resolves to a real file | path resolution over all `import '...'` |
| Every `package:` import is a declared dependency | cross-referenced against `pubspec.yaml` |
| Every cross-file symbol is imported where used | symbol→defining-file map, checked per file |
| No unused imports | reverse check per file |
| Brackets balanced | `{}`, `()`, `[]` counted per file |
| Quote style consistent | `prefer_single_quotes` sweep |
| Null-promotion correctness | manual audit; public fields do not promote, so `!` is used |
| Flutter API stability | avoided APIs mid-rename (see [DECISIONS.md](DECISIONS.md) §D7) |

**What this does not cover:** method signatures, named-parameter names, type
inference, generic variance, const-correctness, whether any widget lays out
sensibly, and whether the app starts. A compiler and a device cover those.

---

## Suites

### `fuel_calculator_test.dart` — the important one

The economy engine ([DECISIONS.md](DECISIONS.md) §D3). If only one suite runs,
make it this one.

- Empty log, single entry → no average (not `0.0`)
- Two full tanks → one point using the **closing** fill's volume, not the
  opening one
- Partial fill rolls into the next full-tank window; `fillCount` reflects it
- Entries before the first full tank are skipped
- Input order does not matter
- A missed fill voids its window and restarts the chain
- Missed litres still count toward total fuel and spend
- **Lifetime average is distance-weighted, not the mean of windows** — the
  fixture is deliberately lopsided so the two answers differ
- Measured totals exclude unmeasurable stretches
- Best / worst / latest selection; average price; range estimate
- Monthly spend bucketing; trend calculation
- Outlier flagging against the median; never with fewer than 3 windows
- Two fills at the same odometer warn instead of dividing by zero
- Trip-meter cross-check, both agreeing and disagreeing
- `lastOdometer`, `previousEntry`, `simpleAverage`, `fuelNeeded`/`rangeFor`,
  `rollingAverage`

### `units_test.dart`
Conversion factors and round-trips for every unit; mpg definitional values;
`L/100km` reciprocal behaviour and its infinity guard; `UnitFormatter` display
strings, input parsing, and the raw numeric accessors used by charts.

### `formatters_test.dart`
Number grouping, compact numbers, currency, all date formats, relative dates,
durations; `parseFlexibleDouble` across `1,234.56` / `1.234,56` / `12,5` /
`$1,234.50`; all validators.

### `models_test.dart`
`toMap`/`fromMap` round-trips including nulls; boolean↔integer columns;
`copyWith` clearing optional fields via the `_unset` sentinel; unknown enum
values falling back rather than throwing; `AppSettings` key/value round-trip.

### `service_planner_test.dart`
Overdue / due-soon / upcoming thresholds; whichever limit is worse deciding the
status; due-today counting as overdue; distance reminders skipped when the
odometer is unknown; urgency ordering; cost totals; suggested next-due.

### `station_analyzer_test.dart`
Case/whitespace-insensitive station grouping; per-station totals; recency
ordering for suggestions; the windowed cheapest ranking and its refusals
(too few visits, too few stations, out-of-window fills); relative price.

### `csv_import_test.dart`
RFC 4180 parsing (quoted commas, doubled quotes, embedded newlines, CRLF);
header alias matching including this app's own export and US-style headers;
date parsing across ISO / day-first / month-first / month names / two-digit
years; **rejection of impossible dates** rather than `DateTime` rollover; unit
conversion on import; deriving total from unit price; skipping bad rows while
keeping good ones.

### `database_test.dart` — needs the FFI backend

Runs the real schema in memory through `sqflite_common_ffi`. **The only thing
that proves the SQL parses.**

- Vehicle CRUD; optional columns accepting nulls; archive filtering
- Entries ordered by odometer; scoped per vehicle
- **Cascade delete** — proves `PRAGMA foreign_keys = ON` took effect
- Service records: round-trip, nullable columns, cascade
- **Migration**: builds a v1 database by hand, runs the real upgrade, asserts
  the new table appears *and v1 rows survive*. Uses a temp file, not
  `:memory:`, because each in-memory open is a new database
- Backup: export→restore round-trip, merge with id remapping, service records
  surviving, v1 backups still restoring, rejection of foreign/newer payloads
- CSV export: header, row count, comma quoting

If this suite fails for environmental reasons (no native SQLite for FFI), the
other six are pure Dart and still meaningful.

---

## Gaps

- **No widget tests.** Every screen is untested.
- **No integration test.** Nothing exercises the app end to end.
- **Charts are visually unverified.** Two `CustomPainter`s, never rendered.
- **No golden tests.**

Highest-value additions, in order: a widget test for `entry_form_screen`
(volume/price/total cross-computation and odometer validation), then an
end-to-end "add vehicle → log two fills → check the average on screen".

---

## Writing new tests

- Prefer testing `domain/` directly. It is pure Dart, so no
  `testWidgets`, no pumping, no fakes.
- Use `closeTo(expected, 1e-9)` for floating-point comparisons.
- Build fixtures with a local helper (`entry(...)`, `record(...)`) rather than
  repeating constructors — see the existing suites.
- For database tests, `AppDatabase.openInMemory()` gives the real schema with
  no device.
- When a test encodes a *decision* rather than a mechanism, say so in the test
  name — e.g. *"is distance-weighted, not the mean of the windows"*. Those
  names are the specification.
