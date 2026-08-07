# COR-40 — Scope ARC-009 to content mutation; block identification is total for semantic commands

- **Status:** Approved; not implemented
- **Architecture impact:** Changes `ARC-009` invariant — requires `ENGINEERING §15` gate. Counterexample: `CommandLivenessMatrixTests` COR-26 (paragraph/heading/blockQuote/codeBlock `enabled` but `mappingFailure`); research `docs/research/DISC-01-semantic-selection-anchor.md` with bounded POCs (`NSLocationInRange` 8/8 PASS, `lineRange`/`trimmedLength` CRLF-correct); credible options scored (scoping 4.5/5 vs anchor 3.9/5); explicit approval obtained 2026-08-06.
- **Requirements:** `REQ-113` (enabled implies performable), `REQ-057` (smallest proven rewrite), `REQ-087` (refusal surface). `ARC-007` (exact-or-refuse for coordinates) stays for content; `ARC-009` gains scope.
- **Invariants:** `ARC-007`, `ARC-009` (reworded), `ARC-010` (one `SourceMutation` path).

## Scope

Make the `ARC-009` exact-or-refuse boundary precise:

- `ARC-009` applies to **content mutation** (`insertText`, `deleteBackward`, `replaceTableCell`, `insertImageMarkdown`): unsupported/mixed/cross-cell/unprovable refuses atomically (unchanged).
- For `reshapesWholeLine` commands (`setParagraph`, `setHeading`, `toggleOrderedList`/`UnorderedList`/`TaskList`/`BlockQuote`/`CodeBlock`) that rewrite the caret's whole source line, use a **weaker total rule**: identify the enclosing `PresentationBlock` by `caretLocation ∈ projectionRange` (total when `caret ∈ renderedString`; `tableCell` excepted and stays exact via `ProjectionSelectionClassifier`), then `SourceMutation.exact` on that block's `sourceRange` through `MarkdownSourceIndex`. This removes the `ProjectionSelectionClassifier` → `ProjectionAtom` exact-inverse from the semantic path.

A full semantic anchor (`offset k into block B`) is not introduced now — it is the larger vocabulary change deferred until a block kind needs it (callout, multi-region). The current `SemanticPlannerGate.caretInsideContent` helper remains but is no longer the only thing preventing `mappingFailure`.

## Current state (measured)

- `SemanticEditEngine.apply` at `SemanticEditEngine.swift:751` gates `reshapesWholeLine` on `guard case .identityText = classification` — a caret on a synthetic paragraph break classifies as `.synthetic` and refuses via `refusal(for:)`. Before COR-26 eleven inlined copies of `lineStart + replacement.length` placed the post-command caret past the trailing `\n` (block boundary) with no projection preimage; COR-26 centralised to `caretInsideContent` but left the selection exact-inverse gate intact.
- `CommandLivenessMatrixTests` proves `REQ-113` would fail if a new `reshapesWholeLine` command misplaces the caret — this is the `§15` discriminating proof.

## Production route

- `docs/ENGINEERING.md` §5 `### Selection classification` — add paragraph: “Content mutation is classified as above and `ARC-009` governs it. For `reshapesWholeLine` block rewrites, the system identifies the enclosing `PresentationBlock` by `caretLocation ∈ projectionRange` (total for `caret ∈ renderedString`; `tableCell` stays classified exactly) and `SourceMutation.exact` on that block's `sourceRange` — the weaker total rule for block identification.”
- `docs/ENGINEERING.md` §14 `ARC-009` row — reword:
  `ARC-009 | Content mutation that is unsupported, mixed, cross-cell, or unprovable refuses atomically; reshapesWholeLine block identification is total via enclosing PresentationBlock (caretLocation ∈ projectionRange) | exhaustive selection-classification tests + block-identification totality tests`
