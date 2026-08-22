# COR-85 — Contrast repair for content-bearing colour roles

- **Status:** Approved 2026-08-22 (user directive: fix the reproduced defects)
- **Delivers:** REQ-139 (back to `Done`)
- Architecture impact: none. `EditorColorCatalog` already owns every painted colour; this changes
  what two roles resolve to, not how colour is expressed.
- **Product impact: yes, and it is visible.** This changes the approved appearance, which
  `VISION.md` owns. Approved by explicit user directive; record the decision there.
- Blockers: none.
- Executor: measure first, then choose; never pick a colour and assume it passes.

## The two defects

Measured in `../research/COR-81-contrast-conformance.md`, pinned by
`ContrastConformanceTests.knownContrastViolations`.

| role | appearance | measured | bound | drawn as |
| --- | --- | --- | --- | --- |
| `secondaryText` | Light | 3.95:1 | 4.5:1 | block-quote text, table header text, list markers |
| `separator` | Light | 1.25:1 | 3:1 | thematic breaks, table borders, block-quote bar |
| `separator` | Dark | 1.34:1 | 3:1 | as above |

`separatorColor` is designed as a decorative hairline and Apple uses it that way. This editor draws
**content** with it: a thematic break is the rendering of `---`, a construct the reader is meant to
perceive, and table borders carry the table's structure.

## Repair

Split `separator` by what it draws, because the two uses have different bounds and conflating them
is what produced the defect:

- **`separator`** stays `NSColor.separatorColor` for incidental dividers, if any remain.
- **`structuralRule`** — a new role for thematic breaks, table borders and the block-quote bar,
  resolving to a system colour that measures ≥ 3:1 in both appearances.
- **`secondaryText`** resolves to a system colour measuring ≥ 4.5:1 in both appearances.

Candidates are `tertiaryLabelColor`, `labelColor`, `textColor`, and `NSColor.gridColor`; the choice
is whichever *measures* within bound, established by running the existing contrast arithmetic over
each candidate rather than by judgement. If no system colour qualifies, define the role with
`NSColor(name:dynamicProvider:)` so it stays appearance-aware and stays inside the catalog — a
literal outside the catalog would fail `productionNamesNoColorOutsideTheCatalog`, which is correct.

## Proof

- `knownContrastViolations` becomes empty and the constant is **deleted**, so the test asserts
  conformance rather than pinning a set. `EditorColorRole.allCases` still drives the enumeration, so
  a future role fails until measured.
- Increase Contrast must still never lower a ratio — the existing test covers this and must stay
  green for the new roles too.
- The closing screenshot is re-captured and reviewed: the block-quote bar was visibly faint in the
  COR-83 capture, and that is the human-visible half of this defect.

## Failure and rollback

If no available colour meets a bound without an unacceptable visual change, stop and report the
trade-off rather than lowering the bound. The bound is WCAG's, not ours.

## Deletion gate

No pinned contrast violations remain, no colour is named outside `EditorColorCatalog`, and no role
is measured against a surface it is not drawn on.
