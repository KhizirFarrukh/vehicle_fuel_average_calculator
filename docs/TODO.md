# TODO

Ordered by what should happen first. Items in P0 block everything else.

---

## P0 — Make it compile and run

Nothing here has been executed. This is the whole job until it is done.

- [ ] `flutter pub get` — the dependency set changed in this branch
      (`sqflite`, `sqflite_common_ffi`, `path`, `path_provider`, `provider`)
- [ ] `flutter analyze` — fix what it reports
- [ ] `flutter test` — 9 suites, none ever executed
- [ ] `flutter run` on one platform — confirm the app actually starts

### Check these constructs first

These are the specific things most likely to be wrong, roughly in descending
order of risk. Each was chosen deliberately but could not be verified.

- [ ] **`sqflite` + `sqflite_common_ffi` imported together** in
      `lib/data/app_database.dart` and `test/database_test.dart`. Both
      re-export parts of `sqflite_common`. This is the pattern from the
      official `sqflite_common_ffi` README, so it should be fine, but an
      ambiguous-import error on `databaseFactory` would show up here first.
- [ ] **`DropdownButtonFormField(value:)`** in `vehicle_form_screen.dart` and
      `service_form_screen.dart`. Deprecated in newer Flutter but still
      functional; `initialValue:` is absent in older. If the installed version
      has *removed* `value:`, both need switching.
- [ ] **`withValues(alpha:)`** — used throughout for colour opacity. Needs
      Flutter 3.27+. If the SDK is older, these must become `withOpacity()`.
      ~25 call sites.
- [ ] **`ColorScheme.surfaceContainerHighest` / `surfaceContainerLow`** —
      Material 3 tokens, need Flutter 3.22+. Used in `core/theme.dart`,
      `stat_tile.dart`, `comparison_screen.dart`.
- [ ] **`TabAlignment.start`** on the `TabBar` in `vehicle_detail_screen.dart`
      — needs Flutter 3.16+.
- [ ] **`DefaultTabController.of(context)`** in `vehicle_detail_screen.dart`
      returns non-nullable on Flutter 3.7+. On older versions it is nullable
      and the `_Fab` widget will not compile.
- [ ] **Record return type** `({double? odometer, DateTime? date})` in
      `service_planner.dart` and `service_tile.dart` — Dart 3 records. Fine on
      the declared SDK `^3.6.0`, but the first thing to blame if the parser
      complains.
- [ ] **`num.clamp()` return type** — four call sites assign the result where a
      `double` is wanted. Dart special-cases `clamp` to return `double` when the
      receiver and both bounds are `double`, so these should be fine; if the
      analyzer disagrees, add `.toDouble()`. Investigated and left alone
      deliberately rather than churned on a guess.
- [ ] **`strict-casts: true`** in `analysis_options.yaml` may surface implicit
      `dynamic` downcasts that were missed, most likely in
      `backup_service.dart` and `csv_import_service.dart` where JSON and CSV
      are parsed. If it produces noise disproportionate to its value, relaxing
      it is reasonable — but read what it caught first.
- [ ] **`sqflite_common_ffi` on this machine** — `test/database_test.dart` and
      the migration test need the FFI backend to load a native SQLite library.
      If those suites fail for environmental reasons rather than logic, the
      other eight suites are pure Dart and still meaningful.

---

## P1 — Smoke-test the real flows

Once it runs, walk these by hand. Automated widget tests do not exist yet
(see P3).

- [ ] Add a vehicle with **only** make/model/variant. Confirm year, colour and
      plate are genuinely optional and the card renders without them.
- [ ] Log one fill-up → confirm it says an average needs a second full tank,
      rather than showing `0.0`.
- [ ] Log a second full fill-up → confirm an average appears and matches
      `(odo2 − odo1) ÷ litres2` by hand.
- [ ] Log a **partial** fill between two full ones → confirm its litres roll
      into the next window and `fillCount` reads 2.
- [ ] Mark a fill **"I missed logging a fill before this"** → confirm that
      stretch reports no average.
- [ ] Change units in Settings → confirm every screen updates and **stored
      data is unchanged** (check a value before and after).
- [ ] Export a backup, wipe, restore → confirm vehicles, fill-ups and service
      records all return.
- [ ] Import a CSV exported by the app itself → round-trip should be clean.
- [ ] Add a service record with a next-due odometer → confirm the reminder and
      the garage-card banner appear.
- [ ] Delete a vehicle → confirm its entries and service records go with it
      (this is the FK cascade; `PRAGMA foreign_keys` must be on).

---

## P2 — Finish the two deferred pieces

Both were cut only to avoid unverifiable dependencies.

- [ ] Add `share_plus`; wire the export actions in `settings_screen.dart` and
      `vehicle_detail_screen.dart` to a share sheet instead of showing a path.
- [ ] Add `file_picker`; replace the paste-JSON dialog in `settings_screen.dart`
      and the paste-CSV field in `csv_import_screen.dart` with real file
      selection. `BackupService.restoreFromFile()` already exists and is tested.

---

## P3 — Testing gaps

- [ ] **No widget tests exist.** The nine suites cover pure logic and the
      database. Every screen is untested. Start with `entry_form_screen` — the
      volume/price/total cross-computation and the odometer validation are the
      highest-value targets.
- [ ] **No integration test.** A single end-to-end "add vehicle → log two
      fills → check the average on screen" would catch most wiring mistakes.
- [ ] Consider a golden test for the two `CustomPainter` charts; they are
      entirely unverified visually.

---

## P4 — Remaining roadmap

Each needs something the original environment could not provide. Full reasoning
in [PLAN.md](PLAN.md) §3.

- [ ] **I21** Home-screen widget / quick-add shortcut — native Kotlin + Swift,
      or the `home_widget` plugin.
- [ ] **I24** Receipt photo on an entry — `image_picker`, file storage, camera
      permissions per platform.
- [ ] **I25** Localisation — `flutter_localizations` + ARB files. Note this
      pins `intl`, which `core/formatters.dart` was written to avoid; revisit
      that trade once the app builds.
- [ ] **Tier 3** (I26–I28): optional cloud sync, CO₂ estimate, cost
      forecasting. Not designed for.

---

## Known rough edges

Small things noticed but not addressed, none blocking.

- [ ] `GarageController` holds the entire log in memory. Fine for the
      realistic data volume (tens of entries per vehicle per year) but it is a
      deliberate trade, not an oversight — revisit only if someone imports
      thousands of rows.
- [ ] The charts repaint on every build because `shouldRepaint` compares list
      identity and the lists are rebuilt each time. Cheap at this size;
      measurable only if a vehicle has hundreds of points.
- [ ] CSV import always creates new entries — there is no duplicate detection.
      Importing the same file twice will double the log.
- [ ] `AppDatabase` caches a single instance in a static field. Convenient, but
      it means `open()` ignores a different `overridePath` on a second call.
      Only `test/database_test.dart` depends on the current behaviour.
