# COR-86 — Release measurability and a bounded main actor

> **Status: proposed, not approved.** `docs/plans/README.md` says this directory holds only
> approved plans. This file and its four siblings are awaiting the approval `CLAUDE.md` §7
> requires; if they are declined, delete them.

- **Executor:** any implementer, unattended. This increment changes one build setting, adds one
  metric to a closed enum, and adds tests. It demands no product judgement. The one judgement it
  does demand — that the new requirement lands `Correction` rather than `Done` — is stated below
  and is not negotiable within the increment.
- **Blockers:** none.
- **Independently landable:** yes. Nothing else in COR-87…COR-90 depends on it except COR-88's
  and COR-89's measurements, which are downstream.
- **Requirements moved to `Done`:** none. This increment **adds** one requirement in
  `Correction` status and re-observes REQ-090's evidence. A plan that closes no requirement is
  legitimate here because its product is measurement, not behavior.
- **Architecture impact:** one ENGINEERING driver is restated and one component is documented.
  Both are corrections of the document to the code that already exists, not architecture changes,
  so `CLAUDE.md` §6 does not apply. Called out explicitly below so a reviewer can disagree.

## The defect

Two halves of one problem: the app cannot measure the thing that matters, and does not bound the
thing it already measures.

**Release tests do not build.** `ENABLE_TESTABILITY = YES` appears once in `project.pbxproj`, in
the app target's Debug configuration. Every test uses `@testable import Markdown_Editor`, so
`xcodebuild test -configuration Release` into clean derived data fails with
`Unable to resolve Swift module dependency to a compatible module: 'Markdown_Editor'`. Observed
2026-08-22. ROADMAP COR-18 claims Debug **and Release** tests compile and execute; REQ-090 cites
six p95 figures from a focused Release run. Those figures are now frozen evidence with no path
back to them — the same rot `DECISIONS.md` records for the manifest `find` fields, where the
release gate reported `PASS` over zero manifests for months.

**The main-actor block is recorded and never bounded.** `EditorSemanticWorker.sync` waits on a
semaphore from the main thread and adds the elapsed time to `WorkLedger.mainThreadBlockedNanos`,
which is serialized into every run log. The only test that mentions the field constructs the
literal `9` in an encoding fixture (`DiagnosticLogTests.swift:166`). Measured cost of that block:
21.9–181.3 ms in Debug — see `docs/research/2026-08-22-semantic-command-main-actor-cost.md`.

`PerformanceBudgetTests.everyMetricHasABudget` exists to prevent exactly this, and its own doc
comment names the failure: *"an unbudgeted metric is reported but never compared against anything,
which reads as coverage and proves nothing."* It cannot see this one, because the closed set it
iterates is `PerformanceSampler.Metric` and this duration is recorded on `WorkLedger` instead.
**The guard is correct; the field is outside it.**

## Why the obvious fix is a band-aid

Adding a `semanticCommand` metric and stopping there leaves two places a duration can be
recorded — one inside a closed budgeted set and one outside it — with nothing preventing the next
duration from landing in the unguarded one. The defect is not the missing metric. It is that the
closed set does not cover its own domain.

## The proper fix

1. `ENABLE_TESTABILITY = YES` on the app target's **Release** configuration.
2. Add `PerformanceSampler.Metric.semanticCommand`, budget **16 ms** — a frame, because this is
   main-actor work the user waits on, the same reasoning REQ-116 already applies to
   `layoutApplication`. Sample it in `EditorSession` around the **whole command path**, not around
   `EditorSemanticWorker.sync`, so the recorded number is user-visible latency rather than one
   component of it.
3. Close the second door: every nanosecond-valued field on `WorkLedger` must name a
   `PerformanceSampler.Metric`. Preferred form is to make the field unreachable except through the
   sampler; if that proves impractical against the existing `WorkLedger` reduction arithmetic, the
   fallback is a closed-set test in the style already used for `EditorCommand.allCases`.

## Files, types, and routes

### Modify

- `Markdown Editor.xcodeproj/project.pbxproj` — `ENABLE_TESTABILITY = YES` in the app target's
  Release configuration.
- `Markdown Editor/PerformanceSampler.swift` — add `Metric.semanticCommand`, its `symbol`, and its
  entry in `budgetNanos`.
- `Markdown Editor/EditorSession.swift` — sample the command path. The site is the branch that
  calls `EditorSemanticWorker.sync` around `SemanticEditEngine.plan`, widened to cover reduction
  and acceptance.
- `Markdown Editor/WorkLedger.swift` — restrict or annotate `mainThreadBlockedNanos`.
- `Markdown Editor/EditorTrace.swift`, `JSONLinesEditorTrace.swift`, `DiagnosticRecord.swift` — if
  and only if a new symbol is required; the existing `budgetExceeded` event already carries a
  `Metric` and should need no change.
