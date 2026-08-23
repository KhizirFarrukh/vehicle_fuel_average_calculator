# Fuel Log — Vehicle Fuel Average Calculator

A Flutter app for tracking fuel economy, refuelling history and running cost
across any number of vehicles. Everything is stored locally in SQLite; there is
no account and no cloud.

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
- **Units of your choosing** — km/L, L/100 km, mpg (US) or mpg (imperial),
  kilometres or miles, litres or gallons, and your own currency symbol.
- **Backup and export** to JSON or CSV.
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
  core/      units, formatting, validation, theme
  models/    Vehicle, FuelEntry, statistics, settings
  domain/    fuel_calculator.dart — the economy engine (pure Dart)
  data/      SQLite schema, DAOs, backup/CSV
  state/     ChangeNotifier controllers
  ui/        screens and widgets
test/        unit tests, including an in-memory database suite
docs/PLAN.md the full design document and roadmap
```

The engine in `lib/domain/fuel_calculator.dart` imports nothing from Flutter, so
the arithmetic can be tested directly:

```bash
flutter test test/fuel_calculator_test.dart
```

## Roadmap

Planned and deliberately deferred work — a maintenance log, vehicle comparison,
CSV import, receipt photos, localisation — is listed in
[docs/PLAN.md](docs/PLAN.md) §3.
