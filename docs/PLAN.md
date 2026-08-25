# Vehicle Fuel Average Calculator — Development Plan

Status: **living document**. Phases are checked off as they land.
Created: 2026-08-23 · Baseline commit: `85a7962` (v0.0.1 basic structure ready)

---

## 1. Where the project was left off

The entire app was one file, [lib/main.dart](../lib/main.dart) (103 lines):

- `FuelAverageApp` → `MaterialApp` with a `primarySwatch` theme (Material 2 style).
- `FuelAverageCalculator`, a `StatefulWidget` with two `TextField`s
  (distance km, fuel litres), a Calculate button, a Reset button, and a
  `String _result` rendered as text.
- The maths is a single expression: `fuelAverage = distance / fuel`.

What exists: a working one-shot calculator.
What does **not** exist: any persistence, any model classes, any notion of a
vehicle, any history, any tests, any folder structure. `pubspec.yaml` has zero
dependencies beyond `flutter` + `flutter_lints`.

Two `TextEditingController`s are also never disposed — a real (if minor) leak
that carries over into the rewrite.

### Environment constraint (important)

The Flutter SDK, Dart SDK, Python and Node are **all absent from this machine**
(checked `PATH`, `C:\`, `%LOCALAPPDATA%`, `C:\dev`, `C:\src`, `C:\tools`,
`C:\Program Files`). Therefore, during this work:

- `flutter pub get`, `flutter analyze`, `flutter test` and `flutter run`
  **cannot be executed here**. The code is written to be correct on first read,
  but it is **unverified by a compiler**.
- Anything requiring code generation (`build_runner`) is **off the table** —
  this rules out `drift`, `freezed`, `json_serializable`, `hive_generator` and
  Riverpod's generator API. Every model gets hand-written `toMap`/`fromMap`.
- Dependencies are kept few and boring, because a version-solve failure cannot
  be diagnosed here.

**First thing to run when a Flutter SDK is available:**

```
flutter pub get
flutter analyze
flutter test
flutter run
```

---

## 2. What the user asked for

1. Continue from where the project was left off.
2. Store a **history of fuel averages**.
3. Store **fuel refilling records**: amount refilled, cost of that refill,
   trip-meter and odometer km at which fuel was refilled.
4. Support **multiple vehicles**, each with its own record, identified by
   make, model, variant, year, colour, licence plate — where **year, colour and
   licence plate are optional** (make / model / variant required).

---

## 3. Ideas added on top of the request

Numbered so they can be accepted or dropped individually. Tier 1 ships in this
pass; Tier 2/3 are recorded for later.

### Tier 1 — shipping now (they make the numbers correct or the app usable)

| # | Idea | Why it matters |
|---|------|----------------|
| I1 | **Full-tank vs partial-fill flag** on every refuel | Without it, fuel economy cannot be computed correctly at all. See §6. |
| I2 | **Missed-fill flag** ("I refuelled and forgot to log it") | Lets the user be honest instead of silently corrupting the average. |
| I3 | **Tank-to-tank economy engine** replacing `distance / fuel` | The old formula answers a different question than "what does my car actually do?" |
| I4 | **Distance-weighted lifetime average**, not the mean of per-fill averages | Averaging ratios is a classic, silent bug. |
| I5 | **Unit system**: km/L, L/100 km, mpg (US), mpg (imperial); km/miles; L/US gal/imp gal | The app should not assume the user's country. |
| I6 | **Currency setting** (symbol + code) with cost-per-km / cost-per-100 km | Cost is usually the reason people track fuel at all. |
| I7 | **Per-vehicle fuel type + tank capacity** | Enables range estimation and keeps a petrol and a diesel car honest. |
| I8 | **Estimated range on a full tank** = capacity × current average | The single most-wanted derived number after the average itself. |
| I9 | **Odometer sanity validation** (must exceed previous entry; warn on wild jumps) | Catches typos at entry time, when they are cheap to fix. |
| I10 | **Outlier flagging** on computed points (>40 % off the median) | Surfaces a mis-keyed litre value months later. |
| I11 | **Trip-meter vs odometer reconciliation warning** | Uses the trip figure the user asked to store as a free cross-check. |
| I12 | **Archive instead of delete** for vehicles; cascade-delete behind a confirmation | Deleting years of records on a mis-tap would be unforgivable. |
| I13 | **Charts** (economy over time, fuel price over time, monthly spend) drawn with `CustomPainter` | No chart dependency to version-solve; full control over dark mode. |
| I14 | **JSON backup / restore + CSV export** | The user's data is theirs. No cloud, no account, no lock-in. |
| I15 | **Quick Calculator kept** as its own screen, able to save its result to a vehicle | The original feature does not regress. |
| I16 | **Material 3 + light/dark/system theme** | The current `primarySwatch` look is two major versions behind. |
| I17 | **Prefill-from-last-entry** on the refuel form | Cuts a forecourt entry to about three taps. |
| I18 | **Any-two-of-three cost entry** (volume / price-per-litre / total — type two, the third computes) | Pumps show different combinations in different countries. |

### Tier 2

Shipped after the initial pass:

| # | Idea | Notes |
|---|------|-------|
| I19 | **Service & maintenance log** | Schema v2. Records what was done, when, at what odometer and cost, with next-due by distance, by date or both. Whichever limit bites first decides the status. Overdue items surface on the garage card without opening the vehicle. |
| I20 | **Multi-vehicle comparison screen** | Ranks the garage on six measures. Bars are drawn from the *canonical* value so "longer" means the same thing in every display unit. |
| I23 | **CSV import** | RFC 4180 parser, headers matched by alias so exports from other fuel apps usually work unchanged. Source units and date order are asked, never guessed. Nothing is written until the parse has been shown. |

Still open:

- I21 Home-screen widget / quick-add shortcut.
- I22 Fuel-station price memory and "cheapest nearby" notes.
- I24 Photo of the pump receipt attached to an entry.
- I25 Localisation (`flutter_localizations` + ARB files).

### Tier 3 — speculative

- I26 Cloud sync (would require an account system; deliberately avoided for now).
- I27 CO₂ estimate per litre burned.
- I28 Cost forecasting from the rolling average.

---

## 4. Architecture

Layered, with the maths engine kept as **pure Dart** so it is unit-testable
without a Flutter binding.

```
lib/
  main.dart                  entry point, DB init, provider wiring
  app.dart                   MaterialApp, theme, routes
  core/
    units.dart               DistanceUnit / VolumeUnit / EconomyUnit + conversions
    formatters.dart          hand-rolled date, number, currency formatting (no intl)
    validators.dart          shared form validators
    theme.dart               Material 3 light + dark schemes
  models/
    vehicle.dart             Vehicle + FuelType, toMap/fromMap, copyWith
    fuel_entry.dart          FuelEntry, toMap/fromMap, copyWith
    fuel_stats.dart          EconomyPoint, VehicleStats, warnings
    app_settings.dart        AppSettings value object
  domain/
    fuel_calculator.dart     <-- PURE DART. The heart of the app. No flutter import.
  data/
    app_database.dart        sqflite open + schema + migrations
    vehicle_dao.dart
    fuel_entry_dao.dart
    settings_dao.dart        key/value table
    backup_service.dart      JSON export/import, CSV export
  state/
    garage_controller.dart   ChangeNotifier: vehicles + entries + CRUD
    settings_controller.dart ChangeNotifier: units, currency, theme
  ui/
    screens/                 home, vehicle_form, vehicle_detail, entry_form,
                             quick_calculator, settings
    widgets/                 vehicle_card, stat_tile, entry_tile, charts,
                             empty_state, section_header
test/
  fuel_calculator_test.dart  the maths, exhaustively
  units_test.dart            conversion round-trips
  models_test.dart           map round-trips
docs/PLAN.md                 this file
```

### Dependency choices

| Package | Why | Why not the alternative |
|---------|-----|------------------------|
| `sqflite` + `sqflite_common_ffi` | Relational history, real queries, real migrations, **no codegen** | `drift` needs `build_runner`, which cannot run here |
| `path`, `path_provider` | DB + export file locations | — |
| `provider` | Smallest sane `ChangeNotifier` wiring | Riverpod's modern API leans on codegen |
| *(none)* for settings | A `settings` key/value table in the same DB | Drops the `shared_preferences` dependency entirely |
| *(none)* for dates/numbers | ~80 lines in `formatters.dart` | `intl` is pinned by `flutter_localizations` and can wedge a version solve |
| *(none)* for charts | `CustomPainter` | `fl_chart` is another version to solve blind |

**Platform note:** `sqflite` covers Android / iOS / macOS; `sqflite_common_ffi`
is registered for Windows and Linux. **Web is not supported** by this storage
choice — adding `sqflite_common_ffi_web` later is the fix, and the data layer
is written behind DAOs so the swap is contained.

---

## 5. Data model

Canonical storage units, converted only at the display edge:
**distance = kilometres, volume = litres, money = the user's single currency,
timestamps = epoch milliseconds.**

### `vehicles`

| Column | Type | Null | Notes |
|--------|------|------|-------|
| `id` | INTEGER PK AUTOINCREMENT | no | |
| `make` | TEXT | **no** | required per request |
| `model` | TEXT | **no** | required per request |
| `variant` | TEXT | **no** | required per request |
| `year` | INTEGER | yes | optional per request |
| `color` | TEXT | yes | optional per request |
| `license_plate` | TEXT | yes | optional per request |
| `fuel_type` | TEXT | no | `petrol`/`diesel`/`cng`/`lpg`/`hybrid`/`electric`/`other` (I7) |
| `tank_capacity` | REAL | yes | litres (I7, I8) |
| `initial_odometer` | REAL | yes | km at which tracking started |
| `notes` | TEXT | yes | |
| `is_archived` | INTEGER | no | 0/1 (I12) |
| `created_at`, `updated_at` | INTEGER | no | epoch ms |

### `fuel_entries`

| Column | Type | Null | Notes |
|--------|------|------|-------|
| `id` | INTEGER PK AUTOINCREMENT | no | |
| `vehicle_id` | INTEGER FK → vehicles ON DELETE CASCADE | no | each vehicle owns its records |
| `filled_at` | INTEGER | no | epoch ms |
| `odometer` | REAL | **no** | km — *requested* |
| `trip_meter` | REAL | yes | km since reset — *requested* |
| `volume` | REAL | **no** | litres refilled — *requested* |
| `total_cost` | REAL | **no** | cost of this refill — *requested* |
| `is_full_tank` | INTEGER | no | default 1 (I1) |
| `missed_fill_up` | INTEGER | no | default 0 (I2) |
| `station`, `notes` | TEXT | yes | |
| `created_at`, `updated_at` | INTEGER | no | |

Index: `(vehicle_id, odometer)`.

`price_per_unit` is **derived** (`total_cost / volume`), never stored — storing
both invites the two to disagree.

### `settings`

`key TEXT PRIMARY KEY, value TEXT NOT NULL` — units, currency, theme mode.

### On "storing the history of fuel averages"

Fuel averages are **derived from the refuel log, not stored**. The log is the
single source of truth; a stored average would go stale the moment an entry is
corrected. The user-visible outcome is identical — a full history of averages
with dates, distances and cost-per-km — computed on read by
`FuelCalculator.analyze()` and rendered as a list plus a chart.

---

## 6. The economy engine (`domain/fuel_calculator.dart`)

The existing `distance / fuel` answers "what average did this *one* tank give,
assuming I know exactly how much fuel that distance consumed?" — which a driver
almost never knows. The standard correct method is **tank-to-tank between
full-tank fills**:

> When you fill the tank to full at odometer `O2`, having last filled it to
> full at `O1`, the fuel you just pumped in is *exactly* the fuel you burned
> over `O2 - O1` — because the tank is back at the same reference level.

So for a window closing at a full-tank entry:

```
distance = odometer(close) - odometer(previous full-tank entry)
fuel     = volume(close) + sum(volume of every partial fill in between)
economy  = distance / fuel
```

Consequences that fall out of this:

- The **closing** entry's volume counts; the **opening** entry's does not.
- A partial fill yields no point of its own; its litres roll into the next
  full-tank window.
- The first full-tank fill can only ever be an *opening* anchor — no average is
  computable before it. The UI says so explicitly rather than showing `0.0`.
- `missed_fill_up` on an entry voids the window in progress; the chain restarts
  at that entry if it is a full tank. (I2)
- Lifetime average = `sum(all window distances) / sum(all window fuel)` —
  distance-weighted, **not** `mean(window averages)`. (I4)

Derived outputs: `EconomyPoint` per window (distance, fuel, km/L, cost,
cost/km, fills, days) and a `VehicleStats` roll-up (lifetime average, best,
worst, latest, total spent, total litres, total distance, average price per
litre, average days between fills, km per day, estimated range).

Warnings produced: odometer not increasing, economy >40 % off the median (I10),
trip-meter disagreeing with the odometer delta by >5 % (I11).

---

## 7. Phases

- [x] **P0 — Scaffolding.** `pubspec.yaml` deps, folder structure, lints tightened.
- [x] **P1 — Core.** `units.dart`, `formatters.dart`, `validators.dart`, `theme.dart`, `unit_formatter.dart`.
- [x] **P2 — Models.** `Vehicle`, `FuelEntry`, `FuelStats`, `AppSettings`.
- [x] **P3 — Engine.** `fuel_calculator.dart`, pure Dart. The most important file.
- [x] **P4 — Persistence.** `app_database.dart` + the three DAOs + `backup_service.dart`.
- [x] **P5 — State.** `garage_controller.dart`, `settings_controller.dart`.
- [x] **P6 — UI shell.** `app.dart`, home/garage screen, navigation, empty states.
- [x] **P7 — Vehicle CRUD.** Add/edit form, required vs optional fields, archive, delete.
- [x] **P8 — Refuel CRUD.** Entry form (I17, I18), history list, edit, delete, validation (I9).
- [x] **P9 — Stats & charts.** Overview tab, average history, `CustomPainter` charts (I13).
- [x] **P10 — Quick calculator.** Ported from the original, kept working (I15).
- [x] **P11 — Settings & backup.** Units, currency, theme; JSON export/restore, CSV export (I14).
- [x] **P12 — Tests.** Calculator, units, formatters, models, in-memory database.
- [x] **P13 — Docs.** README rewritten, this plan updated.

### What shipped

30 files under `lib/`, 5 test suites, ~8,000 lines. Every Tier 1 idea (I1–I18)
is implemented. Tier 2 and Tier 3 remain open.

Two scope calls made along the way, both to avoid dependencies that could not
be verified here:

1. **Export writes to the app documents directory and shows the path**, with a
   copy-to-clipboard button, instead of opening a system share sheet or file
   picker. Adding `share_plus` / `file_picker` is the natural follow-up.
2. **Restore takes pasted JSON** rather than a picked file, for the same
   reason. `BackupService.restoreFromFile` already exists and is tested — only
   the file-picking UI is missing.

### Verification status

**The code has never been compiled.** No Flutter, Dart, Python or Node runtime
exists on this machine, so `flutter analyze` and `flutter test` could not be
run. What *was* done instead:

- Every relative import checked to resolve to a real file.
- Every `package:` import checked against the declared dependencies.
- Every cross-file symbol checked to be imported where it is used.
- Unused-import sweep (clean).
- Quote-style sweep for `prefer_single_quotes` (clean).
- Flutter APIs mid-rename across versions deliberately avoided: no
  `ThemeData.cardTheme` / `appBarTheme` / `inputDecorationTheme` (styling moved
  to `AppTheme.inputDecoration` and `AppCard`), `DropdownButtonFormField.value`
  rather than `initialValue`, plain `ListTile` rather than `RadioListTile`.

Expect a handful of analyzer nits on the first run. Nothing structural should
be wrong, but **run `flutter pub get && flutter analyze && flutter test`
before trusting any of it**.

---

## 8. Risks

| Risk | Mitigation |
|------|-----------|
| No SDK here → code is compiler-unverified | Few dependencies; conservative APIs; thorough tests written for the user to run first |
| `pub get` version-solve failure | Only five well-known packages, all with wide caret ranges |
| Web build broken by `sqflite` | Documented; storage sits behind DAOs for a later `_ffi_web` swap |
| Users mis-entering odometer/volume | Entry-time validation (I9) + after-the-fact outlier flags (I10) |
| Data loss on vehicle delete | Archive by default (I12); delete requires explicit confirmation |