- `docs/ENGINEERING.md` — restate driver 6; add an `EditorSemanticWorker` section.
- `docs/REQUIREMENTS.md` — one new row.
- `docs/research/COR-71-release-performance.md` — record the exact reproducing command and the
  re-taken figures.
- `CLAUDE.md` §3 — add: *every recorded measurement carries a bound.*

### Add

- `Markdown EditorTests/SemanticCommandBudgetTests.swift`.

### Delete

Nothing. This increment displaces no path.

## Ordered phases

1. Restore Release testability. Observe `xcodebuild test -configuration Release` building. If it
   fails for a reason other than testability, **stop and re-plan** — that is a finding.
2. Re-take REQ-090's six p95 figures in Release. Record command, machine, build configuration,
   corpus, sample count, median and p95, per VISION. If any figure now misses its budget, stop:
   REQ-090 moves to `Correction` and that is a separate increment.
3. Add the metric and its budget. `PerformanceBudgetTests` gains the literal.
4. Sample the command path in `EditorSession`.
5. Add `SemanticCommandBudgetTests`. **Observe it fail** — this is the whole point; a green test
   here would mean the sampling is not measuring the block.
6. Close the `WorkLedger` door with the closed-set proof.
7. Write the new requirement as `Correction`, with the research document as its counterexample.
   Restate ENGINEERING driver 6 and document `EditorSemanticWorker`.
8. `Scripts/check.sh`. Report its actual output.

## Requirements and architecture

**New requirement.** *WHILE a semantic formatting command executes, the system shall complete its
main-actor work within 16 ms p95 on the approved performance corpus.* Status on delivery:
**`Correction`**, with the measured counterexample in
`docs/research/2026-08-22-semantic-command-main-actor-cost.md`. Per REQUIREMENTS' own convention,
a row moves to `Correction` in the same change that reproduces a defect against it. COR-88 and
COR-89 close it.

**ENGINEERING driver 6** currently reads *"synchronous edit translation stays below the
interactive budget while parsing and image work remains off-main."* The parse **is** off-main; the
main thread waits for it. The invariant constrains **where work runs** rather than **whether the
main actor blocks**, and is therefore satisfied by the exact behavior it exists to prevent.
Restate as: *"no user-initiated interaction blocks the main actor beyond the interactive budget,
whichever thread the work executes on."*

**`EditorSemanticWorker` appears zero times in ENGINEERING's 792 lines**, despite being the only
component in the app that blocks the main actor. It gets a section.

## Automated non-UI proof

- `semanticCommandBlockIsBudgeted` — drives a real command through the production `EditorSession`
  route on each `PerformanceCorpus` case and asserts the recorded `semanticCommand` sample against
  the budget. **Expected red on delivery.**
- `semanticCommandSampleIsRecordedForEveryCommand` — iterates `EditorCommand.allCases`; every
  command that mutates must produce exactly one sample. Closed-set, so a new command fails the
  build until its sampling is declared. **Expected green.**
- `everyRecordedDurationNamesABudgetedMetric` — closed-set over `WorkLedger`'s duration fields.
- `PerformanceBudgetTests.budgetsMatchTheApprovedRequirementValues` gains the 16 ms literal.

What turns these red: removing the `semanticCommand` case, changing the budget literal without
changing REQUIREMENTS, or removing the sampling call from `EditorSession`.

## Instrumentation and performance evidence

The new metric flows through the existing `PerformanceSampler.flush()` → `budgetExceeded` route,
so an over-budget command appears in the run log with no new plumbing. Release evidence for
REQ-090 is re-recorded in research. No new diagnostic payload type, so REQ-031's privacy boundary
is untouched — the metric is an enumerated symbol and an integer.

## Failure and rollback behavior

No runtime behavior changes. The sampler already tolerates any metric being over budget by
recording `budgetExceeded`; nothing refuses, nothing degrades. Rollback is reverting the commit:
the build setting, one enum case, one sampling call, and tests. No data format changes, so a
downgrade reads existing logs unchanged.

## Deletion and conformance gate

Nothing is displaced, so the conformance gate is narrow: `grep` proves no second unbudgeted
duration field survives on `WorkLedger`, and the closed-set test proves it stays that way. The
claim *"Release tests compile and execute"* is either observed true or ROADMAP COR-18 is corrected
in this same change.

## Risk

The new requirement lands `Correction`, the first non-`Done` behavior row since the August
programme closed. That is intended and honest. The alternative — adding the metric with a budget
loose enough to pass — is the failure mode `DECISIONS.md` warns about, satisfying a proxy rather
than fixing the defect.
