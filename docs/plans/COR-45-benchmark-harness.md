# COR-45 — Honest corpora and the in-app benchmark harness

> **Restored 2026-08-11, partially implemented.** The corpus half landed and REQ-127 is `Done` on
> its own tests. The harness half did not: `Scripts/benchmark.sh` had never completed a run, and
> the baseline committed under its name was written by an earlier driver at commit `b27cf196` —
> 4 rows of the 108 the script iterates, reporting `nativeInput p95 = n/a` and `parses = 1` for a
> *typing* scenario. That baseline is deleted and REQ-128 is back to `Correction`.
>
> Three defects were found by running the script. Two are fixed and stay fixed:
>
> 1. The reconciliation ceiling is a livelock guard sized for a caller driving a handful of edits.
>    This driver issues one edit per interval for the whole duration and reconciles once per
>    accepted edit, so a clean run reported `17 applied (ceiling 4)` and the script died at its
>    first scenario. `verify-smoke-log.py` now takes `--reconciliation-ceiling`; `benchmark.sh`
>    derives it from the edits it drove, so it remains a bound.
> 2. The recorder passed `--fail-on-budget-exceeded`, so it refused to write a baseline until every
>    budget was already met — inverting the ordering this programme rests on, in which measurement
>    precedes every increment that makes anything faster. It failed on a real overrun
>    (`parseProjection` 183.7 ms against a 100 ms budget), which is the finding, not an error.
>
> **What remains is the whole of the remaining work.** `applyCommands` performs every command
> without establishing a selection, so all 40 pass their availability guard and then refuse with
> `mappingFailure`/`ambiguousSelection` — in the scenario whose entire purpose is to exercise those
> routes. Setting a source-mode caret the way `Markdown_EditorApp`'s smoke path does fixes the
> source half (40 refusals → 20). The WYSIWYG half survives a bounded wait for an editable
> projection, so a stale projection is **not** the cause and the cause is not yet known. Start
> there. `EditorCommandController.currentSelection` falls back to the *source* selection when
> WYSIWYG has neither a selection nor an editable presentation, which would produce exactly this
> refusal — first hypothesis to test, not a conclusion.
>
> This is not a product defect: the process-level smoke path performs `.bold` successfully because
> it sets the caret first. The driver is at fault, not the editor.

- **Status:** Approved; not implemented
- **Requirements:** REQ-090 (moves to `Correction` in this increment), REQ-045; REQ-127 (corpus-shape enumeration) is already `Done` and out of scope here; REQ-128 (process-level benchmark with a committed baseline) is what remains
- **Delivers:** REQ-128
- **ARC invariants:** ARC-Q05 restated as "on every approved corpus shape"; ARC-Q12 extended to benchmark scenarios; ARC-026 (COR-44) proved here; ARC-014 (no manual or UI testing) unchanged and explicitly re-argued for the scroll scenario

## Context

`nativeInputCallbackP95Under8ms` builds its corpus as
`String(repeating: "word ", count: 20_000)` — 100,000 UTF-16 units containing no newline, no heading,
no list, no emphasis, no code, no table, no image. cmark sees **one paragraph**;
`MarkdownProjectionModel` produces **one block and one run**. The reported p95 of 4.871 ms is real and
describes a document nobody has.

The other proof, `parseIndexProjectionP95Under100msAt100k`, uses a realistically structured 100,000
unit corpus and measures the same parse+index+projection work at **13.9 ms**. Since
`SemanticEditEngine.plan` performs that work synchronously inside every insertion, 13.9 ms is a
keystroke's floor on a real document, against an 8 ms budget, before TextKit lays anything out.

The two suites are individually sound and jointly blind — the failure mode `CLAUDE.md` §6 already
names from COR-23. `modeToggleP95Under16ms` has the same defect in smaller form: its corpus is
`"# Title\n\nHello world\n"`, 21 characters.

Separately, every existing latency proof constructs sessions directly and never lays out glyphs, so
nothing measures the shipping binary doing the thing a user does.

## Production changes

Production code changes are limited to the benchmark driver; the corpora are test-side.

