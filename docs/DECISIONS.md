# Decisions

Why the code is the way it is. Each entry records the alternative that was
rejected, so a future change is a decision rather than an accident.

If you are about to "fix" something that looks odd, look for it here first.

---

## D1 — Local SQLite via `sqflite`, no code generation

**Chose:** `sqflite` with hand-written SQL, hand-written `toMap`/`fromMap`.

**Rejected:** `drift` (excellent, but requires `build_runner`), `hive`
(document store; the data is genuinely relational), `shared_preferences` alone
(cannot express a vehicle→entries relationship).

**Why:** the environment this was built in has no Dart SDK, so `build_runner`
could not run. A generated-code approach would have been unmaintainable there.
The data is relational — vehicles own entries and service records, with cascade
delete — so a relational store is the honest fit.

**Cost:** more boilerplate, and mapping bugs are possible. Mitigated by
round-trip tests for every model.

**Consequence:** web does not build. `sqflite` needs `sqflite_common_ffi_web`,
and `lib/data/app_database.dart` imports `dart:io` for platform detection and
paths. Contained to that one file if web is ever wanted.

---

## D2 — `provider` + `ChangeNotifier`, not Riverpod/BLoC

**Why:** two controllers and a handful of screens. `ChangeNotifier` is enough,
and `provider` is the smallest thing that does the job. Riverpod or BLoC would
be more ceremony than this app has state.

**Revisit if:** the controllers grow past a few hundred lines each, or async
state (loading/error per-operation) starts being modelled by hand.

---

## D3 — Fuel economy is measured tank to tank

**This is the most important decision in the codebase.**

The app it replaced computed `distance / fuel`. That answers: *"what average
did this tank give, assuming I know exactly how much fuel that distance
consumed?"* At a petrol pump, nobody knows that — you know what you just put
in, not what you burned.

**The method used instead:** fill to full at odometer `O2`, having last filled
to full at `O1`. The fuel just pumped in is *precisely* what was burned over
`O2 − O1`, because the tank is back at the same reference level.

```
distance = odometer(this full tank) − odometer(previous full tank)
fuel     = litres of this fill + litres of any partial fills in between
average  = distance ÷ fuel
```

**Everything else follows from this:**

- **Two full tanks are needed before any average exists.** The first only sets
  the reference level. The UI says so in words rather than showing `0.0`.
- **`FuelEntry.isFullTank` must exist.** A partial fill cannot close a
  measurement — the tank is at an unknown level — so its litres are carried
  into the next full tank instead of being lost.
- **`FuelEntry.missedFillUp` must exist.** If fuel went in that was never
  logged, any window spanning it understates consumption and *overstates* the
  average. The window is discarded rather than reported wrongly.
- **The closing fill's volume counts; the opening fill's does not.** Getting
  this backwards is the classic off-by-one in fuel trackers.

**Lifetime average is distance-weighted** — total distance ÷ total fuel — not
the mean of the per-window figures. The two differ whenever tank lengths vary,
and only the weighted one is correct. `VehicleStats` exposes both;
`meanOfWindowsKmPerLitre` exists mainly so the difference can be shown.

`FuelCalculator.simpleAverage()` still exists for the Quick Calculator, where
the user *asserts* the fuel used and the simple formula is the right answer to
that question.

---

## D4 — Canonical storage units: kilometres and litres

**Why:** a user switching from miles to kilometres must not alter stored data.
Storing in display units would mean rewriting every row on a settings change,
or storing a unit tag per row and converting on read — both worse.

Conversion happens only in `lib/core/unit_formatter.dart`. Money is *never*
converted; the currency symbol is cosmetic and no exchange rates are involved.

CSV export writes canonical units regardless of display settings, and says so
in the headers — a CSV whose units silently changed between exports would be
worthless.

CSV *import* asks what units the file is in, because an export from a US app is
in miles and gallons whatever this app displays.

---

## D5 — Formatting hand-rolled instead of `intl`

**Why:** `flutter_localizations` pins a specific `intl` version, and a version
conflict there can wedge a dependency solve — which could not be diagnosed
without a working SDK. `lib/core/formatters.dart` is ~180 lines and covers
everything needed: thousands separators, fixed decimals, compact numbers, dates
and relative dates.

**Cost:** English-only, and month names are hardcoded. When localisation (I25)
is picked up, this decision should be revisited — that is the natural moment to
adopt `intl` properly.

