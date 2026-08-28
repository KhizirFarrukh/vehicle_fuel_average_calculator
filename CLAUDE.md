# CLAUDE.md — read this first

Guidance for any AI agent (or person) picking this repository up cold.
This file is loaded automatically by Claude Code. **Read
[docs/HANDOFF.md](docs/HANDOFF.md) next** — it says exactly where work stopped
and what to do first.

---

## The one thing you must know

> **None of this code has ever been compiled or run.**

It was written in an environment with **no Flutter SDK, no Dart SDK, no Python
and no Node**. `flutter pub get`, `flutter analyze` and `flutter test` have
never executed against it. Everything that could be verified statically was
(see [docs/TESTING.md](docs/TESTING.md)), but static checking is not a
compiler.

**Your first task is almost certainly:**

```bash
flutter pub get
flutter analyze
flutter test
```

Then fix what falls out. [docs/TODO.md](docs/TODO.md) lists the specific
constructs most likely to be wrong, in priority order. Do not build new
features before the existing ~12,500 lines compile.

---

## What this project is

A Flutter app for tracking fuel economy, refuelling history, running cost and
maintenance across any number of vehicles. Local-only: SQLite, no account, no
cloud, no network calls anywhere in the codebase.

It began as a single 103-line `main.dart` that divided distance by fuel. The
current state is the result of one long session that rebuilt it; the design
document is [docs/PLAN.md](docs/PLAN.md).

---

## Hard rules — do not break these without reading why

These exist for reasons recorded in [docs/DECISIONS.md](docs/DECISIONS.md).
Each has been violated by well-meaning refactors before, so check there before
"fixing" any of them.

### 1. `lib/domain/` imports nothing from Flutter

`fuel_calculator.dart`, `service_planner.dart`, `station_analyzer.dart` and
`lib/data/csv_import_service.dart` are pure Dart. They hold all the logic worth
testing. Adding `package:flutter/...` to any of them breaks that, and the test
suites with it.

### 2. Storage is always canonical: **kilometres and litres**

Conversion happens **only** at the display edge, through
`lib/core/unit_formatter.dart`. Never store a mile or a gallon. A user changing
units in Settings must never alter stored data. Money is never converted — the
currency symbol is cosmetic.

### 3. Fuel economy is measured **tank to tank**, never distance ÷ fuel

`distance / fuel` is only correct if you know how much fuel a distance
consumed, which nobody does at a pump. The engine measures between consecutive
*full* fills: the fuel just pumped in is exactly what was burned since the tank
was last full. See [docs/DECISIONS.md](docs/DECISIONS.md) §D3 — this is the
single most important idea in the codebase and the reason `isFullTank` and
`missedFillUp` exist on every entry.

The lifetime figure is **distance-weighted** (total distance ÷ total fuel), not
the mean of per-tank figures. Those differ; only the first is honest.

### 4. No code generation

No `build_runner`, `freezed`, `json_serializable` or `drift`. All `toMap` /
`fromMap` / `copyWith` are hand-written. Codegen cannot run in the environment
this was built in, and reintroducing it means nobody can edit models there.

### 5. Avoid Flutter APIs that are mid-rename

The exact Flutter version is unknown, so the code deliberately sticks to
long-stable APIs:

| Avoided | Used instead | Why |
|---|---|---|
| `ThemeData.cardTheme`, `appBarTheme`, `inputDecorationTheme` | `AppCard` widget, `AppTheme.inputDecoration()` | Their types changed to `*ThemeData` variants across versions |
| `DropdownButtonFormField(initialValue:)` | `value:` | `initialValue` does not exist on older Flutter |
| `RadioListTile(groupValue:, onChanged:)` | plain `ListTile` + check icon | Mid-deprecation in favour of `RadioGroup` |
| `intl` package | `lib/core/formatters.dart` | `flutter_localizations` pins `intl`; hand-rolling ~80 lines avoids a dependency-solve wedge |

If you add a widget, prefer the boring, decade-old API.

### 6. `copyWith` uses an `_unset` sentinel

Models need to distinguish "leave this field alone" from "set this field to
null". `copyWith(year: null)` genuinely clears the year. Do not replace this
with `??`, which makes clearing impossible.

### 7. Public fields do not type-promote

Dart 3.2 promotes only *final private* fields. Everything here uses public
fields, so `vehicle.year != null` does **not** promote `vehicle.year`. The code
uses explicit `!` after null checks, or copies to a local first. Both patterns
are intentional.

---

## Layout

```
lib/
  core/      units, formatting, validation, theme, UnitFormatter
  models/    Vehicle, FuelEntry, ServiceRecord, stats, settings
  domain/    PURE DART engines — the logic worth testing
  data/      SQLite schema + migrations, DAOs, backup, CSV import
  state/     ChangeNotifier controllers (provider)
  ui/        screens/ and widgets/
test/        7 suites; see docs/TESTING.md
docs/        everything below
```

| Doc | What it is for |
|---|---|
| [HANDOFF.md](docs/HANDOFF.md) | **Start here.** State of play, next actions |
| [TODO.md](docs/TODO.md) | Prioritised task list, including likely-broken constructs |
| [PLAN.md](docs/PLAN.md) | The original design document and full idea list |
| [ARCHITECTURE.md](docs/ARCHITECTURE.md) | Code map, layering, data flow |
| [DECISIONS.md](docs/DECISIONS.md) | Why things are the way they are |
| [SCHEMA.md](docs/SCHEMA.md) | Database schema and how to add a migration |
| [TESTING.md](docs/TESTING.md) | What is covered, what was verified, what was not |
| [DEVELOPMENT_LOG.md](docs/DEVELOPMENT_LOG.md) | Commit-by-commit history |
| [SESSION_CONTEXT.md](docs/SESSION_CONTEXT.md) | What the user asked for, verbatim intent |

---

## Environment notes

- **Windows 11.** Both PowerShell and a Git Bash shell are available; they take
  different syntax.
- Git warns `LF will be replaced by CRLF` on nearly every write. Harmless.
- Repo: `github.com/KhizirFarrukh/vehicle_fuel_average_calculator`
- Work is on **`feature/multi-vehicle-fuel-tracking`**, branched from `main`.
  `main` still holds the original 103-line calculator.
- Commit style: a short subject naming the phase or idea number, then a body
  explaining *why*, not what. Trailer:
  `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`

## Platform support

Android, iOS, macOS, Windows, Linux. **Web does not build** — `sqflite` needs
`sqflite_common_ffi_web`, and `lib/data/app_database.dart` imports `dart:io`.
That is a known, documented limitation, not a bug to be surprised by.
