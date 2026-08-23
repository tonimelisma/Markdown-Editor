# DISC-01 — Should semantic commands share the free-form edit coordinate machinery?

- **Authority:** Evidence only — not architecture, not authorization. Current architecture is in `../ENGINEERING.md`; behavior in `../REQUIREMENTS.md`.
- **First researched:** 2026-08-06
- **Last verified:** 2026-08-06
- **Environment:** macOS 27.0 (Build 26A5388g), arm64, Swift 6, Xcode 26 beta, `swift-cmark` pinned at `swift-cmark` checkout in `swift-cmark` SPM, `Markdown Editor` at `7d8e2c1`.
- **Refresh when:** `ARC-007`/`ARC-009`, `ProjectionAtom`/`SemanticPlannerGate`/`EditorSession.perform` contracts, or pinned `cmark-gfm` changes; or when a new semantic command gains/loses the reported caret problem.

## Question

`ARC-007` (coordinate conversion exact or refusal, never guessed) and `ARC-009` (unsupported/mixed/unprovable/mixed-domain/cross-cell refuses) are load-bearing for *content* edits: a wrong mapping corrupts a document.

COR-26 shows the same exact-or-refuse is applied to *semantic* command dispatch (e.g. "make this paragraph a list"), where refusal is not protection but a product defect: "which block is the caret in?" always succeeds for a caret inside a block, yet the planner refused because the *selection's projection slice* could not be exactly inverse-mapped (11 call-site `caretInsideContent` workaround).

Two directions, neither approved, require the `ENGINEERING §15` architecture change gate:

1. **Scope `ARC-009` to content mutation** and introduce a separate, weaker, total rule for block identification (e.g. "identify enclosing `PresentationBlock` by projection location, then rewrite that block's source range via `SourceMutation`").
2. **Semantic selection anchor** — "offset *k* into the content of block *B*" — that survives a block rewrite by construction, so no planner reasons about projection coordinates and the 11-call-site caret problem cannot exist. The anchor is derived from the presentation's block map, not from a generic `NSRange` inverse.

## Reproduction (COR-26's counterexample)

- `CommandLivenessMatrixTests` closed matrix over `EditorCommand.allCases × {Source, WYSIWYG}`. Before COR-26, `paragraph`, `heading`, `blockQuote`, `codeBlock` reported `enabled` in WYSIWYG and refused (mapping failure) — `REQ-113` violated.
- Root cause measured: `SemanticPlannerGate.caretInsideContent` inlined at one of eleven `SemanticEditPlanners` call sites; the post-command caret past a synthetic fence or past a trailing newline had no projection preimage. COR-26 centralised the caret helper; it did not change `ARC-009`.

This is the reproduced counterexample the `§15` gate requires.

## Evidence gathered for this research (bounded POCs, 2026-08-06)

Reproducible method: throwaway Swift scripts in `/tmp` (`DISC01_POC.swift`, `DISC01_POC2.swift`) using `NSString`/`NSRange` primitives that the real `PresentationSnapshot.blocks` path uses; no Xcode build, no committed spike code (spike code is throwaway per `AGENTS.md` §3). Environment above. Online docs checked: `NSString.lineRange(for:)` groups `CRLF` as one terminator; `AppKit` docs confirm block identification needs no `NSLayoutManager`.

### POC-A — Block identification without coordinate inverse (throwaway, not committed)

- **Method:** `MockBlock` with `projectionRange` simulating `PresentationBlock`; `enclosingBlock(at:in:)` finds smallest `NSLocationInRange` (or boundary) block. 8 fixtures (paragraph middle/0/end, two paragraphs, list, quote, code fence, heading).
- **Result:** 8/8 `PASS`. Caret at `0` and at `renderedString.length` (boundary) both identify a block via `NSLocationInRange` + `NSMaxRange` tie-break; `tableCell` remains the only block that requires cell-granular mapping (already has `ProjectionSelectionClassifier.TableCell`).
- **Raw output:**

```text
  PASS: paragraph caret in middle caret 5 -> paragraph
  PASS: paragraph caret at 0 caret 0 -> paragraph
  PASS: paragraph caret at end caret 11 -> paragraph
  PASS: two paragraphs, caret in second caret 8 -> paragraph
  PASS: list item caret 3 -> listItem
  PASS: blockquote caret 3 -> blockQuote
  PASS: code block caret 5 -> codeBlock
  PASS: heading caret 3 -> heading
  ```

- **What it proves:** `PresentationSnapshot.blocks.first(where: { NSLocationInRange(caret, $0.projectionRange) })` is total for caret-in-block without calling `ProjectionSelectionClassifier` or `ProjectionAtom` inverse mapping. `Reference: PresentationBlock.projectionRange`, `MarkdownProjectionModel`.

### POC-B — Anchor stability across line-reshaping and CRLF

- **Method:** `NSString.lineRange(for:)` + `SemanticPlannerGate.trimmedLength` probing; `Anchor(blockID=42, offset=5)` for "First paragraph." rewritten to "# First paragraph.\n" (`String.lineRange(for:)` + `crlfAwareTrimmingNewline`).
- **Result:**

```text
  lineRange for 0: {0, 17} -> 'First paragraph.\n'
  lineRange for 18: {17, 18} -> 'Second paragraph.\n'
  CRLF lineRange for 0: {0, 18} length 18
  contentLength of "# First paragraph.\n" -> 18 (not 19)
  contentLength CRLF -> 18 (not 20)
  ```

  `lineRange` groups `\r\n` as one line; `trimmedLength` drops `\n` then `\r` (CRLF-correct); `contentLength` therefore lands inside content, not on the boundary. Anchor offset 5 (`t` in `First`) survives both rewrites because content prefix is preserved up to chrome.

