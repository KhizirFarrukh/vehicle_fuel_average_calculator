# Session 01 — rebuilding the fuel calculator

A record of the conversation that turned a 103-line calculator into this
codebase. Written so the reasoning survives losing the chat.

| | |
|---|---|
| **Dates** | 23 August – 19 September 2026 |
| **Agent** | Claude Opus 5, via Claude Code on Windows 11 |
| **User** | Khizir Farrukh (`khizirkfc@gmail.com`) |
| **Branch** | `feature/multi-vehicle-fuel-tracking`, off `main` |
| **Commits** | 18 |
| **Net change** | 62 files, +14,721 / −89 |
| **Ended with** | ~12,700 lines of Dart, none of it ever compiled or run |

> **The defining constraint:** no Flutter SDK, no Dart SDK, no Python and no
> Node on the machine, for the entire session. Every decision below was shaped
> by the inability to compile, run, or test anything.

---

## Turn 1 — the original request

The user asked (near-verbatim):

> "see what was being worked on, analyze the code, and then start working from
> where it was left off. also, it needs to have functionality to store history
> of fuel averages, fuel refilling (the amount refilled, the cost of that
> refill, trips and ODO kms at which fuel was refilled) data and ability to
> have multiple vehicles data being stored by make, model, variant, year,
> color and license plate. make year, color and license plate optional. each
> vehicle will have its own record. if you have your own ideas, make list of
> them. and make sure to make a detailed plan, store that then start working
> according to that."

Four instructions: pick up the existing work, add the listed features, produce
my own idea list, and write and store a plan *before* building.

### What was found

`main` held one file: `lib/main.dart`, 103 lines. Two `TextField`s, a Calculate
button, `distance / fuel`, result in a `Text`. No models, no persistence, no
tests, no dependencies beyond `flutter_lints`. Two `TextEditingController`s
never disposed.