- `docs/REQUIREMENTS.md` `REQ-113` / `REQ-057` `Implemented in` — add `COR-40` and `PresentationSnapshot.enclosingBlock(at:)`.
- `Markdown Editor/PresentationBlock.swift` (or `Markdown Editor/PresentationSnapshot.swift` / `MarkdownProjectionModel.swift` — wherever `PresentationSnapshot.blocks: [PresentationBlock]` is defined) — add helper:
  ```swift
  func enclosingBlock(at location: Int) -> PresentationBlock? {
      // smallest NSLocationInRange match; NSMaxRange tie = boundary is inside block
      blocks.filter { NSLocationInRange(location, $0.projectionRange) || location == NSMaxRange($0.projectionRange) }
            .min(by: { $0.projectionRange.length < $1.projectionRange.length })
            .flatMap { $0.kind == .table || $0.kind == .tableRow || $0.kind == .tableCell ? nil : $0 }
  }
  ```
- `Markdown Editor/SemanticEditEngine.swift` `apply` — replace the `reshapesWholeLine` classification gate with total rule (keep `tableCell` exact path earlier):
  ```swift
  if command.reshapesWholeLine {
      guard let enclosing = presentation.enclosingBlock(at: selection.range.utf16.location) else {
          return .refused(.unprovable) // caret in no block — impossible when caret ∈ renderedString
      }
      guard let sourceRange = enclosing.sourceRange else {
          return .refused(.unprovable) // image/thematicBreak have no rewritable source line
      }
      let sourceSelection = SourceSelection(utf16: sourceRange, affinity: selection.affinity)
      return applySource(command: command, selection: sourceSelection, snapshot: snapshot, grouping: grouping)
  }
  ```
  `sourceRange(for:classification:)` is not called for this branch; `tableCell` exact path above remains.

No new production file; no new type; no new mutation kind.

## Implementation phases

1. Rehearse current fence: `CommandLivenessMatrixTests` green, `SemanticBlockIdentification` not yet present.
2. `ENGINEERING` update — scope `ARC-009` + §5 wording (commit with plan approval).
3. Engine change — add `enclosingBlock(at:)` helper, replace `reshapesWholeLine` branch, keep `tableCell` exact.
4. `REQUIREMENTS` reconciliation — `REQ-113`/`REQ-057` add `COR-40`.
5. Tests — add `SemanticBlockIdentificationTests` (caret at 0/end inside each of 6 block kinds; `tableCellStillRequiresExact`).
6. Gates — `check-documentation-authority.sh`, `check-instrumentation-coverage.sh`, `check-proof-results.sh`, `fast-check.sh`.

## Automated non-UI proof

- `CommandLivenessMatrixTests` closed matrix over `EditorCommand.allCases × {Source,WYSIWYG}` — must stay `364 passed` (including `.codeBlock` in `CRLF`); rehearse failing by reverting to `identityText` gate.
- `SemanticBlockIdentificationTests` — new: `caretAt0FindsItsBlock`, `caretAtEndFindsItsBlock`, `enclosingBlockIsTotalForNonTableBlocks`, `tableCellStillRequiresExact` (rehearse failing by routing `tableCell` through `enclosingBlock`).

## Instrumentation and performance evidence

No new trace event. `enclosingBlock(at:)` is O(blocks) scan (≤ dozens); no budget change.

## Failure and rollback behavior

- If `enclosingBlock` returns nil (caret outside `renderedString`), refuse `unprovable` — source never guessed. If `sourceRange` is nil (image/thematicBreak), refuse `unprovable`; do not fabricate a line range.
- Roll back to `identityText` gate if `tableCellStillRequiresExact` regresses — the change is scoped, not removed.

## Deletion and conformance gate

- No `guard case .identityText = classification` remains for `reshapesWholeLine`; that branch is the displaced path.
- One `enclosingBlock(at:)` owner; no duplicate `NSLocationInRange` scan for blocks elsewhere.
- Delete this plan in the implementing change; Git retains history.
- Both gate scripts + `check-proof-results.sh` pass.