---

## D6 — Charts drawn with `CustomPainter`

**Rejected:** `fl_chart`, `syncfusion_flutter_charts`, `charts_flutter`.

**Why:** one fewer dependency to version-solve blind, and full control over
dark-mode rendering. The two painters in `lib/ui/widgets/charts.dart` handle
the degenerate cases a real log produces: a flat series that would divide by
zero, and dense series where markers would smear into a solid band.

**Cost:** no animations, no built-in interactivity beyond the tap-to-inspect
that was written by hand. Entirely unverified visually — see
[TODO.md](TODO.md) P3.

---

## D7 — Avoid Flutter APIs that are mid-rename

The Flutter version could not be determined, so the code sticks to
long-stable APIs. See the table in [../CLAUDE.md](../CLAUDE.md) §5.

The notable one: **card and input styling live at the call site**
(`AppCard`, `AppTheme.inputDecoration()`) rather than in `ThemeData`, because
`cardTheme`, `appBarTheme` and `inputDecorationTheme` changed types across
versions. This looks like it is fighting the theme system; it is deliberate.

---

## D8 — `_unset` sentinel in `copyWith`

A model needs to distinguish *"leave this alone"* from *"set this to null"*.
With plain `??`, an optional field can never be cleared — and year, colour,
plate, trip meter and both service due-fields all need clearing.

```dart
static const Object _unset = Object();

Vehicle copyWith({Object? year = _unset, ...}) =>
    Vehicle(year: identical(year, _unset) ? this.year : year as int?, ...);
```

Verbose, but correct. There are tests for exactly this on every model.

---

## D9 — Settings in a database table, not `shared_preferences`

**Why:** one fewer dependency, and a backup then captures preferences along
with the data. `SettingsDao` is a small key/value table; `AppSettings` maps to
and from `Map<String, String>`.

---

## D10 — Quality warnings, not silent correction

The engine flags rather than fixes: duplicate odometer readings, dates running
backwards against readings, a trip meter disagreeing with the odometer delta,
and windows more than 40% from the median.

**Why:** the app cannot tell a genuine unusual tank from a typo. Silently
dropping outliers would hide real data; silently including them skews the
average. Flagging lets the user decide, and `EconomyPoint.isOutlier` keeps
outliers *in* the figures while marking them in the UI.

Similarly, entering an odometer **lower** than the highest on record raises a
confirmation, not an error — back-filling an old receipt is legitimate, and
only the user can distinguish that from a mistyped digit. A *duplicate*
odometer is a hard error, since it makes the window undefined.

---

## D11 — Station comparison is windowed and hedged

Pump prices move over time. A station visited mostly two years ago will look
cheaper than one visited last month regardless of how either prices, so an
all-time average per station compares the calendar as much as the forecourt.

`StationAnalyzer.cheapest()` therefore:
- looks only at the last 180 days,
- counts only stations with at least 2 visits in that window,
- returns **nothing** when fewer than 2 stations qualify — a ranking of one is
  not a ranking,
- and the UI states the window and the caveat in plain words.

---

## D12 — Migration DDL is a shared constant

`AppDatabase._serviceRecordsV2` is used by **both** `_create` (fresh install)
and `_upgrade` (existing install). Duplicating the SQL in both places is how
migrations rot: the two schemas drift, and the bug only appears for users who
upgraded.

There is a test that builds a v1 database by hand, runs the real upgrade over
it, and checks both that the new table appears and that v1 rows survive. It
uses a **temp file**, not `:memory:` — each in-memory open is a *new* database,
so a migration cannot be observed across one.

See [SCHEMA.md](SCHEMA.md) for how to add the next migration.

---

## D13 — Backup format is versioned separately from the schema

`BackupService.formatVersion` is 2, independent of `AppDatabase.schemaVersion`.
A restore rejects a *newer* format with a readable message rather than
half-reading it, and accepts older ones — a v1 backup restores fine, it simply
carries no service records.

Vehicle ids are **remapped** on restore, so a merge can never collide with
existing rows.

---

## D14 — In-memory garage cache

`GarageController` loads every vehicle, entry and service record at startup and
keeps them in memory. A heavy user logs perhaps 30 entries a year per vehicle,
so this is kilobytes, and it lets the garage list show each vehicle's current
average without a query per card.

**Revisit if:** CSV import starts bringing in thousands of rows routinely.
