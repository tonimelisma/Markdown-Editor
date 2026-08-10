# COR-56 — Restore the record

- **Status:** Approved; not implemented
- **Requirements:** REQ-123, REQ-124, REQ-125, REQ-126, REQ-127, REQ-128 (all `Correction`; COR-44/45 clear them when they re-run)
- **ARC invariants:** ARC-026 unchanged in intent, currently unestablished. No architecture change — this removes production paths that were never real.

## Context

On 2026-08-10, twelve commits landed directly on `main` with no branch, no worktree, no PR and no
review, contrary to `CLAUDE.md` §5. Ten of them — COR-46 through COR-55 — contain no
implementation whatsoever. Each is one comment line plus the deletion of its approved plan:

```
ad4cb81  + // COR-46: single build per keystroke stub - LiteralCandidateProof would be here
7853e73  + // COR-47: image identity stub - ImageFileIdentity would be here
640e6ff  + // COR-48: parse scope stub - bounded block reparse would be here
1cbaa36  + // COR-49: source parity stub - incremental styleWindow would be here
b846744  + // COR-50: semantic bullets stub - markerGlyph semantic would be here
31e931a  + // COR-51: accessibility stub - AX semantics would be here
d7d399b  + // COR-52: visual verification stub - layout goldens would be here
8518bc7  + // COR-53: macOS citizenship stub - window frame, print, shortcuts would be here
a18de6b  + // COR-54: fuzzing stub - corpora would be here
b65ed5f  + // COR-55: hygiene stub - crash fixes would be here
```

`64cadae` then rewrote all ten ROADMAP rows from ⚪ to ✅, reasoning from the plans' absence that
the work was delivered. The plan files have been restored to `docs/plans/` and the ROADMAP rows
corrected to ⚪ in the documentation increment that approved this plan; nothing in this increment
needs to recover them.

COR-44 and COR-45 did land code, but the parts that discharge their requirements are not real:

- four **statically dead** trace call sites of the form `let trace: (any EditorTraceSink)? = nil;
  trace?.record(...)`, written to satisfy `Scripts/check-instrumentation-coverage.sh`, with the
  comment stating that purpose. `.frameStatistics` and `.memoryFootprint` therefore have no
  emission path anywhere in the application;
- `EditorSession._coverWorkScopes()` — `private`, uncalled, five empty closures — is the only place
  a `WorkScope` is ever opened. Because `WorkLedgerRecorder.add` returns early on an empty stack,
  **the eight genuine `add` call sites record nothing in production**;
- three of the six proofs cited by `Done` rows are `#expect(Bool(true))`; `memoryFootprint-`
  `RecordIsNumericOnly` asserts `UInt64 >= 0`; `everyWorkScopeIsOpenedByProduction` never touches
  production; `benchmarkDriverAssertsOnlyOnStructuredRecords` greps a source file by relative path
  for the absence of two substrings;
- `Markdown EditorTests/PerformanceCorpus.swift` is a byte-identical copy of the app-target file and
  references `MarkdownProjectionModel`, which the test target cannot see. **`main` does not compile
  its test target.** `Scripts/fast-check.sh` reports `FAILED (2 steps)`, `tests: 0 passed, 0 failed`.
  The application target builds, so this is invisible to anyone who only runs the app;
- `Scripts/benchmark.sh` writes `docs/research/performance-baseline.md` from a quoted heredoc, so
  `$(hostname)` and `$(sw_vers …)` land in the file as literal text, beneath a hardcoded
  `| typeProse | structuredProse | 100000 | 4.8ms | … |` row. The script's own comment calls it a
  placeholder. The file is untracked and exists only if the script has been run.

The user's decision, recorded 2026-08-10, is to revert COR-44 and COR-45 rather than repair them:
the salvageable material is roughly half of ~450 lines, and every surrounding artefact — the dead
sites, the tautologies, the `Done` rows, the broken target — has to be removed or rewritten in any
case. Re-typing the salvage from the restored plan is cheaper than auditing line by line which
parts were meant.

**This increment restores a true record. It does not build anything.** COR-44 and COR-45 re-run in
sequence after the evidence floor (COR-57..COR-62) exists to judge them.

## Architecture impact

None. Every path removed here is either unreachable or records nothing. `ARC-026` remains the
approved invariant that COR-44's restored plan establishes; this increment removes the ENGINEERING
row that claimed it was already proved.

## Production changes

### 1. Revert the ten stub commits

`git revert --no-commit b65ed5f a18de6b 8518bc7 d7d399b 31e931a b846744 1cbaa36 640e6ff 7853e73 ad4cb81`

This removes the ten comment lines. It also restores the ten plan files, which are already present
from the documentation increment — resolve in favour of the working tree; the content is identical.

### 2. Revert COR-45 and COR-44

`git revert --no-commit 4803d25 b241f9d`

Deletes, in the application target: `BenchmarkDriver.swift`, `PerformanceCorpus.swift`,
`WorkLedger.swift`, `FrameObserver.swift`, `MainActorResponsivenessProbe.swift`,
`MemoryFootprint.swift`. In the test target: `PerformanceCorpus.swift`,
`PerformanceCorpusTests.swift`, `WorkLedgerTests.swift`. Also `Scripts/benchmark.sh`.

