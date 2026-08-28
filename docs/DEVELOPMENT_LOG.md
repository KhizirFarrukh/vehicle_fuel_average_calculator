# Development log

Chronological record of how the branch was built. All of it is one session,
25 August 2026, on `feature/multi-vehicle-fuel-tracking`.

Commit subjects use the phase number (`P0`–`P13`) or the idea number
(`I19`–`I23`) from [PLAN.md](PLAN.md).

---

## Before: `main`

`85a7962 version 0.0.1 - basic structure ready`

One file. `lib/main.dart`, 103 lines: two `TextField`s, a Calculate button,
`distance / fuel`, result in a `Text`. No models, no persistence, no tests, no
dependencies beyond `flutter_lints`. Two `TextEditingController`s that were
never disposed.

`main` still holds exactly this.

---

## Phase 1 — rebuild (P0–P13)

Ten commits establishing the app.

| Commit | What |
|---|---|
| `ccacc0e` **P0** | `docs/PLAN.md` written first, as asked. Dependencies chosen (`sqflite`, `sqflite_common_ffi`, `path`, `path_provider`, `provider`) — all selected to avoid code generation, which could not run. Analyzer tightened: `strict-casts`, `use_build_context_synchronously` as an error. |
| `4935ecd` **P1** | `core/`: unit system with four economy units; hand-rolled formatters (avoiding `intl`); validators with lenient number parsing; Material 3 theme replacing the M2 `primarySwatch`. |
| `8806d6a` **P2** | `models/`: `Vehicle` (make/model/variant required, year/colour/plate optional), `FuelEntry` (+ `isFullTank`, `missedFillUp`), stats types, `AppSettings`. `_unset` sentinel in every `copyWith`. |
| `6fa6b35` **P3** | **The economy engine.** Replaced `distance / fuel` with tank-to-tank measurement. Pure Dart. |
| `5f7ff7b` **P4** | SQLite schema v1, four DAOs, `BackupService` (JSON + CSV). `PRAGMA foreign_keys` enabled so cascade delete actually works. |
| `4f0a0ce` **P5** | `GarageController` and `SettingsController`. |
| `8b02117` **P6** | Shared widgets, and two `CustomPainter` charts rather than a charting dependency. |
| `4e08b1a` **P7–P11** | All screens: garage, vehicle detail (3 tabs), vehicle form, entry form, quick calculator, settings. |
| `ea7b9de` **P12** | Five test suites, including the in-memory database suite. |
| `97cc5d3` **P13** | README rewritten. |

At this point: 30 files in `lib/`, ~8,000 lines, every Tier 1 idea (I1–I18)
implemented.

---

## Phase 2 — Tier 2 features

Six more commits, after the user asked to continue and to commit per stage.

| Commit | What |
|---|---|
| `315fb08` **I20** | **Vehicle comparison.** Ranks the garage on six measures. Bars drawn from the *canonical* value, so "longer" means the same thing in every display unit — otherwise an L/100 km reader sees the longest bar on their thirstiest car while the header claims longer is better. |
| `228f39f` **I23** | **CSV import.** RFC 4180 parser; headers matched by alias. Source units and date order are *asked*, never guessed. Impossible dates rejected rather than left to `DateTime`'s rollover. Preview before write. Added `GarageController.addEntries` for bulk insert. |
| `05b2bca` **I19a** | **Service records, schema v2.** Migration DDL as a shared constant used by both `_create` and `_upgrade`. Migration test against a temp file. `ServicePlanner` (pure Dart). Backup format → v2, still restoring v1. |
| `845e51e` **I19b** | **Service UI.** Fourth tab; FAB follows the visible tab; reminders read out both limits; overdue items surface on the garage card. Overview separates fuel from maintenance cost. |
| `e26976b` **I22** | **Station price memory.** Recent stations as taps on the entry form; per-station spend; cheapest ranking windowed to 180 days and refusing to rank fewer than two qualifying stations. |
| `74adc78` docs | Recorded Tier 2 progress and why the rest is blocked. |

---

## Phase 3 — handoff documentation

This set of files, so the work survives losing the chat.

---

## Running totals

| | After P13 | Now |
|---|---|---|
| Files in `lib/` | 30 | 39 |
| Test suites | 5 | 8 |
| Lines | ~8,000 | ~12,500 |
| Schema version | 1 | 2 |
| Backup format | 1 | 2 |

---

## Constraints that shaped everything

Worth understanding before judging any of the above.

1. **No Flutter, Dart, Python or Node on the machine.** Checked `PATH`, `C:\`,
   `%LOCALAPPDATA%`, `C:\dev`, `C:\src`, `C:\tools`, `Program Files`. Nothing.
   So: no compilation, no tests, no `pub get` — and no code generation, which
   ruled out `drift`, `freezed` and `json_serializable` outright.

2. **Unknown Flutter version.** Led to deliberately conservative API choices
   ([DECISIONS.md](DECISIONS.md) §D7): styling at the call site instead of
   `ThemeData.cardTheme`, `DropdownButtonFormField(value:)` not
   `initialValue:`, plain `ListTile` not `RadioListTile`.

3. **Unverifiable dependency solves.** Ruled out `share_plus`, `file_picker`,
   `image_picker`, `fl_chart` and `intl` — hence hand-rolled charts and
   formatters, and the two scope reductions noted in [HANDOFF.md](HANDOFF.md).

Verification was mechanical instead: import resolution, symbol availability,
unused imports, bracket balance, quote style, and a manual null-promotion
audit. See [TESTING.md](TESTING.md).
