# COR-81 — WCAG contrast conformance of the approved appearance

> **Repaired by COR-85 on 2026-08-22.** `secondaryText` now resolves to `labelColor` at 60% alpha
> (5.74:1 Light, 6.77:1 Dark) and the role formerly called `separator` is `structuralRule`,
> resolving to `systemGray` (3.26:1 Light, 5.81:1 Dark). Every role now meets its bound and the
> pinned violation set is deleted. Retained because the measurements below are what the choice was
> made from, and because the reasoning — that a thematic break is content, not chrome — is the part
> that would otherwise be re-litigated.

- **Authority:** evidence only. Not a product decision and not a repair plan.
- **First researched:** 2026-08-22
- **Last verified:** 2026-08-22
- **Environment:** macOS 27.0 (Darwin 27.0.0), Xcode-beta, Debug
- **Method:** `ContrastConformanceTests` resolves every `EditorColorRole` under
  `NSAppearance.performAsCurrentDrawingAppearance` for Aqua and DarkAqua, composites alpha onto the
  surface the role is actually drawn on, and computes the WCAG 2.1 relative-luminance ratio. The
  luminance formula is written out in the test rather than shared with production, so the two are
  independent.
- **Refresh triggers:** any change to `EditorColorCatalog`, to the approved typography in
  `ENGINEERING.md` §7, or a macOS release that redefines a system colour.

## What was found

Two of the six declared colour roles do not meet their WCAG 2.1 bound. Both are pinned in
`ContrastConformanceTests.knownContrastViolations`, which fails if the set grows **or shrinks**.

| role | appearance | measured | bound | drawn as |
| --- | --- | --- | --- | --- |
| `secondaryText` | Light | **3.95:1** | 4.5:1 | block-quote text, table header text, list markers |
| `separator` | Light | **1.25:1** | 3:1 | thematic breaks, table borders, block-quote bar |
| `separator` | Dark | **1.34:1** | 3:1 | as above |

Everything else conforms, including code text on the translucent code background (measured against
`quaternaryLabelColor` composited over `textBackgroundColor`, not against the window), and
Increase Contrast never lowers any role's ratio.

## Why these are not simply "Apple's colours are fine"

`NSColor.separatorColor` is designed as a hairline divider, and Apple's own use of it is
decorative. This editor uses it for **content**: a thematic break is the rendering of `---`, a
Markdown construct the reader is meant to perceive, and table borders carry the table's structure.
A 1.25:1 rule is invisible to many readers and, in a document editor, that is lost content rather
than lost chrome.

`NSColor.secondaryLabelColor` at 3.95:1 is close to the bound but under it, and it carries
block-quote body text — running prose, at body size.

## Not repaired here

Both fixes are product decisions about the approved appearance, which `VISION.md` owns:

- **`secondaryText`** could resolve to `labelColor` for block-quote body text while staying
  secondary for markers, or the approved palette could gain a dedicated de-emphasised role with a
  measured ratio.
- **`separator`** could use a stronger role for thematic breaks and table borders while leaving
  incidental dividers alone.

Neither is made here. REQ-139 is `Correction` with a reproduced counterexample rather than
`Planned`, because the counterexample now exists and is measured.

## Note on what the catalog changed

Before this increment, production named six system colours directly at twenty sites across two
files. Nothing could enumerate them, so nothing could measure them.
`EditorColorRole.allCases` is what makes the measurement possible at all, and
`DisplayPreferencePolicyTests.productionNamesNoColorOutsideTheCatalog` is what keeps a new colour
from re-entering unmeasured — with its detector self-tested against four literal forms, because an
absence proof whose pattern never matches is indistinguishable from a clean codebase.
