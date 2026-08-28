# Architecture

A code map, the layering rules, and how data moves through the app.

---

## Layers

```
    ui/          screens and widgets          ← Flutter
     ↓ reads via provider
    state/       ChangeNotifier controllers   ← Flutter (foundation only)
     ↓ calls
    data/        DAOs, backup, CSV import     ← sqflite, dart:io
     ↓ maps to
    models/      plain data classes           ← PURE DART
    domain/      calculation engines          ← PURE DART
    core/        units, formatting, theme     ← theme.dart is Flutter; rest is pure
```

**The rule that matters:** `domain/` and `models/` never import Flutter.
`lib/data/csv_import_service.dart` also holds to this. That is what makes the
logic directly testable, and it is why the test suites are fast and have no
`testWidgets` scaffolding.

`core/theme.dart` is the one file in `core/` that imports Flutter. The other
four (`units`, `formatters`, `validators`, `unit_formatter`) are pure.

---

## File map

### `lib/core/`

| File | What it holds |
|---|---|
| `units.dart` | `DistanceUnit`, `VolumeUnit`, `EconomyUnit`, conversion factors and functions. Canonical units are km and litres. |
| `formatters.dart` | Number, currency and date formatting. Hand-rolled to avoid `intl` (D5). `kEmDash` is the "no value" string. |
| `validators.dart` | `parseFlexibleDouble` (handles `1,234.56` and `1.234,56`), `validateRequired/Number/Year`. |
| `unit_formatter.dart` | **The single formatting entry point for the UI.** Wraps `AppSettings`; converts canonical → display and parses display → canonical. Also exposes raw numeric accessors (`economyValue`, `priceValue`) for charts, which need numbers not strings. |
| `theme.dart` | Material 3 light/dark schemes, `AppTheme.inputDecoration()`, and the `good`/`warn` semantic colours. Card styling deliberately lives in `AppCard`, not here (D7). |

### `lib/models/`

| File | What it holds |
|---|---|
| `vehicle.dart` | `Vehicle`, `FuelType`. make/model/variant required; year/colour/plate optional. |
| `fuel_entry.dart` | `FuelEntry`. Odometer, trip, volume, cost, `isFullTank`, `missedFillUp`. `pricePerLitre` is *derived*, never stored. |
| `service_record.dart` | `ServiceRecord`, `ServiceType` with default intervals. |
| `fuel_stats.dart` | `EconomyPoint`, `EntryIssue`, `MonthlySpend`, `VehicleStats` — the engine's output types. |
| `app_settings.dart` | `AppSettings`, `AppThemeMode`. Maps to/from the settings key/value table. |

All models: hand-written `toMap`/`fromMap`, `copyWith` with an `_unset`
sentinel (D8), value equality, and `toMap()` omits `id` when null so inserts
work.

### `lib/domain/` — pure Dart engines

| File | What it does |
|---|---|
| `fuel_calculator.dart` | **The core.** Walks entries in odometer order, builds tank-to-tank windows, produces `VehicleStats`. Also holds `simpleAverage` for the Quick Calculator and the entry-form helpers `lastOdometer` / `previousEntry`. |
| `service_planner.dart` | Turns `ServiceRecord`s into `ServiceReminder`s with overdue/due-soon/upcoming status. Whichever limit (distance or date) is worse decides. |
| `station_analyzer.dart` | Groups entries by station, computes per-station spend, and the windowed cheapest ranking (D11). |

### `lib/data/`

| File | What it does |
|---|---|
| `app_database.dart` | Opens SQLite, holds the schema DDL, runs migrations. `registerPlatformFactory()` sets the FFI backend on desktop. `openInMemory()` is for tests. |
| `vehicle_dao.dart`, `fuel_entry_dao.dart`, `service_dao.dart`, `settings_dao.dart` | CRUD. Entries come back ordered by odometer — the order the engine wants. |
| `backup_service.dart` | JSON export/restore (format v2) and CSV export. Remaps vehicle ids on restore. |
| `csv_import_service.dart` | **Pure Dart.** RFC 4180 parser, header alias matching, lenient date parsing, preview-before-write. |

