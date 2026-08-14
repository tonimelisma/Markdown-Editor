# COR-70 — Editor transaction kernel

- **Status:** Approved; not implemented
- **Delivers:** none (refactor; no requirement changes status)
Completion-Proofs: acceptedEditAdvancesSourcePresentationSelectionAndUndoOnce; refusedEditMutatesNothing; everyInputRouteUsesEditorTransactionKernel
Architecture impact: none; makes ARC-001, ARC-004, ARC-005, ARC-007, ARC-010, and ARC-013 executable through one seam
Blockers: COR-68
Executor: A junior developer may implement this plan in order. Obtain senior review of the kernel types before migrating routes; do not invent a compatibility route when a current entry point does not fit.

## Outcome

Create one pure transaction seam: typed editor input plus an immutable state snapshot produces
either one accepted transaction or one typed refusal. AppKit adapters capture input and apply an
accepted result; they do not parse, plan, mutate the document, repair selection, or manage undo.

## Files and ownership

- Add `EditorTransactionKernel.swift`: `EditorInput`, `EditorStateSnapshot`,
  `AcceptedEditorTransaction`, `EditorRefusal`, and `EditorTransactionKernel.reduce`.
- Add focused helpers `SelectionPlanner.swift`, `UndoTransaction.swift`, and
  `PresentationTransitionService.swift` only where the extracted responsibility needs its own type.
- Modify `MarkdownDocument.commitSourceMutation`, `EditorSession`, `WYSIWYGPlanningDomain`,
  `SemanticEditEngine`, `EditorCommandController`, and both editor coordinators to use the kernel.
- Delete adapter-local source mutation, undo grouping, selection repair, and duplicate refusal logic.

## Implementation

1. Characterize every current input route in a closed matrix: source replacement; literal WYSIWYG
   replacement; marked-text update/commit/cancel; semantic command; checkbox; image-reference
   insertion; undo/redo; mode change; reconciliation.
2. Define immutable input/state/result values with explicit source revision, location generation,
   projection revision, coordinate space, origin, selection/affinity, and `IntentID`.
3. Move pure validation behind `reduce`; the session performs semantic planning with the originating
   intent and passes the immutable `plannedOutcome` into the kernel. The kernel performs no
   AppKit, I/O, clock, diagnostics, worker-queue, or mutable document work.
4. Add one main-actor commit method that validates identity, registers undo, updates canonical source
   and session presentation atomically, applies the native patch, and records the result.
5. Migrate one route at a time using the matrix. Delete its displaced path in the same commit; never
   keep a compatibility adapter.
6. Split `WYSIWYGEditor` and `SourceEditor` coordinators into construction, input capture, result
   application, interaction, and layout objects after all mutation routes use the kernel.

## Proof and failure behavior

- Table-driven tests enumerate every `EditorInput` case and accepted/refused result class.
- For accepted inputs, source/presentation/selection/undo/intent advance exactly once together;
  a tampered planned outcome is refused when its source content, selection identity, or
  presentation transition does not match the captured state.
- For stale, invalid, mixed-domain, marked-text, and unprovable inputs, every mutable spy remains
  unchanged and one typed refusal is recorded.
- Adapter integration tests prove each delegate/controller route calls the kernel once and applies
  only its returned transaction (`realSourceAdapterRouteUsesKernelCommitExactlyOnce` plus the
  existing WYSIWYG, checkbox, paste, marked-text, and image route proofs). Re-entrancy and
  programmatic updates never enter as user input.

## Deletion/conformance gate

A structural test enumerates every production input entry point and its sole kernel call. `rg` and
the compiler prove no adapter calls `commitSourceMutation`, parser/projector, undo manager, or
selection-repair helper directly. The three completion proofs pass in the closing bundle.
