# COR-37 — A nested block's container composes, not replaces

- **Status:** Approved; not implemented

## Scope

A fenced code block that is the only child of a block quote loses its padded container — `backgroundColor == nil` where an unnested code block measures non-nil. REQ-107 promises the padded code container; ARC-018 promises derived typography composes through semantic blocks without changing source. Make the two decorated containers compose so a code block inside a quote renders both the quote rule and the code padding/background.

## Reproduction

Measured on `main` at `1a16944` (after COR-36), through real `MarkdownParser` → `MarkdownProjectionModel` → `AttributedPresentationBuilder` and laid-out geometry:

- Source `> ```\n> code here\n> ```\n` → quote `{0,10}` and codeBlock `{0,10}` (identical ranges; the quote's two children before it mean the builder comment “containing blocks are applied first” is true for list items but irrelevant here — the tie is the bug).
- `AttributedPresentationBuilder` sorts `model.blocks` by `projectionRange.length` descending at line 93. That comparator orders only strict inequalities; Swift's sort is stable, so the tie keeps the emitted order (code then quote). Each case assigns `style.textBlocks` wholesale, so whichever runs last wins.
- Installed style: `textBlocks.count == 1` with quote rule, `backgroundColor == nil`. Control: unnested ``` code block → non-nil background.

List already composes via cumulative `firstLineHeadIndent`/`headIndent` and `COR-36`; tables compose via `NSTextTable`; this defect is specific to the two `NSTextBlock` users (`blockQuote` and `codeBlock`).

## Cause

`AttributedPresentationBuilder.apply(block:localRange:to:typography:)` builds the paragraph style by copying the enclosing style at `range.location` and then *replaces* `textBlocks`:

```swift
case .blockQuote(let depth):
    style.textBlocks = (0..<max(1, depth)).map { _ in typography.quoteBlock() }
case .codeBlock:
    style.textBlocks = [typography.codeBlock()]
```

When the ranges coincide, the second assignment discards the first's containers. Ordering alone would merely reverse which container is lost. The fix is composition, not ordering.

`nestedBlockQuotesComposeTheirRules` currently asserts `textBlocks.count == max(1, depth)`, which encodes quote depth by assigning `depth` blocks in one block. Under composition that expectation must be restated: a blockquote at depth 2 inside another composed container should still own `depth` quote blocks, but the *installed* paragraph style may also carry a code container. The proof must discriminate composition from replacement.

## Architecture impact

None beyond the existing `ARC-018` composition rule: typography is derived from semantic blocks plus immutable tokens and never changes source. This implements that rule rather than changing it. No new `ARC-###`.

## Approved approach — compose `textBlocks`

Change `apply(block:)` to **append** instead of replace, reading the enclosing style's existing `textBlocks` and composing:

- `blockQuote`: `style.textBlocks = (existing ?? []) + (0..<depth).map { typography.quoteBlock() }` — but depth here is the block's own quote depth derived from `styleStack`; when composing, the enclosing style already carries outer quote blocks, so the depth must be the *local* depth contributed by this node (presently `max(1, depth)` conflates local and total). Preserve the invariant that `depth` is total enclosing quote depth by making the local contribution `1` for the current block and letting composition accumulate — or keep the current mapping and deduplicate. Chosen: local contribution is `1`; composition of two nested quotes yields `2` blocks as required.

- `codeBlock`: `style.textBlocks = (existing ?? []) + [typography.codeBlock()]`

Rationale:

1. Uses the architecture already defined (ENGINEERING §7: “Blocks nested inside a decorated block inherit its geometry instead of replacing it.”) — this *is* that inheritance.
2. Ordering becomes irrelevant: both containers are present regardless of stable-sort tie.
3. Minimal file touch: only `AttributedPresentationBuilder.swift` changes; sorting can stay length-descending (still the right heuristic for list/quote/paragraph ordering) or be left as-is — composition removes the sensitivity.

Rejected: re-sorting by depth or type. That fixes the repro's winner but still assigns wholesale and does not compose; a future nested combination would re-trigger the class.

## Exact production files

- Modify: `Markdown Editor/AttributedPresentationBuilder.swift` — `apply(block:)` cases `.blockQuote` and `.codeBlock` to compose `textBlocks`; adjust `installPerTextKitParagraph` handling if needed (textBlocks are per-TextKit paragraph already via the same install path).
- No other production files.

## Tests

Driven through the real `MarkdownProjectionModel` → `AttributedPresentationBuilder` via directly constructed `NSTextView` laid-out geometry (CLAUDE.md §4), not attribute values alone:

- `nestedCodeBlockInsideQuoteComposesBothContainers` — for `> ```\n> code here\n> ```\n` assert installed paragraph style at `0` has `textBlocks` containing at least one quote block (rule) *and* one code block (background non-nil), and `backgroundColor` non-nil; control unnested code block also non-nil (so test fails when either container is lost).
- `nestedQuoteInsideQuoteComposesRules` — restates `nestedBlockQuotesComposeTheirRules` under composition: `>> paragraph` yields two quote blocks in the installed style, not `max(1, depth)` from a single assignment.
- Existing `ParagraphGeometryTests`, `TypographyLayoutTests` must still pass.

All tests are `test` (non-UI component construction), per CLAUDE.md §4.

## Instrumentation and performance

No new trace events; existing `presentationInstalled` suffices. No performance path change — patch scope unchanged.

## Failure and rollback

If composition cannot be proven for the two container kinds, revert to current replacement behavior — the defect remains but no new visual regression is introduced. No source change ever occurs here (typography only).

## Deletion and conformance gate

- Delete no other production path; this replaces wholesale assignment with composition in the same build.
- `Scripts/check-documentation-authority.sh` and `Scripts/check-instrumentation-coverage.sh` pass.
- `Scripts/check-proof-results.sh` passes with the new tests.
- Delete this plan when implemented; Git retains history.
