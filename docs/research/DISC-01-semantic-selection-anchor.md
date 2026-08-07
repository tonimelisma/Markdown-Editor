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

### POC-A — Block identification without coordinate inverse (throwaway, not committed)

- Created `EditorSessionTests` throwaway: for a WYSIWYG caret at `{42,0}` inside a paragraph block whose `projectionRange` is `{40,20}`, `MarkdownProjectionModel.blocks.first(where: { NSLocationInRange(caretLocation, $0.projectionRange) })` reliably identifies the enclosing block without calling `ProjectionSelectionClassifier` or `ProjectionAtom` inverse mapping.
- Verification: `WYSIWYGEditorTests` caret at `0` and at `presentation.renderedString.length-1` always identifies some block; `tableCell` remains the only block that requires cell-granular mapping (already has `ProjectionSelectionClassifier.TableCell`).

### POC-B — Anchor stability across line-reshaping

- `NSString.lineRange(for:)` for the identified block's source `NSRange` is stable across `BlockEditPlanner` rewrites: rewriting `"First paragraph.\n"` to `"# First paragraph.\n"` keeps the anchor's *block identity* (same `nodeID` family) but changes its `projectionRange` length. An anchor storing `(blockID, offsetInBlockContent)` survives that length change; a generic `NSRange` does not.

### POC-C — Online/policy check

- `cmark-gfm` `node.firstChild`/`next` block tree and `MarkdownSourceIndex` `utf8Range` remain off-main immutable snapshots; block identification from presentation snapshot does not need main-actor `NSTextView` or `NSLayoutManager`.
- Existing `ImagePlacementController` already uses `MarkdownSourceIndex` + `CanonicalAssetReferences` derived from the cmark tree, not regex — precedent for block-sourced truth.

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
|---|---|---|
| **1. Scope ARC-009** | Smallest doc/code change; keeps `NSRange`-based planning; reuses existing `SourceMutation.exact` | Still reasons about ranges; 11-site caret helper remains but becomes simpler |
| **2. Semantic anchor** | Removes coordinate reasoning from planners entirely for `reshapesWholeLine`; anchor survives rewrite by construction | New type + two-way conversion (anchor↔source NSRange); migration of 4 planners |

A third rejected option — make `ProjectionSelectionClassifier` total for caret — was not pursued because `ARC-007` exact-or-refuse is load-bearing for *content*; weakening it there would risk document corruption.

## Recommendation for next discovery step

Approve research continuation: implement a bounded, throwaway `SemanticAnchor` POC behind a feature flag, measure that `CommandLivenessMatrixTests` and `CrlfCodeBlockTests` stay green while `caretInsideContent` is called only from the anchor path, and present that measurement as the `§15` proof. Do not change `ENGINEERING`/`REQUIREMENTS` until that proof discriminates.

## Deletion/refresh triggers

Delete this research if `DISC-01` is implemented (plan deleted, `ENGINEERING §15` gate satisfied) or if `ARC-007`/`ARC-009` are otherwise changed. Refresh if pinned `cmark-gfm` or `MarkdownSourceIndex` span reporting changes.
