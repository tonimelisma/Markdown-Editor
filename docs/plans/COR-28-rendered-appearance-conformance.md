# COR-28 — Rendered appearance conformance

- **Status:** Approved; not implemented

## Scope

Three rendered-appearance defects that every existing test passes over, plus the fixture weakness
that let two of them reach the mandatory visual gate unnoticed. All three were found by reviewing
the REQ-104 capture at `88b7bd3` and then confirmed in source.

### 1. Fenced code blocks carry two backgrounds

`ProjectionCompiler` marks fenced code content with the **same** inline style used for inline code
spans:

- `ProjectionCompiler.swift:97-102` — `codeBlock` content → `styles: styleStack + [.code]`
- `ProjectionCompiler.swift:133-134` — inline code → `styles: styleStack + [.code]`

`AttributedPresentationBuilder.swift:145-147` then attaches a run `backgroundColor` for `.code`
unconditionally, while `:220-221` also installs the `NSTextBlock` container background. The result
is a darker band inside a lighter container, visible in the capture. ENGINEERING §7 states the two
treatments are distinct — "Code blocks use block geometry and padding. Inline code remains
inline" — and they must not compose.

### 2. Toolbar items render as blank buttons

`EditorToolbarController.menuItem(_:label:command:)` sets `label`, `paletteLabel`, `toolTip`,
`target`, `action`, `tag`, and `menuFormRepresentation`, and never sets `image`. An
`NSToolbarItem` with no image and no view draws as an empty control with a label beneath it. Bold,
Italic, and Link are blank circles in the capture. `EditorToolbarConstructionTests` asserts
per-window ownership and identifiers, not appearance.

### 3. The visual gate's fixture cannot discriminate success from failure

`Scripts/Fixtures/assets/sample.png` is a 64×64 image of a blank document page. ENGINEERING §7
requires that a missing image use "an intentional labeled placeholder rather than an unrelated
generic file icon" — and the fixture's **successful** render is visually indistinguishable from
exactly that forbidden failure mode. A reviewer looking at the mandatory capture cannot tell
whether image resolution worked. During this review it was initially misread as a defect.

## Requirements and invariants

- REQ-107 → `Correction`: code-block treatment must not compose with the inline-code treatment.
- REQ-058, REQ-108 → `Correction`: the adaptive native toolbar must present identifiable
  controls.
- REQ-104 → `Correction`: the visual-review fixture must let a reviewer distinguish a correct
  render from the failure modes ENGINEERING forbids.
- REQ-032: accessibility meaning must not depend on the icon alone; labels and `toolTip` remain.
- ARC-018: typography and appearance stay derived and never touch source.
- ARC-024: menu and toolbar remain presentations of one command model.
- **Architecture impact: none.**

## Production route

Modify:

- `Markdown Editor/ProjectionCompiler.swift` — distinguish fenced-block content from an inline
  code span at the point the style is assigned, so the presentation layer is told which it is
  rather than inferring it. Prefer a distinct `PresentationInlineStyle` case over a positional
  test in the builder.
- `Markdown Editor/PresentationInlineStyle.swift` — carry that distinction.
- `Markdown Editor/AttributedPresentationBuilder.swift` — apply the run background for inline
  code only; fenced content keeps the monospaced font and the container background only.
- `Markdown Editor/EditorToolbarController.swift` — set `item.image` from SF Symbols for every
  command item (`bold`, `italic`, `link`, `Add Image…`), and set `image` on the grouped
  `NSMenuToolbarItem`s. Keep every existing label, `paletteLabel`, `toolTip`, and
  `menuFormRepresentation`, so overflow and accessibility are unchanged.
- `Scripts/Fixtures/assets/sample.png` — replace with a small, high-contrast, unmistakably
  non-iconic image (for example a solid-colour block with a diagonal), still a valid PNG and
  still tiny.
- `Scripts/Fixtures/smoke-rich.md` — add a second image reference that is deliberately **broken**,
  so one capture shows a correct render and the labeled placeholder side by side. (COR-27 has
  already extended the fenced code block to multiple lines.)

Delete: nothing.

## Implementation phases

1. Add the failing attributed-presentation assertion that fenced content carries no run
   `backgroundColor` while inline code does.
2. Split the style at the compiler and apply it in the builder.
3. Add the failing toolbar assertion that every command item has a non-nil `image`; set the
   images.
4. Replace the fixture image and extend the rich fixture.
5. Re-capture the REQ-104 screenshot and review it against every construct.
6. Reconcile REQ-058/104/107/108; delete this plan.

## Automated non-UI proof

- `AttributedPresentationTests`: for `` `inline` `` the run at the code range has
  `.backgroundColor`; for a fenced block the content runs have **no** `.backgroundColor` while
  the paragraph style still carries the `NSTextBlock` container. This discriminates — it fails on
  current `main`.
- `EditorToolbarConstructionTests`: every `NSToolbarItem` this controller vends for a semantic
  command has a non-nil `image`, a non-empty `label`, and a `menuFormRepresentation`. A new
  toolbar command with no icon fails the build.
- A fixture assertion that `Scripts/Fixtures/smoke-rich.md` retains a fenced block of at least
  three lines (COR-27) and gains at least one unresolvable image reference, so the visual gate's
  discriminating power cannot silently regress when the fixture is edited.
- The missing-image placeholder test asserts `MissingImageAttachmentCell` renders its label text,
  since "labeled placeholder" is the ENGINEERING requirement and an unlabeled box would satisfy
  neither the requirement nor a reviewer.

## Instrumentation and performance evidence

- No new trace event here; the unrecorded image-resolution failure that the broken fixture
  reference will now exercise is closed by COR-29 (REQ-114) and the two increments should be
  reviewed together when both have landed.
- No performance movement expected. Re-record the focused Release gates as usual and treat any
  movement as a finding.

## Failure and rollback behavior

If an SF Symbol name is unavailable on the deployment target, the toolbar item must fall back to
its text label rather than render blank, and the toolbar test asserts the fallback is non-empty.
No source, asset, or coordinate state participates in this increment.

## Deletion and conformance gate

- Prove `.code` no longer carries two meanings: the fenced and inline cases are distinct at the
  type level, so the composition cannot be reintroduced without changing the enum.
- Prove there is exactly one place a toolbar command item is constructed.
- Both gate scripts pass; both smoke scripts pass; the re-captured screenshot is reviewed and
  sent to the user per `CLAUDE.md` §3; delete this plan in the implementing change.