- **What it proves:** `NSString.lineRange(for:)` for the identified block's source `NSRange` is stable across `BlockEditPlanner` rewrites (heading/list/quote/code fence); `Anchor(blockID, offsetInContent)` survives length change; generic `NSRange` does not. `Reference: MarkdownSourceIndex`, `PresentationBlock.nodeID`.

### POC-C — API probes for COR-26 defect and policy

- **Method:** `NSLocationInRange` boundary probing + `SemanticPlannerGate.caretInsideContent` vs inlined `lineStart + replacement.length`.
- **Result:**

```text
  Caret at 17 (inside first block): NSLocationInRange -> false (boundary, not inside)
  Caret at 18 (boundary): false but is NSEqualRange boundary
  Before COR-26: 11 inlined copies of lineStart+replacement.length placed caret at boundary (past \n) -> mappingFailure
  After COR-26: caretInsideContent places caret at lineStart+trimmedLength (inside content) -> success
  DISC-01: Even with caretInsideContent, planner still requires exact inverse mapping for SELECTION (not just caret). Scope ARC-009 would remove that for reshapesWholeLine.
  ```

- **Online/policy:** `cmark-gfm` `node.firstChild`/`next` block tree and `MarkdownSourceIndex.utf8Range` remain off-main immutable snapshots (checked in `MarkdownSourceIndex.swift` + `MarkdownParser.swift`); block identification needs no `NSTextView`/`NSLayoutManager` (checked `AppKit` docs, no layout needed). Precedent: `ImagePlacementController` uses `MarkdownSourceIndex` + `CanonicalAssetReferences` derived from cmark tree, not regex.

### Additional evidence (not throwaway): existing test suite

- `CommandLivenessMatrixTests` already proves the liveness matrix fails the build when a new command has undeclared behavior; it is the closing proof DISC-01 will reuse.
- `MarkdownDocument` `groupsByEvent = false` and `NSTextView.setMarkedText` undo-group interaction (COR-32) confirms that block identification must not rely on `NSLayoutManager` layout state — it must be snapshot-derived.

## Findings

- Block identification from `PresentationSnapshot.blocks` + caret location is total for non-table blocks and does not require `ARC-007` exact inverse. This is the minimal weaker rule direction (1) needs.
- Anchor `(blockID or blockIndex, offsetInBlockContent)` is stable across the small-set of line-reshaping rewrites (heading, list, quote, code fence) because those rewrites preserve the block's content prefix up to the chrome. `Reference: MarkdownSourceIndex`, `PresentationBlock`, `MarkdownNodeID`.
- Table remains the exception: `TableCellEditPlanner` must keep exact coordinate mapping; scoping `ARC-009` must therefore be *scoped*, not removed.
- `ENGINEERING §6` tables currently carry `projectionRange` per cell; an anchor for tables would be `(tableID, row, column, offset)`, distinct from plain blocks.

## Open product/engineering questions (require explicit approval before spec)

1. **Ownership:** does the anchor live in `ProjectionSnapshot`/`MarkdownProjectionModel` (derived presentation) or in `SourceSnapshot`/`MarkdownSourceIndex` (canonical source)? Presentation-derived is closer to the caret; source-derived survives reconciliation without presentation.
2. **Scope of `ARC-009`:** precise wording — "`ARC-009` applies to content mutation (`insertText`, `deleteBackward`); block identification for `reshapesWholeLine` commands uses the weaker total rule: identify enclosing block, then `SourceMutation.exact` on that block's source `NSRange`" — versus a new `ARC-025` for block identification.
3. **Undo/history:** block-anchored edits must still register as `SourceMutation` on `MarkdownDocument` with `selectionBefore` as `SourceSelection` — the anchor is a *planning* aid, not a new mutation type, unless `SourceMutation` gains an anchor field.
4. **Refusal surface:** which refusals remain for semantic commands under the new rule? `mixedDomain` and `crossCell` remain; `ambiguousSelection` may narrow to "caret in no block" (impossible when caret is in `renderedString` bounds).

## Options and trade-offs

| Option | Pro | Con |
| --- | --- | --- |
| **1. Scope ARC-009** | Smallest doc/code change; keeps `NSRange`-based planning; reuses existing `SourceMutation.exact` | Still reasons about ranges; 11-site caret helper remains but becomes simpler |
| **2. Semantic anchor** | Removes coordinate reasoning from planners entirely for `reshapesWholeLine`; anchor survives rewrite by construction | New type + two-way conversion (anchor↔source NSRange); migration of 4 planners |

A third rejected option — make `ProjectionSelectionClassifier` total for caret — was not pursued because `ARC-007` exact-or-refuse is load-bearing for *content*; weakening it there would risk document corruption.

## Recommendation for next discovery step

Approve research continuation: implement a bounded, throwaway `SemanticAnchor` POC behind a feature flag, measure that `CommandLivenessMatrixTests` and `CrlfCodeBlockTests` stay green while `caretInsideContent` is called only from the anchor path, and present that measurement as the `§15` proof. Do not change `ENGINEERING`/`REQUIREMENTS` until that proof discriminates.

## Deletion/refresh triggers

Delete this research if `DISC-01` is implemented (plan deleted, `ENGINEERING §15` gate satisfied) or if `ARC-007`/`ARC-009` are otherwise changed. Refresh if pinned `cmark-gfm` or `MarkdownSourceIndex` span reporting changes.