### 1. New `Markdown EditorTests/PerformanceCorpus.swift`

```swift
nonisolated enum PerformanceCorpus: String, CaseIterable, Sendable {
    case degenerateParagraph, structuredProse, heavyLists, tableDense, codeHeavy, imageHeavy
    func source(utf16Target: Int = 100_000) -> String
    var minimumExpectedBlocks: Int
}
```

| Case | Repeating unit | Minimum blocks per 100k |
| --- | --- | --- |
| `degenerateParagraph` | `"word "` | 1 |
| `structuredProse` | an H2 heading, a blank line, then a prose paragraph carrying strong, emphasis, an inline-code span and an inline link, then a blank line | 1000 |
| `heavyLists` | `"- item\n  - nested\n    - deeper\n- [ ] task\n1. ordered\n\n"` | 2000 |
| `tableDense` | `"\| A \| B \|\n\|---\|---\|\n\| 1 \| 2 \|\n\| 3 \| 4 \|\n\n"` | 800 |
| `codeHeavy` | a three-line fenced Swift block plus a blank line | 800 |
| `imageHeavy` | a CommonMark image reference to `assets/sample.png`, then a blank line, then a one-sentence prose paragraph, then a blank line | 1500 |

Truncation happens on a **unit boundary**, never mid-unit: a truncated fence or table row changes the
parse and would make the corpus a different shape than its name claims. Assert the final length is
within 5 % of target and record the actual length in every evidence line.

`degenerateParagraph` is retained deliberately, as a floor and as a permanent reminder of what a
size-only corpus proves.

### 2. New `Markdown Editor/BenchmarkDriver.swift`

```text
Markdown Editor --benchmark <scenario> --corpus <shape> --size <utf16> --duration <seconds>
```

| Scenario | Drives | Exposes |
| --- | --- | --- |
| `typeProse` | 40 insertions inside ordinary paragraph text | the ordinary keystroke route |
| `typeInTable` | 40 insertions inside a GFM table cell | the unconditional full-reparse route (`SemanticEditEngine.swift:138`) |
| `typeAdjacentMarkup` | 40 insertions immediately after an emphasis close | the `contextualLiteralMutation` route |
| `applyCommands` | every `EditorCommand.allCases` once, both modes | semantic command cost |
| `toggleModes` | 40 mode toggles | `modeTransition`, selection and scroll restoration |
| `scrollDocument` | programmatic scroll top → bottom → top | layout cost and frame hitches |
| `undoRedoStorm` | 100 edits, 100 undos, 100 redos | history cost, ledger amplification |
| `openAndIdle` | open, settle, idle | the ARC-Q11 livelock guard |
| `soak` | 60 s of mixed scenarios | leaks, unbounded growth, sampler lifetime |

**Insertions are spaced at a human cadence (~120 ms), not run in a tight loop.** A tight loop never
lets reconciliation land between keystrokes, so it measures a different system than the one users
have. The interval is a parameter and is recorded in every evidence line.

The driver reaches the window-scoped `EditorCommandController` through `NSApp.windows`'s toolbar
delegate — the same handle `MarkdownAppDelegate.exerciseSmokeEdits` already uses for REQ-115, for the
same recorded reason (ARC-024 makes the command controller window-scoped, so the window is its owner).
No synthetic events, no accessibility API, no pixel or view-state reads; every assertion is made on
structured diagnostic records.

**One new judgement, recorded rather than left implicit.** `scrollDocument` sets
`NSClipView.bounds.origin` programmatically. `ENGINEERING.md` §12 already records the equivalent
judgement for reaching a controller through `NSApp.windows`; this increment extends that paragraph to
cover setting a scroll offset, with the reasoning stated: it is not a synthetic event and reads
nothing from the screen, and the assertions remain purely structural. If that reading is rejected,
`scrollDocument` is dropped and scroll-hitch coverage is lost — but the judgement is written down
either way, never assumed.

### 3. New `Scripts/benchmark.sh`

Runs the matrix (scenarios × corpora × sizes {10k, 100k, 1M}), reads the JSON Lines output, and emits
a Markdown report:

```text
| scenario | corpus | size | nativeInput p95 | mainActorLatency p95 | hitch ms/s | parses/edit | bytes read/edit | peak MB |
```

Writes `docs/research/performance-baseline.md` carrying evidence-only authority, first-researched and
last-verified dates, machine, OS build, architecture, build configuration, corpus digests, warmup and
sample counts, and the table. Committed, and re-recorded at the close of every performance increment,
so each future increment has a real before/after instead of a claim. Sets
`MARKDOWN_EDITOR_FRAME_OBSERVER=1` and `--fail-on-budget-exceeded`.

### 4. Rewrite the latency gates

`nativeInputCallbackP95Under8ms` and `modeToggleP95Under16ms` become parameterised over
`PerformanceCorpus.allCases`. Insertion points come from a helper
`insertionPoints(in: model, count:)` returning caret locations classified `.identityText`, so the
gate measures the ordinary route rather than accidentally landing on synthetic content.

Two new gates cover the routes that bypass `finishIdentityTransition`:
`tableCellKeystrokeP95Under8ms` and `adjacentMarkupKeystrokeP95Under8ms`.

`Scripts/check-performance-suite.sh` raises its bounded wall-clock allowance for the larger matrix and
asserts the executed case count is at least `PerformanceCorpus.allCases.count × gateCount`, so a
silently skipped corpus fails rather than passing quietly.

## Proof

- `corpusShapesProduceTheStructureTheyClaim` — parameterised over every case; parses the corpus and
  asserts `model.blocks.count >= minimumExpectedBlocks`. **Rehearsed failing** by degrading one unit
  to a plain paragraph. This is the gate that makes the corpus names honest.
- `corpusTruncationPreservesUnitBoundaries` — no corpus ends mid-fence or mid-table-row.
- `acceptedEditPerformsBoundedWork`, parameterised over every corpus: `documentParses <= 1`,
  `oracleValidations <= 1`, `storageFullReplacements == 0`, `fileBytesRead == 0`,
  `attributedCharactersWritten <= 4 × editLength + enclosingBlockLength`. This is COR-044's ARC-026
  gate and **it is expected to fail on landing**.
- `nativeInputCallbackP95Under8ms`, `tableCellKeystrokeP95Under8ms`,
  `adjacentMarkupKeystrokeP95Under8ms`, `modeToggleP95Under16ms` — all parameterised.
- `benchmarkDriverAssertsOnlyOnStructuredRecords` — source-conformance test proving the driver reads
  no view state and dispatches no synthetic event, in the shape of `noSecondaryMarkdownScannerRouteExists`.

**Expected outcome: several gates fail on landing.** That failure is the reproduction that opens the
performance programme, and it is pasted verbatim into the PR. Budgets are not tuned to make them
pass; REQ-090 moves to `Correction` with the failing numbers recorded, and `ROADMAP.md` carries an
active increment so a `Correction` row cannot contradict an inactive one (REQ-040's rule).

## Instrumentation and performance evidence

`docs/research/performance-baseline.md` is the artifact. Its first recording is the "before" column
for COR-46, COR-47, COR-48 and COR-49; each of those increments re-records it and quotes the delta.

## Failure / rollback

The corpora and gates are test-side and cannot affect shipping behaviour. `BenchmarkDriver` is
production code but is reachable only through `--benchmark`, which is absent from ordinary launches
and from `applicationShouldOpenUntitledFile`'s paths; a defect in it cannot reach a user. Revert is
one commit.

If `scrollDocument`'s judgement is rejected in review, drop that scenario and land the rest — the
plan explicitly does not depend on it.

## Deletion / conformance gate

- The old single-corpus gate bodies are **deleted**, not left beside the parameterised ones; no test
  may keep proving the 8 ms budget on `degenerateParagraph` alone.
- `Scripts/check-proof-results.sh` must show REQ-090 no longer claiming a passing proof.
- `CLAUDE.md` §4 gains the rule this increment exists to enforce: *"A proof's inputs are part of the
  proof. A requirement quantifying over a class of inputs must be proved by a structural enumeration
  of that class, not by one representative the author chose."*