### `lib/state/`

| File | What it does |
|---|---|
| `garage_controller.dart` | Owns everything: vehicles, entries, service records, and the derived `VehicleStats`. Loads all of it at startup (D14). Entry writes recompute only the affected vehicle. |
| `settings_controller.dart` | Preferences; hands out a freshly-built `UnitFormatter` so no widget can format with stale units. |

### `lib/ui/screens/`

| Screen | Notes |
|---|---|
| `home_screen.dart` | The garage. Vehicle cards with average, fill count, last fill, and any service alerts. |
| `vehicle_detail_screen.dart` | Four tabs: Overview, History, Charts, Service. The FAB follows the visible tab. |
| `vehicle_form_screen.dart` | Add/edit vehicle; archive and delete live in its overflow menu. |
| `entry_form_screen.dart` | Log a fill-up. Cross-computes volume/price/total from any two. Odometer validation. Station suggestions. |
| `service_form_screen.dart` | Log maintenance; seeds next-due from the type's typical interval. |
| `comparison_screen.dart` | Ranks vehicles on six measures. |
| `csv_import_screen.dart` | Paste → check → preview → import. |
| `quick_calculator_screen.dart` | The original calculator, preserved. |
| `settings_screen.dart` | Units, currency, theme, backup/restore/export. |

### `lib/ui/widgets/`

`app_card.dart` (`AppCard`, `SectionHeader`, `EmptyState`), `stat_tile.dart`
(`StatTile`, `StatGrid`, `DetailRow`), `charts.dart` (two `CustomPainter`
charts), `vehicle_card.dart`, `entry_tile.dart`, `service_tile.dart`.

---

## Data flow: logging a fill-up

```
entry_form_screen
  │  user types in display units (miles/gallons if chosen)
  ├─ UnitFormatter.parseDistanceToKm / parseVolumeToLitres
  │  → canonical km + litres
  ├─ validation: duplicate odometer = error;
  │              lower-than-highest = confirmation, not error (D10)
  ↓
GarageController.addEntry(FuelEntry)
  ├─ FuelEntryDao.insert          → SQLite
  ├─ _reloadEntries(vehicleId)    → re-read that vehicle only
  ├─ FuelCalculator.analyze(...)  → rebuild VehicleStats
  ├─ VehicleDao.touch(vehicleId)  → garage list reorders by recent activity
  ↓
notifyListeners()
  ↓
every watching widget rebuilds; UnitFormatter renders canonical → display
```

## Data flow: the economy engine

`FuelCalculator.analyze(vehicleId, entries)`:

1. Sort by odometer (then date, then id) — input order does not matter.
2. Walk forward holding an **anchor** (the last full-tank entry) and
   accumulating `pendingFuel` / `pendingCost` / `pendingFills`.
3. A `missedFillUp` entry discards the window and restarts the chain.
4. A partial fill accumulates but cannot close a window.
5. A full tank closes the window → emits an `EconomyPoint` → becomes the new
   anchor.
6. Windows shorter than `kMinWindowDistanceKm` (1 km) produce a warning, not a
   point.
7. Afterwards: flag outliers against the median, cross-check trip meters,
   check date/odometer monotonicity, bucket monthly spend.

Output is one `VehicleStats` holding the points, the issues, and every derived
figure the UI shows.

---

## Conventions

- **Naming:** `*Screen`, `*Tile`, `*Card`, `*Dao`, `*Controller`. Private
  widgets in a screen file are `_PascalCase`.
- **Imports:** `dart:` first, then `package:`, then relative — each block
  alphabetised.
- **Comments** explain *why*, not what. Several mark non-obvious constraints
  (`// value: not initialValue: — the latter is absent on older Flutter`);
  those are load-bearing, not noise.
- **Null safety:** public fields do not type-promote, so explicit `!` after a
  null check is the norm. Not sloppiness — see [../CLAUDE.md](../CLAUDE.md) §7.
- **`kEmDash`** (`—`) is shown wherever a value genuinely does not exist.
  Never `0.0`, which would read as a measurement.
