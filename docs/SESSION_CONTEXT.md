# Session context

What the user asked for and how the work unfolded, preserved so a fresh agent
does not have to re-derive intent from the code.

**Session:** 23–25 August 2026, single continuous session.
**Repo:** `github.com/KhizirFarrukh/vehicle_fuel_average_calculator`
**User:** Khizir Farrukh (`khizirkfc@gmail.com`)

---

## The original request

Near-verbatim:

> "see what was being worked on, analyze the code, and then start working from
> where it was left off. also, it needs to have functionality to store history
> of fuel averages, fuel refilling (the amount refilled, the cost of that
> refill, trips and ODO kms at which fuel was refilled) data and ability to
> have multiple vehicles data being stored by make, model, variant, year,
> color and license plate. make year, color and license plate optional. each
> vehicle will have its own record. if you have your own ideas, make list of
> them. and make sure to make a detailed plan, store that then start working
> according to that."

Four distinct instructions:

1. Pick up the existing project (a 103-line calculator on `main`).
2. Add the listed features.
3. **Produce a list of my own ideas** → [PLAN.md](PLAN.md) §3, 28 items in
   three tiers.
4. **Write a detailed plan and store it before building** → [PLAN.md](PLAN.md),
   written and committed first as `P0`.

## Follow-up instructions

- *"continue"* (several times) — keep working through the roadmap.
- *"commit after each stage, and continue"* — hence one commit per phase and
  per feature, and the branch off `main`.
- *"save the chat context into a file… development stages… plans… todo list…
  if i forgot something, save that too"* — this documentation set.
- *"commit those files and all the progress up till now and push."*

---

## How it went

**Investigation.** `main` had one file: two text fields, a button,
`distance / fuel`. No tests, no persistence, no models. Also no Flutter SDK
anywhere on the machine — checked `PATH`, `C:\`, `%LOCALAPPDATA%`, `C:\dev`,
`C:\src`, `C:\tools`, `Program Files`. That constraint shaped every subsequent
decision.

**Planning.** [PLAN.md](PLAN.md) written and committed before any code:
requirements, architecture, schema, the algorithm, 28 ideas, 13 phases.

**Build.** Phases P0–P13 in ten commits, then Tier 2 features I20, I23, I19 and
I22 in five more. Full breakdown in
[DEVELOPMENT_LOG.md](DEVELOPMENT_LOG.md).

**Stopping point.** Work stopped at I22 deliberately. Everything still open
needs either a dependency whose version solve cannot be checked without an SDK,
or native platform code. Adding more unverified code past that point costs more
than it returns.

---

## The one substantive disagreement with the original code

The existing app computed `distance / fuel`. I did not preserve that as the
basis for tracking, and the reasoning matters:

That formula answers *"what average did this tank give, assuming I know exactly
how much fuel that distance consumed?"* — and at a pump, nobody does. You know
what you just put in, not what you burned.

So the engine measures **tank to tank** instead. Full reasoning in
[DECISIONS.md](DECISIONS.md) §D3. This is why `FuelEntry` carries
`isFullTank` and `missedFillUp`, and why a vehicle with one fill-up shows no
average rather than `0.0`.

The original calculator was **not** deleted — it survives as the Quick
Calculator (`lib/ui/screens/quick_calculator_screen.dart`), where the user
asserts the fuel used and the simple formula is the right answer to *that*
question. It also now disposes its controllers, which the original did not.

---

## Judgement calls made without asking

Recorded so they can be reversed knowingly.

| Call | Reasoning |
|---|---|
| Tank-to-tank instead of `distance / fuel` | Correctness. See above. |
| Branched off `main` rather than committing to it | `main` is the default branch; the user asked for commits, not for `main` to be rewritten. Merge or rebase as preferred. |
| Export shows a file path + copy button, no share sheet | Avoided `share_plus`, unverifiable. Easy to finish. |
| Restore and CSV import take pasted text, not a file picker | Avoided `file_picker`. `BackupService.restoreFromFile()` already exists and is tested. |
| Charts hand-drawn with `CustomPainter` | Avoided a charting dependency. |
| Formatting hand-rolled | Avoided `intl`, which `flutter_localizations` pins. |
| Extra fields beyond the request: fuel type, tank capacity, initial odometer, station, notes, full/partial flag, missed-fill flag | The last two are *required* for correct averages; the rest are cheap and unlock the range estimate and station features. |
| Archive as well as delete | Deleting a vehicle destroys its history; people who sell a car still want its records. |
| Stopped at I22 | Remaining items need unverifiable dependencies or native code. |

---

## What the user has been told, repeatedly

That **none of this has been compiled or run**, and that the first real step is:

```bash
flutter pub get && flutter analyze && flutter test
```

This is stated in [../CLAUDE.md](../CLAUDE.md), [HANDOFF.md](HANDOFF.md),
[TODO.md](TODO.md), [TESTING.md](TESTING.md) and [PLAN.md](PLAN.md). It is the
single most important fact about the current state of the repository, and no
claim of correctness anywhere should be read as "verified".

---

## Working style established

- Commit per stage; subject names the phase or idea number; body explains
  *why*; trailer `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`.
- Comments explain reasoning, not mechanics. Several encode constraints
  (e.g. *"`value:` rather than `initialValue:` — the latter is absent on older
  Flutter"*) and are load-bearing.
- Where the app cannot know something, it says so — `—`, "no average yet", a
  stated caveat on the station ranking — rather than showing a confident zero.
- Trade-offs are named in the docs rather than hidden.
