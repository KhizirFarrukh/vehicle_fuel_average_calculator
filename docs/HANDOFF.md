# Handoff — state of play

**Last updated:** 19 September 2026
**Branch:** `feature/multi-vehicle-fuel-tracking` (18 commits ahead of `main`)
**Working tree:** clean

Read [../CLAUDE.md](../CLAUDE.md) first if you have not. This file says where
work stopped and what to do next.

For *how* it got here — turn by turn, including what was rejected and why — see
[archive/SESSION-01-rebuild.md](archive/SESSION-01-rebuild.md).

---

## Where things stand

| | |
|---|---|
| Dart files | 49 (40 in `lib/`, 9 in `test/`) |
| Lines | ~12,500 |
| Test suites | 9 |
| Schema version | 2 |
| Backup format version | 2 |
| **Compiled?** | **No. Never.** |
| **Run?** | **No. Never.** |
| **Tests executed?** | **No. Never.** |

Everything in the original request is implemented, plus four items from the
Tier 2 roadmap. Feature work stopped deliberately — see "Why work stopped"
below.

---

## Do this first

Nothing else matters until the code compiles.

```bash
cd "path/to/vehicle_fuel_average_calculator"
flutter pub get      # dependency set changed; this is required
flutter analyze
flutter test
```

Then work through [TODO.md](TODO.md), which lists the specific constructs most
likely to be wrong and why, ordered by how likely they are to bite.

**Expect analyzer output.** ~12,500 lines written without a compiler will not
be clean on the first run. Nothing *structural* should be wrong — imports,
symbols, and bracket balance were all verified mechanically — but individual
API signatures could not be.

**Do not start new features until `flutter analyze` is clean and
`flutter test` passes.**

---

## What was asked for, and whether it is done

The user's original request, in their words, was to pick up the existing
project and add:

> "functionality to store history of fuel averages, fuel refilling (the amount
> refilled, the cost of that refill, trips and ODO kms at which fuel was
> refilled) data and ability to have multiple vehicles data being stored by
> make, model, variant, year, color and license plate. make year, color and
> license plate optional. each vehicle will have its own record."

| Requirement | Status | Where |
|---|---|---|
| History of fuel averages | Done | `lib/domain/fuel_calculator.dart`, Overview + Charts tabs |
| Amount refilled | Done | `FuelEntry.volume` (litres, canonical) |
| Cost of refill | Done | `FuelEntry.totalCost` |
| Trip at refill | Done | `FuelEntry.tripMeter` (optional) |
| ODO km at refill | Done | `FuelEntry.odometer` (required) |
| Multiple vehicles | Done | `Vehicle`, garage screen, per-vehicle records |
| make / model / variant **required** | Done | validated in `vehicle_form_screen.dart` |
| year / colour / plate **optional** | Done | nullable columns, no validation beyond range |
| Each vehicle its own record | Done | FK with `ON DELETE CASCADE` |

They also asked for a list of my own ideas and a stored plan before building
both are in [PLAN.md](PLAN.md) §3 and §7.

---

## Beyond the request

Implemented on top (idea numbers refer to [PLAN.md](PLAN.md) §3):

- **I19 Service & maintenance log** — schema v2. What was done, when, at what
  odometer, what it cost, next due by distance and/or date. Overdue items
  surface on the garage list.
- **I20 Vehicle comparison** — ranks the garage on six measures.
- **I22 Station price memory** — recent stations as taps on the entry form;
  per-station spend; a deliberately hedged cheapest-station ranking.
- **I23 CSV import** — reads this app's export and other fuel apps'.
- Plus everything in Tier 1 (I1–I18): unit system, full/partial tank flags,
  outlier detection, backup/restore, dark mode, charts, and the original
  calculator preserved as a Quick Calculator.

---

## Why work stopped where it did

Every remaining roadmap item needs something the build environment could not
provide:

| Item | Blocker |
|---|---|
| I21 home-screen widget | Native Kotlin (AppWidget) + Swift (WidgetKit), or the `home_widget` plugin |
| I24 receipt photos | `image_picker` — a new dependency whose version solve cannot be checked |
| I25 localisation | `flutter_localizations` pins `intl`, the exact dependency the architecture avoids; and it touches every string |

Adding more unverified code past that point costs more than it returns. The
useful next step is a working toolchain, not more features.

---

## Two deliberate scope reductions

Both were made to avoid dependencies that could not be version-solved. Both are
easy to finish once the app builds.

1. **Export writes to the app documents directory and shows the path** with a
   copy-to-clipboard button, instead of opening a system share sheet.
   → add `share_plus`.
2. **Restore takes pasted JSON**, and CSV import takes pasted text, rather than
   a file picker. → add `file_picker`.
   `BackupService.restoreFromFile()` already exists and is tested; only the
   picking UI is missing.

---

## Review pass, 19 September 2026

Still no SDK, so the logic was read for bugs instead. Two real ones, both fixed
with regression tests. Detail in [DEVELOPMENT_LOG.md](DEVELOPMENT_LOG.md)
phase 4.

1. **Replace-mode restore deleted the garage before parsing the backup** — a
   nearly-valid file wiped everything and then threw, with no undo. Now the
   whole payload is parsed before anything is deleted. [DECISIONS §D16](DECISIONS.md)
2. **Engine warnings hardcoded `km`** around canonical values, so a miles reader
   saw kilometre numbers labelled `km`. Issues now carry structured figures that
   the UI formats. [DECISIONS §D15](DECISIONS.md)

This is worth knowing for two reasons. It shows the mechanical checks genuinely
do not catch logic errors — so the remaining ~12,700 unrun lines should be
assumed to hold more of the same. And the restore bug is the kind that only
surfaces when someone is already in trouble, which is the worst time to find it.

---

## Things that will look like bugs but are not

- **Web does not build.** `sqflite` + `dart:io`. Documented, intentional.
- **A vehicle with one fill-up shows no average.** Correct. A fuel average
  needs two full tanks — the first only sets the reference level. The UI says
  so in words rather than showing `0.0`.
- **An entry marked "missed fill-up" produces no average for its stretch.**
  Correct, and the point of the flag.
- **`main` looks empty by comparison.** All the work is on the feature branch.
