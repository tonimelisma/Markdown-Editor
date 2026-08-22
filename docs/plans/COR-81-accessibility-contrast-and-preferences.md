# COR-81 — Accessibility, contrast, and display preferences

- **Status:** Approved; partially implemented (2026-08-22).
  **Delivered:** `EditorColorCatalog` with a closed `EditorColorRole` enum, replacing twenty direct
  system-colour references across two files; `ContrastConformanceTests` (WCAG 2.1 arithmetic over
  every role in Aqua/DarkAqua plus Increase Contrast, alpha composited onto the real surface);
  `DisplayPreferencePolicyTests` (colour literals outside the catalog, motion/translucency pairing,
  and the REQ-140 text-scaling absence — with the colour detector self-tested). REQ-141 is `Done`.
  REQ-139 is `Correction`: two roles measure below their bound, recorded in
  `../research/COR-81-contrast-conformance.md`, and the fix is a VISION appearance decision.

  **Remaining:** `MarkdownAccessibilityModel` and the AppKit accessibility elements for heading,
  paragraph, list/item, quote, code, table/cell and raw HTML (REQ-129), and the keyboard-reachability
  matrix (`KeyboardCommandMatrixTests`) that REQ-032 needs. Thematic break, task checkbox, image,
  link, and both editor views already expose roles and labels; the closed per-block model does not
  exist yet.
- **Delivers:** REQ-032, REQ-129, REQ-139, REQ-141
Architecture impact: none; establishes reserved ARC-025, ARC-Q21, ARC-Q23, and ARC-Q25
Blockers: COR-76, COR-77
Executor: A junior developer may implement this plan in order. Obtain senior review of the closed semantic accessibility model before adding AppKit elements.

## Outcome

Expose Markdown semantics and every offered action through directly constructed AppKit accessibility
objects; prove full keyboard reachability; meet declared Light/Dark contrast; and ensure motion,
transparency, and literal-color additions cannot bypass platform preference policy.

## Files and ownership

- Add `MarkdownAccessibilityModel.swift` and thin AppKit accessibility elements owned by the
  WYSIWYG view for heading, paragraph, list/item, task, quote, code, table/cell, link, image, raw HTML,
  and thematic break.
- Add one semantic `EditorColorCatalog`; migrate literal production colors and delete displaced
  theme/facade aliases rather than layering catalogs.
- Add `AccessibilitySemanticTests`, `KeyboardCommandMatrixTests`, `ContrastConformanceTests`, and
  `DisplayPreferencePolicyTests`; directly construct components, never launch XCUITest or VoiceOver.
- Keep REQ-140 Deferred; do not invent an Accessibility Text Size API or add in-app scaling here.

## Implementation

1. Declare a closed semantic role matrix: label/value/role/level/children/actions and source-derived
   privacy boundary for every presentation block/atom. Avoid reading live mutable AppKit state during
   SwiftUI reconciliation.
2. Build elements from the immutable presentation snapshot and map frames only after real layout.
   Stale snapshots expose nothing; actions route through the transaction kernel and revalidate identity.
3. Enumerate every `EditorCommand`, editor mode, menu/toolbar/key equivalent, focus transition,
   checkbox, link, and image-description action. Prove ordinary success and correct unavailable state.
4. Resolve catalog colors in Aqua/DarkAqua plus Increase Contrast. Composite alpha and calculate WCAG
   relative luminance against actual resolved backgrounds at the declared font sizes.
5. Add a structural production policy: animation/translucency APIs require paired Reduce Motion/
   Reduce Transparency behavior; new color literals fail outside the catalog. Rehearse each gate red.

## Proof and failure behavior

Role/action matrices cover every semantic and command enum case. Layout-backed accessibility frames
are bounded and ordered. Actions mutate only their active document. Contrast arithmetic proves each
foreground/background/appearance/state tuple. Preference changes rebuild derived presentation without
changing source or history.

## Deletion/conformance gate

No semantic construct relies only on font/color/indentation; no offered command lacks keyboard and
accessibility route proof; no production literal color, unpaired animation/translucency, duplicate
theme catalog, or false text-scaling claim remains.