Then the discovery that shaped everything: **no Flutter SDK anywhere**. Checked
`PATH`, `C:\`, `%LOCALAPPDATA%`, `C:\dev`, `C:\src`, `C:\tools` and
`Program Files`. Nothing. Reported immediately rather than discovered later.

### Consequences accepted at the outset

| Ruled out | Because | Chosen instead |
|---|---|---|
| `drift`, `freezed`, `json_serializable` | `build_runner` cannot run | hand-written `toMap`/`fromMap`/`copyWith` |
| `intl` | `flutter_localizations` pins it; a wedged solve could not be diagnosed | `lib/core/formatters.dart` |
| `fl_chart` and friends | unverifiable dependency solve | two `CustomPainter` charts |
| `share_plus`, `file_picker` | same | show a file path; accept pasted text |
| Newer Flutter APIs | version unknown | long-stable APIs only |

### The plan

`docs/PLAN.md` written and committed **first**, as asked: requirements,
architecture, schema, the algorithm, 28 ideas in three tiers, 13 phases.

### The one substantive disagreement with the existing code

The app computed `distance / fuel`. That answers *"what average did this tank
give, assuming I know exactly how much fuel that distance consumed?"* — and at
a pump nobody does. You know what you just put in, not what you burned.

So the engine measures **tank to tank**: fill to full at `O2`, having last
filled to full at `O1`; the fuel just pumped in is precisely what was burned
over `O2 − O1`, because the tank is back at the same reference level.

Everything else follows — `isFullTank`, `missedFillUp`, two full tanks before
any average exists, distance-weighted lifetime figures. Recorded as
[DECISIONS §D3](../DECISIONS.md).

The original calculator was **not** deleted. It survives as the Quick
Calculator, where the user *asserts* the fuel used and the simple formula is the
right answer to that question. It also now disposes its controllers.

### Built: phases P0–P13, ten commits

`ccacc0e` plan and deps · `4935ecd` core · `8806d6a` models · `6fa6b35` the
engine · `5f7ff7b` schema v1 + DAOs + backup · `4f0a0ce` controllers ·
`8b02117` widgets and charts · `4e08b1a` all screens · `ea7b9de` five test
suites · `97cc5d3` README.

30 files in `lib/`, ~8,000 lines, every Tier 1 idea (I1–I18).

### Verification, in the absence of a compiler

Mechanical checks over the whole tree: every relative import resolves, every
`package:` import is declared, every cross-file symbol is imported where used,
no unused imports, brackets balanced, quote style consistent, and a manual
null-promotion audit (public fields do not promote in Dart, so explicit `!`).

Stated plainly and repeatedly that this is not a compiler.

---

## Turn 2 — "commit after each stage, and continue"

Interpreted as: commit per phase, and work down the Tier 2 roadmap.

Branched off `main` first rather than committing to the default branch — a
judgement call, left for the user to merge or rebase as they prefer.

### I20 — vehicle comparison (`315fb08`)

Ranks the garage on six measures. The detail worth keeping: **bars are drawn
from the canonical value, not the displayed one.** Otherwise a reader using
L/100 km sees the longest bar against their thirstiest car while the header
claims longer is better.

Vehicles with no figure go under "Not enough data" rather than ranking last,
which would read as a result rather than an absence.

### I23 — CSV import (`228f39f`)

RFC 4180 parser; headers matched by alias so other apps' exports usually work
unchanged. Two things are **asked, never guessed**, because guessing wrong
corrupts data silently: the units the file is in, and whether `03/04/2026` is
3 April or 4 March. Impossible dates are rejected rather than left to
`DateTime`'s rollover — month 13 quietly becoming next January would turn a
misread column into plausible-looking data. Nothing is written until the parse
has been shown.

### I19 — service log, in two commits

`05b2bca` data layer: schema **v2**, with the new table's DDL as a shared
constant used by *both* `_create` and `_upgrade`, because duplicating it is how
migrations rot. The migration test builds a v1 database by hand, runs the real
upgrade, and checks both that the table appears and that v1 rows survive —
against a **temp file, not `:memory:`**, since each in-memory open is a new
database and a migration cannot be observed across one.

`845e51e` UI: fourth tab, FAB follows the visible tab, reminders read out both
limits, overdue items surface on the garage card.

### I22 — station price memory (`e26976b`)

Recent stations as taps on the entry form; per-station spend. The cheapest
ranking is deliberately hedged: 180-day window, minimum two visits, and it
refuses to rank at all below two qualifying stations — a ranking of one is not a
ranking. Pump prices move, so an all-time average compares the calendar as much
as the forecourt, and the card says so.

### Stopping point

Stopped at I22 deliberately and said why: I21 needs Kotlin/Swift widget targets,
I24 needs `image_picker`, I25 needs `flutter_localizations` (which pins the
`intl` the architecture avoids) and would touch every string. Adding more
unverified code past that point costs more than it returns.

---

## Turn 3 — "save the chat context… if i forgot something, save that too"

Asked for the chat context, development stages, plans and a todo list as
separate files, plus anything overlooked, then commit and push.

Delivered `e549f22`: **`CLAUDE.md`** at the repo root (Claude Code loads it
automatically, so a fresh agent gets it unprompted) plus nine documents.

Asked for: `HANDOFF.md`, `DEVELOPMENT_LOG.md`, `SESSION_CONTEXT.md`, `TODO.md`,
`PLAN.md`.

**Added unasked, in descending order of how much I would regret losing them:**

1. **`DECISIONS.md`** — every decision with *the alternative that was rejected*.
   Code shows what you chose; it never shows what you chose against. Without
   this, the next agent "fixes" `DropdownButtonFormField(value:)` to
   `initialValue:` and breaks the build on older Flutter.
2. **`ARCHITECTURE.md`** — code map, the pure-Dart layering rule, two traced
   data flows.
3. **`SCHEMA.md`** — tables plus a migration recipe, flagging the trap that a
   migration test against `:memory:` silently tests nothing.
4. **`TESTING.md`** — separates what was verified mechanically from what only a
   compiler catches, so nobody reads "checked" as "passing".

Every one states that the code has never been compiled. A fresh agent reading
confident documentation about 12,500 unverified lines would be misled in exactly
the way that costs the most time.

Pushed to `origin`, 17 commits. First push of the branch.

---

## Turn 4 — "continue" (new session, 19 September)

Re-checked for Flutter in both shells and the usual install roots. Still absent;
`winget` present but installing a multi-gigabyte SDK that edits `PATH` was left
as the user's call.

So: **read the logic for bugs.** The earlier checks were mechanical and cannot
catch logic errors. Two real ones found.

### 1. Restore destroyed data before validating the backup — severe

Replace-mode restore deleted the garage and *then* parsed each vehicle as it
inserted it. The three header checks (format id, version, `vehicles` is a list)
only prove the file is shaped like ours — a truncated write, a disk error or one
hand-edited field still gets through, and the `as String?` / `as num?` casts in
the model parsers throw on the wrong type.

So a nearly-valid backup **wiped everything and then failed partway**. No
transaction, no undo. The worst outcome the app can produce, from the one
feature people reach for precisely when they cannot afford to lose anything.

Fixed by parsing the whole payload into models first; nothing is deleted until
every row is known readable. A transaction was the alternative but would mean
threading a `Transaction` through every DAO for one caller's benefit.
[DECISIONS §D16](../DECISIONS.md).

### 2. Engine warnings hardcoded `km` — cosmetic but wrong

*"Trip meter says 250 km but the odometer moved 400 km"* — canonical values, so
a reader set to miles saw kilometre figures labelled `km` on a screen where
everything else was miles. The engine cannot fix this itself: pure Dart by rule,
no business knowing display preferences.

`EntryIssue` now carries an `IssueKind` and the raw figures with a unit-free
`message` as fallback; `core/issue_text.dart` renders the sentence.
[DECISIONS §D15](../DECISIONS.md).

### A suspected third bug, investigated and dismissed

`num.clamp()` appears to return `num`, which would break four call sites where a
`double` is wanted. I was about to change all four — then worked out that Dart
special-cases `clamp` to return `double` when the receiver and both bounds are
`double`. They were already correct.

**Left alone rather than churned on a guess**, and noted in `TODO.md` for the
analyzer to settle. Recording this because the temptation to "fix" working code
from an uncertain recollection is itself a hazard of working without a compiler.

Committed as `19c2cc4` with both fixes, `test/issue_text_test.dart` (ninth
suite) and a regression test asserting that a damaged backup leaves the counts
unchanged.

---

## Turn 5 — archive

This file, its index, and a push.

---

## Commit list

| Hash | Date | Subject |
|---|---|---|
| `85a7962` | 2025-01-07 | *(on `main`)* version 0.0.1 — basic structure ready |
| `ccacc0e` | 2026-08-23 | P0: plan, dependencies and lint configuration |
| `4935ecd` | 2026-08-23 | P1: unit system, formatting, validation and theme |
| `8806d6a` | 2026-08-23 | P2: Vehicle, FuelEntry, statistics and settings models |
| `6fa6b35` | 2026-08-23 | P3: tank-to-tank fuel economy engine |
| `5f7ff7b` | 2026-08-23 | P4: SQLite schema, DAOs and backup service |
| `4f0a0ce` | 2026-08-23 | P5: garage and settings controllers |
| `8b02117` | 2026-08-23 | P6: shared widgets and hand-painted charts |
| `4e08b1a` | 2026-08-23 | P7-P11: screens, navigation and app shell |
| `ea7b9de` | 2026-08-23 | P12: unit and in-memory database tests |
| `97cc5d3` | 2026-08-23 | P13: rewrite README |
| `315fb08` | 2026-08-23 | I20: multi-vehicle comparison screen |
| `228f39f` | 2026-08-24 | I23: CSV import |
| `05b2bca` | 2026-08-24 | I19 (data layer): service records, schema v2 and reminders |
| `845e51e` | 2026-08-25 | I19 (UI): service tab, reminders and maintenance costs |
| `e26976b` | 2026-08-25 | I22: station price memory and suggestions |
| `74adc78` | 2026-08-25 | docs: record Tier 2 progress and why the rest is blocked |
| `e549f22` | 2026-08-28 | docs: handoff set so the work survives losing the chat |
| `19c2cc4` | 2026-09-19 | fix: two bugs found reviewing the never-run code |

## Final state

| | |
|---|---|
| `lib/` | 40 files, 10,382 lines |
| `test/` | 9 files, 2,352 lines |
| Docs | 11 files, 1,977 lines |
| Schema version | 2 |
| Backup format version | 2 |
| Compiled / run / tested | **never** |

---

## Judgement calls made without asking

Recorded so they can be reversed knowingly.

| Call | Reasoning |
|---|---|
| Tank-to-tank instead of `distance / fuel` | Correctness. The old formula needs information nobody has at a pump. |
| Branched off `main` | `main` is the default branch; commits were asked for, not a rewrite of `main`. |
| Export shows a path; restore and import take pasted text | Avoided `share_plus` / `file_picker`, unverifiable. `restoreFromFile()` exists and is tested; only the picker is missing. |
| Charts hand-drawn | Avoided a charting dependency. |
| Formatting hand-rolled | Avoided `intl`. |
| Extra fields beyond the request | `isFullTank` and `missedFillUp` are *required* for correct averages; fuel type, tank capacity, station and notes are cheap and unlock range and station features. |
| Archive as well as delete | Deleting a vehicle destroys its history; people who sell a car still want the records. |
| Stopped feature work at I22 | Everything left needs unverifiable dependencies or native code. |
| Wrote four documents nobody asked for | The reasoning is the expensive part to reconstruct. |
| Did not install Flutter via `winget` | Multi-gigabyte download that edits `PATH`; the user may want a specific channel or `fvm`. Offered instead. |
| Left `num.clamp()` alone | Verified correct on reflection; changing it would have been churn from a misremembering. |

## What a fresh agent should do first

```bash
flutter pub get
flutter analyze
flutter test
```

Then [../TODO.md](../TODO.md) P0, which lists the constructs most likely to be
wrong, ranked. Do not add features before the existing code compiles.

The two bugs found in turn 4 are the evidence for why: mechanical checks passed
cleanly on both, and one of them silently destroyed user data.
