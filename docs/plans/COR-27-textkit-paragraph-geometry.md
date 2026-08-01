# COR-27 — TextKit paragraph geometry

- **Status:** Approved; not implemented

## Scope

`NSParagraphStyle.paragraphSpacing` is applied after every **TextKit** paragraph, and TextKit
ends a paragraph at every `\n` in the storage. The projection inserts real newline characters for
constructs that are *not* semantic paragraph boundaries, so those constructs receive
paragraph-sized vertical gaps.

Confirmed in the REQ-104 capture at `88b7bd3`: a formal hard break renders with the same vertical
gap as a paragraph boundary (measured ≈69 px versus ≈70 px in the same image). REQ-106 requires a
soft break, a hard break, and a paragraph boundary to have three distinct presentations; only two
are distinguishable on screen.

The same mechanism is present but not yet observed in the fenced code block:
`AttributedPresentationBuilder.applyBlock` sets `style.paragraphSpacing = typography.blockSpacing`
across the whole `.codeBlock` range, so a multi-line fenced block should receive block-sized
spacing between every line of code. The rich fixture's code block is a single line, so the
mandatory visual gate cannot currently see it.

This is the same family as the blockquote "one character per line" defect COR-22 found by eye:
paragraph-level attributes applied across a range without accounting for how TextKit divides that
range into paragraphs.

## Requirements and invariants

- REQ-106 → `Correction`: soft break, hard break, and paragraph boundary must be three visually
  distinct presentations, not three distinct strings.
- REQ-107 → `Correction`: the approved semantic block treatment for code blocks must not apply
  block spacing between lines within one block.
- REQ-105: the approved typography tokens are unchanged by this increment.
- ARC-018: typography stays derived from semantic presentation plus immutable tokens and never
  changes canonical source, history, or coordinate meaning.
- ARC-Q14, ARC-Q15: constructed attributed presentation and constructed-container layout proofs.
- ARC-019, ARC-Q16: attribute changes continue to travel the bounded patch/refresh routes.
- **Architecture impact: ENGINEERING §7 amendment required, in the implementing change.**

## ENGINEERING §7 amendment

Two rules in §7 cannot both hold in TextKit as written:

> A cmark `lineBreak` emits a distinct hard-line-break atom and **a visible newline**.

and:

> Paragraph spacing and heading spacing are **`NSParagraphStyle` attributes**. Synthetic extra
> newline characters are not inserted merely to create visual spacing.

A visible newline *is* a TextKit paragraph terminator, so it necessarily collects
`paragraphSpacing`. The implementing change states the resolution explicitly: spacing is a
property of a **semantic** block boundary, and a rendered newline that is not a semantic block
boundary must carry a paragraph style whose `paragraphSpacing` is zero. This is an amendment to
how §7 describes the mechanism; it does not change any `ARC-###` invariant, the typography
tokens, the rendered string, or any coordinate.

## Production route

Modify:

- `Markdown Editor/AttributedPresentationBuilder.swift`
  - `applyBlock` — install paragraph styles per **TextKit paragraph** within a semantic block
    rather than once across the block's whole range. Only the paragraph that ends at a semantic
    block boundary carries `paragraphSpacing`; interior paragraphs (hard-break continuations,
    code-block lines, multi-line quote content) carry zero.
- `Markdown Editor/PresentationBlock.swift` — if the semantic block does not already expose its
  interior newline positions, add that structural metadata rather than rescanning the rendered
  string in the builder. The builder must keep receiving structure, not rediscovering it.

- `Scripts/Fixtures/smoke-rich.md` — extend the fenced code block to at least three lines, so the
  mandatory visual gate can see the defect this increment fixes. A single-line block is why the
  code-block half of this defect was invisible to REQ-104 until now.

Add:

- `Markdown EditorTests/ParagraphGeometryTests.swift` — laid-out geometry proofs.

Delete: nothing.

## Implementation phases

1. Add failing geometry proofs for (a) hard break versus paragraph boundary and (b) a
   three-line fenced code block. Both must fail on current `main`.
2. Extend semantic block metadata with interior newline structure if not already present.
3. Apply per-TextKit-paragraph styles in `applyBlock`.
4. Verify blockquote, list continuation, and table cell geometry are unchanged.
5. Re-run ARC-Q14/ARC-Q15 suites and the attribute-refresh patch proofs.
6. Amend ENGINEERING §7; reconcile REQ-106/REQ-107 back to `Done`; delete this plan.

## Automated non-UI proof

The existing typography suites assert **attribute values** (`textBlocks`, `paragraphSpacing`).
Every visual defect found in this project so far — inverted task checkmark, collapsed blockquote,
and now hard-break spacing — lives past the last such assertion. This increment adds assertions
on **laid-out geometry**, using the constructed-container technique `TypographyLayoutTests`
already establishes, with no UI automation:

- build the attributed presentation, install it in a directly constructed `NSTextView` with a
  fixed container width, force layout, and read
  `NSLayoutManager.lineFragmentRect(forGlyphAt:effectiveRange:)`;
- assert the vertical delta across a **hard break** equals one body line advance within
  tolerance, and is strictly less than the delta across a **paragraph boundary** in the same
  document;
- assert consecutive lines inside one fenced code block have a uniform line advance with no
  block-spacing gap, while the gap *after* the block equals `blockSpacing`;
- assert the rendered string is byte-identical before and after the change (ARC-018), so this is
  provably a layout-only correction.

These are component tests over directly constructed AppKit objects, which `CLAUDE.md` §4 permits;
no XCUITest and no screen automation is involved.

## Instrumentation and performance evidence

- No new trace event.
- Per-paragraph style installation increases attribute work within a block. Re-record the focused
  Release `nativeInputCallback` gate (REQ-090, p95 < 8 ms) and the `authoritativeApplication`
  boundary, and record the multi-line-code-block corpus explicitly, since that is the case whose
  attribute count changes most.
- Confirm `storage.fullReplacements == 0` for an ordinary edit inside a multi-line code block.

## Failure and rollback behavior

If interior newline structure cannot be derived for a block, the builder must apply the current
whole-block style and the block is reported through the existing `presentationRecovered` fault
route rather than silently rendering with guessed geometry. Canonical source is untouched in all
cases; this increment changes only derived attributes.

## Deletion and conformance gate

- Prove exactly one paragraph-style installation route exists in `AttributedPresentationBuilder`;
  no second path may set `paragraphSpacing`.
- Prove the rendered string and every coordinate map are unchanged by the increment.
- Both gate scripts pass; both smoke scripts pass; the REQ-104 screenshot is re-captured and
  reviewed with the hard break and the multi-line code block both visible; delete this plan in
  the implementing change.
