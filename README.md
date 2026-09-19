# Fuel Log — Vehicle Fuel Average Calculator

A Flutter app for tracking fuel economy, refuelling history, running cost and
maintenance across any number of vehicles. Everything is stored locally in
SQLite; there is no account and no cloud.

> ⚠️ **This code has never been compiled or run.** It was written without a
> Flutter SDK available. Run `flutter pub get && flutter analyze &&
> flutter test` before trusting any of it. See
> [docs/HANDOFF.md](docs/HANDOFF.md).

## Getting started

```bash
flutter pub get
flutter test
flutter run
```

> **Note:** the dependency set changed in v0.2.0 (`sqflite`, `path_provider`,
> `provider`). Run `flutter pub get` before building.

Runs on **Android, iOS, macOS, Windows and Linux**. Web is not supported yet:
storage uses `sqflite`, and web would need `sqflite_common_ffi_web`. See
[docs/PLAN.md](docs/PLAN.md) §4.

## What it does

- **Multiple vehicles**, each with its own records. Make, model and variant are
  required; year, colour and licence plate are optional.
- **A refuelling log** per vehicle: litres added, what it cost, and the trip and
  odometer readings at the time.
- **A history of fuel averages**, with cost per kilometre, best and worst
  stretches, and charts of economy, fuel price and monthly spend.
- **A service log** per vehicle — oil, tyres, insurance, anything — with
  next-due reminders by distance, by date, or both. Overdue items show on the
  garage list without opening the vehicle.
- **Side-by-side comparison** of every vehicle on economy, running cost and
  spend.
- **Units of your choosing** — km/L, L/100 km, mpg (US) or mpg (imperial),
  kilometres or miles, litres or gallons, and your own currency symbol.
- **Backup and export** to JSON or CSV, and **CSV import** that reads exports
  from other fuel apps.
- **The original quick calculator**, still one tap away.

## How the average is worked out

Dividing distance by fuel only works if you know exactly how much fuel that
distance used — and at a petrol pump, nobody does. This app measures
**tank to tank** instead:

> Fill to full at odometer `O2`, having last filled to full at `O1`. Whatever
> the pump just put in is precisely what was burned over `O2 − O1`, because the
> tank is back at the same level it started from.

```text
distance = odometer(this full tank) − odometer(previous full tank)
fuel     = litres of this fill + litres of any partial fills in between
average  = distance ÷ fuel
```

Consequences worth knowing:

- **Two full tanks are needed before any average exists.** The first fill only
  sets the reference level. The app says so rather than showing `0.0`.
- **Mark partial fills as partial.** They cannot close a measurement, but their
  litres are carried into the next full tank, so nothing is lost.
- **Mark a fill-up you forgot to log.** The stretch across the gap is discarded
  instead of quietly reporting an average that is too good.
- **The lifetime figure is distance-weighted** (total distance ÷ total fuel),
  not the average of the per-tank figures — those two differ, and only the
  first one is honest.

The app also flags entries that look wrong: duplicate odometer readings, dates
that run backwards, a trip meter that disagrees with the odometer, and any
stretch more than 40 % away from the median.

## Project layout

```
lib/
  core/      units, formatting, validation, theme, issue text
  models/    Vehicle, FuelEntry, ServiceRecord, statistics, settings
  domain/    the engines — economy, service reminders, stations (pure Dart)
  data/      SQLite schema + migrations, DAOs, backup, CSV import
  state/     ChangeNotifier controllers
  ui/        screens and widgets
test/        9 suites, including an in-memory database suite
docs/        design document, decisions, schema, handoff, archive
```

Nothing in `lib/domain/` imports Flutter — nor do `core/` (except `theme.dart`)
or `data/csv_import_service.dart`. All the logic worth testing lives there, so
it can be tested directly:

```bash
flutter test test/fuel_calculator_test.dart
```

## Documentation

| Doc | What it is for |
|---|---|
| [CLAUDE.md](CLAUDE.md) | Rules and conventions for anyone — human or agent — working on this |
| [docs/HANDOFF.md](docs/HANDOFF.md) | **Start here.** Current state and what to do next |
| [docs/TODO.md](docs/TODO.md) | Prioritised tasks, including what is most likely broken |
| [docs/PLAN.md](docs/PLAN.md) | The design document and full idea list |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Code map, layering, data flow |
| [docs/DECISIONS.md](docs/DECISIONS.md) | Why things are the way they are |
| [docs/SCHEMA.md](docs/SCHEMA.md) | Database schema and how to add a migration |
| [docs/TESTING.md](docs/TESTING.md) | Coverage, and what was and was not verified |
| [docs/DEVELOPMENT_LOG.md](docs/DEVELOPMENT_LOG.md) | Commit-by-commit history |
| [docs/SESSION_CONTEXT.md](docs/SESSION_CONTEXT.md) | What was asked for, and judgement calls made |
| [docs/archive/](docs/archive/) | Turn-by-turn records of the sessions that built this |

## Roadmap

Deferred work — a home-screen widget, receipt photos, localisation — and why
each is blocked, is in [docs/PLAN.md](docs/PLAN.md) §3 and
[docs/TODO.md](docs/TODO.md) P4.
