# COR-20 — Incremental TextKit application and honest latency

- **Status:** Approved; not implemented
- **Kind:** App-code correction; one worktree, branch, PR, and squash merge
- **Requirements:** REQ-090, REQ-091, REQ-103, REQ-109
- **Architecture:** Implements ARC-019, ARC-020, ARC-Q05, ARC-Q16; preserves ARC-003–007
- **Depends on:** COR-18, COR-19, INC-05

## Goal

Keep complete logical presentation snapshots while replacing the ordinary accepted-edit path's
full attributed-storage rebuild with one validated local patch. Measure the complete native input
callback, including TextKit application and selection restoration.

## Baseline defect to reproduce

Instrument `NSTextStorage` during one accepted insertion in the 100k corpus. Show that the current
adapter calls `setAttributedString` for the complete document after semantic planning, while the
`keystrokeTranslation` timer has already ended.

## Files

### Modify

- `Markdown Editor/PresentationTransition.swift`
- `Markdown Editor/PresentationSnapshot.swift`
- `Markdown Editor/MarkdownProjectionModel.swift`
- `Markdown Editor/EditorSession.swift`
- `Markdown Editor/WYSIWYGEditor.swift`
- `Markdown Editor/AttributedPresentation.swift`
- `Markdown Editor/AttributedPresentationBuilder.swift`
- `Markdown Editor/PerformanceSampler.swift`
- `Markdown Editor/EditorTrace.swift`
- `Markdown Editor/JSONLinesEditorTrace.swift`
- `Markdown Editor/DiagnosticRecord.swift`
- `Markdown EditorTests/AcceptedEditTransactionTests.swift`
- `Markdown EditorTests/PersistentEditorCharacterizationTests.swift`
- `Markdown EditorTests/DiagnosticLogTests.swift`
- `Markdown EditorTests/ReconciliationInvariantTests.swift`
- `Scripts/verify-smoke-log.py`
- smoke JSON fixtures if schema/metric names change
- `docs/ENGINEERING.md`
- `docs/REQUIREMENTS.md`
- `docs/ROADMAP.md`

### Add

- `Markdown Editor/PresentationPatch.swift`
- `Markdown Editor/TextStorageApplier.swift`
- `Markdown EditorTests/TextStorageApplierTests.swift`
- `Markdown EditorTests/PerformanceBoundaryTests.swift`

### Delete

- ordinary-edit calls to complete `AttributedPresentationBuilder` plus
  `textStorage.setAttributedString`
- `PerformanceSampler.Metric.keystrokeTranslation`
- ambiguous `reconciliation` metric if it combines parse/projection, images, and main application
- tests that time only `EditorSession.perform` while claiming native callback latency
- this plan after implementation

## `PresentationPatch` contract

A patch contains:

- from/to complete snapshot identities;
- projection replacement range in the currently applied snapshot;
- attributed replacement built from complete semantic blocks in the next snapshot;
- selection after;
- affected block identities;
- attachment lookup delta;
- explicit reason when the patch expands beyond the raw character replacement.

Construction fails rather than guesses. A failed patch before source commit refuses the edit. A
post-commit mismatch is an invariant violation and enters the existing safe recovery path; it
must never leave stale content editable.

Patch range expansion rules:

- inline identity edit: containing semantic inline/block scope as required for correct attributes;
- paragraph style change: complete affected paragraphs;
- list prefix/task/quote change: complete affected list/quote blocks;
- table edit: the one proven table cell plus required table style scope;
- attachment change: exact attachment block;
- cross-block or unprovable structural change: use the already-proven semantic command scope or
  refuse before mutation.

## Implementation

1. Add `PresentationPatch` validation against both complete snapshots.
2. Build attributed replacements only for the patch's complete semantic block scope.
3. Add `TextStorageApplier` as the sole mutation route for WYSIWYG attributed storage.
   - `applyInitialPresentation`: complete replacement, allowed at load.
   - `applyPatch`: one `beginEditing`/replacement/attribute transaction.
   - `applyRecoveryPresentation`: complete replacement with an explicit reason/trace.
   - `applyTypographyChange`: complete replacement after an explicit token identity change.
4. Update attachment lookup atomically with storage application.
5. Apply selection after storage mutation but before returning from the native callback.
6. Move timing start to the native delegate boundary before classification.
7. Stop timing only after source commit, session snapshot advance, attributed patch, attachment
   update, and selection restoration complete.
8. Record `.nativeInputCallback`; do not emit per-keystroke diagnostic records. Feed only the
   sampler.
9. Split reconciliation:
   - detached `.parseProjection`;
   - detached `.imageResolution`;
   - main `.authoritativeApplication`.
10. Keep mode timing around the complete real mode transition, not initial view construction.
11. Update Release evidence and smoke verifier metric expectations.

## Automated proof

- A spy `NSTextStorage` records mutation APIs and ranges.
- One ordinary insertion:
  - one bounded range edit;
  - zero complete replacements;
  - complete next snapshot and storage strings agree;
  - selection and attachment lookup agree.
- Initial load and explicit typography change each permit exactly one complete replacement.
- One hundred immediate insertions remain accepted, ordered, and visible exactly once.
- Bold/italic/link/code/list/task/quote/table/image-description edits patch correct semantic scope.
- IME marked text receives no programmatic replacement until composition completion.
- Undo/redo and mode switching preserve exact source selection.
- Injected failures before commit change neither source nor storage.
- A boundary spy proves `.nativeInputCallback` ends after storage and selection operations.
- Release performance:
  - 10 warmups and at least 40 recorded samples;
  - 100k UTF-16 approved corpus;
  - p95 complete native callback <8 ms;
  - zero refused accepted-input fixtures;
  - evidence prints actual configuration, OS, architecture, corpus length/hash, median, p95,
    sample count, and failures.

Also run a non-gating 1M UTF-16 characterization and report it without inventing a threshold.

## Instrumentation

Aggregate only. Metric payload key is `metric`, not `mode`. A recovery full replacement records a
typed reason because it is architecturally exceptional; ordinary patches are not recorded per
keystroke.

## Failure and rollback

- Never fall back from a failed ordinary patch to a silent full replacement inside the input
  callback.
- If patch construction is unprovable before commit, refuse.
- If an impossible post-commit application mismatch occurs, make WYSIWYG unavailable, record a
  fault, rebuild authoritatively, and preserve canonical source. Add a test that discriminates
  this route.
- Do not change the 8 ms threshold without separate evidence and approval.

## Conformance and completion gates

- A structural test or API restriction proves ordinary edit code cannot call the full replacement
  route.
- `rg "keystrokeTranslation"` returns no production or current-doc result.
- Every performance gate executes nonzero samples in Release.
- ARC-Q05 and ARC-Q16 pass.
- Full Debug/Release tests, gates, smoke, screenshot review, separate-agent review, PR triage, and
  stale-work cleanup pass.
- Reconcile REQ-090/103/109 only from evidence; delete this plan.