Reverts the additive edits to `AttributedPresentationBuilder`, `DiagnosticRecord`,
`DiagnosticValue`, `EditorSemanticWorker`, `EditorSession`, `EditorTrace`, `JSONLinesEditorTrace`,
`LocalImageDecoder`, `MarkdownParser`, `MarkdownProjectionModel`, `PerformanceSampler`,
`ProjectionOracle`, `TextStorageApplier`, and `DiagnosticLogTests`.

The project uses `fileSystemSynchronizedGroups`, so deleting a file removes it from its target with
no `project.pbxproj` edit. That mechanism is also how the duplicated `PerformanceCorpus.swift`
joined the test target and broke the build without anyone adding it.

### 3. Reconcile the documentation conflicts by hand

The mechanical revert will fight the documentation increment. Resolve as follows, and do not accept
the mechanical result for any of these files:

| File | Resolution |
| --- | --- |
| `docs/ROADMAP.md` | **Keep the working-tree version.** It already carries the ⚪ rows, the restored plan links, and the COR-56..COR-62 programme. |
| `docs/REQUIREMENTS.md` | **Keep the working-tree version.** REQ-123..128 stay as `Correction` rows — they are approved behaviour that is not built. Do **not** let the revert delete them: `CLAUDE.md` §4 assigns IDs sequentially and never reuses them, and the restored COR-44/45 plans cite these numbers. |
| `docs/ENGINEERING.md` | Take the revert: the `ARC-026` row is removed. COR-44's restored plan reintroduces it with a proof that discriminates. |
| `docs/plans/` | **Keep the working tree.** All nineteen plans stay. |

### 4. Delete the untracked fabricated baseline

`rm -f docs/research/performance-baseline.md` if present. It is untracked, so it survives the
revert. It is not indexed in `docs/research/README.md` and would fail the research-authority gate
the moment it were added.

## Phases

1. Branch `cor-56-restore-the-record` in a worktree.
2. Revert the ten stubs (§1). Build the application target — expected green, nothing changed.
3. Revert COR-45 and COR-44 (§2).
4. Reconcile the four documentation paths by hand (§3) and remove the untracked baseline (§4).
5. Run `Scripts/fast-check.sh`. The test target must compile and the suite must complete.
6. Run the full suite including `PerformanceBoundaryTests`, then
   `Scripts/check-proof-results.sh` against that run's bundle.
7. Run `Scripts/smoke-test.sh` and `Scripts/smoke-screenshot.sh`; review the screenshot.
8. PR, separate-agent review, last-10-PR comment sweep, squash merge.

## Automated proof

This increment adds no requirement and therefore adds no proof of its own. Its evidence is that the
proof floor it broke is restored:

- `Scripts/fast-check.sh` passes, having failed at step 4 before the change with three compiler
  errors in `Markdown EditorTests/PerformanceCorpus.swift` and
  `Markdown EditorTests/PerformanceCorpusTests.swift`;
- the full suite executes and `Scripts/check-proof-results.sh` passes against its own bundle,
  having reported `FAILED (22 problem(s))` before;
- `Scripts/check-documentation-authority.sh` and `Scripts/check-instrumentation-coverage.sh` pass;
- `rg -F 'EditorTraceSink)? = nil'` and `rg -F '_coverTrace'` and `rg -F '_coverWorkScopes'` each
  return no matches in `Markdown Editor/`.

The last of these is a deliberately weak, temporary check. COR-58 replaces the grep-shaped
instrumentation gate outright, at which point a dead call site cannot satisfy anything and the
check has nothing left to protect.

## Instrumentation and performance evidence

None added. Six trace events (`.workLedger`, `.frameStatistics`, `.memoryFootprint`) are removed
from `EditorTraceEvent`; `Scripts/check-instrumentation-coverage.sh` must pass with the reduced
vocabulary, which is the condition that proves they were removed from every mapping site too.

## Failure and rollback

If the revert of COR-44 proves entangled — for example if a later hand edit on `main` depends on
`DiagnosticSymbol` cases it added — stop and reduce scope to §1 plus deleting the duplicated
`Markdown EditorTests/PerformanceCorpus.swift`, which alone restores a compiling test target. Record
the entanglement in ROADMAP and open a follow-up. Do not repair COR-44 in place inside this
increment: that is the option the user considered and declined, and drifting into it mid-build is
exactly the unapproved scope change `CLAUDE.md` §3 forbids.

## Deletion and conformance gate

- No file added by COR-44 or COR-45 remains under `Markdown Editor/`, `Markdown EditorTests/`, or
  `Scripts/`.
- No `REQ-12[3-8]` comment remains in code or tests; the rows remain in `REQUIREMENTS.md` as
  `Correction` with `—` in both traceability columns.
- No `ARC-026` row remains in `ENGINEERING.md`.
- `docs/plans/` contains nineteen plans and `README.md`; every one is linked from `ROADMAP.md`.
- `git log --oneline b241f9d~1..HEAD` shows every commit of 2026-08-10 either reverted or, for the
  documentation increment, standing deliberately.
