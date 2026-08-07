# COR-43 — Split SemanticEditEngine by planning domain

- **Status:** Approved; not implemented
- **Requirements:** REQ-057/058/078-080/087/113 (smallest-unit rewrite, commands, table cell, liveness) — no new REQ
- **ARC invariants:** ARC-005/007/008/009 (synchronous edit, exact conversion, literal vs formatting, refusal) unchanged; split only

## Context

`SemanticEditEngine` (`Markdown Editor/SemanticEditEngine.swift:62`, 1291 lines) owns routing, literal encoding, table-cell mapping, and 12 `plan*` helpers for both `Source` and `WYSIWYG` domains. Adding one command (e.g. table creation) adds a 13th branch to the same `switch`. `SemanticEditPlanners.swift` (624 lines) already holds per-command rewrites, but routing and `WYSIWYG` vs `Source` planning remain in one enum. This is the second god object after `EditorSession` (COR-42). Split now so next product increment is reviewable.

## Production changes

### 1. New `WYSIWYGPlanningDomain` (new file `Markdown Editor/WYSIWYGPlanningDomain.swift`)

- `enum WYSIWYGPlanningDomain` — owns `applyWYSIWYG`, `applyTableCellTyping`, `tablePresentationEdit`, `literalCandidatePreservesPresentation`, `sameRunSemantics` etc that are WYSIWYG-only.
- Takes `snapshot: SourceSnapshot`, `presentation: PresentationSnapshot`, `tree: MarkdownTree?` as params, not as stored state.
- Calls existing `SemanticEditPlanners` and `SemanticPlannerGate` helpers; no new logic.

### 2. New `SourcePlanningDomain` (new file `Markdown Editor/SourcePlanningDomain.swift`)

- `enum SourcePlanningDomain` — owns `applySource` path for `EditorSelection.source`.
- Currently thin; exists so `SemanticEditEngine.plan` dispatches to one of two domains, not to 15 `case` branches.

### 3. `SemanticEditEngine.swift` — router only

- Becomes ~300-line router: `plan` dispatches to domain based on `request.selection`, `apply` dispatches to `WYSIWYGPlanningDomain` vs `SourcePlanningDomain`, common `mapRefusal`/`container`/`defaultGrouping` remain.
- No `try!`, no new `force: Bool`, no new mutex mirror.

## Proof

- `Scripts/fast-check.sh` 368 passed / 0 failed
- Full `xcodebuild test` — `CommandLivenessMatrixTests` (closed matrix over `EditorCommand.allCases` x both modes), `SemanticBlockIdentificationTests`, `CRLFCodeBlockTests`, `AcceptedEditTransactionTests` all green
- `Scripts/check-documentation-authority.sh` PASS
- `Scripts/check-instrumentation-coverage.sh` PASS
- `Scripts/check-proof-results.sh` PASS

## Failure / rollback

Pure split with identical observable behavior. If any liveness or planner test fails, revert the single split commit; no file format or diagnostic change.

## Deletion / conformance gate

- No `applyWYSIWYG` / `applyTableCellTyping` / `tablePresentationEdit` remains inside `SemanticEditEngine.swift` — grep must be empty for those names inside `SemanticEditEngine`.
- `WYSIWYGPlanningDomain` is single owner for WYSIWYG planning; `SourcePlanningDomain` for Source.
- One squashed commit for COR-43; plan deleted in same commit.
