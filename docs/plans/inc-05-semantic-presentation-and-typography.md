# INC-05 — Semantic presentation and typography

- **Status:** Approved; not implemented
- **Kind:** App-code increment; one worktree, branch, PR, and squash merge
- **Requirements:** REQ-054–056, REQ-078–081, REQ-084, REQ-105–107
- **Architecture:** Implements ARC-018, ARC-Q14, ARC-Q15; preserves ARC-003, ARC-007–009
- **Depends on:** COR-18 and COR-19
- **Must finish before:** COR-20

## Goal

Replace font/color-only WYSIWYG styling with a semantic native presentation system and implement
the approved typography exactly. This increment may still apply a complete attributed snapshot;
COR-20 changes ordinary-edit application to patches. Canonical source, projection coordinates,
edit semantics, and parser configuration do not change.

## Typography contract

Implement the tokens in ENGINEERING §7 without substituting approximate ad hoc values:

- body: 15-point system regular;
- line height: approximately 1.35× using one documented paragraph-style mechanism;
- centered maximum reading measure: 720 points;
- minimum insets: 28 horizontal and 20 vertical points;
- ordinary paragraph spacing: 0.7 em;
- H1–H6: 30/24/20/17/15/13 points, semibold, more spacing before than after;
- list nesting: 24 points per depth and hanging marker alignment;
- blockquote: 3-point adaptive leading rule and 16–18-point inset;
- inline code: approximately 0.93-em monospaced adaptive treatment;
- code block: padded monospaced adaptive block;
- thematic break: one-pixel full-measure separator.

If AppKit cannot express a token without breaking selection/editability, build a bounded component
POC, present measured alternatives, and obtain approval before changing the contract.

## Files

### Modify

- `Markdown Editor/MarkdownProjectionModel.swift`
- `Markdown Editor/ProjectionCompiler.swift`
- `Markdown Editor/ProjectionAtom.swift`
- `Markdown Editor/ProjectionSegment.swift`
- `Markdown Editor/PresentationSnapshot.swift`
- `Markdown Editor/PresentationTransition.swift`
- `Markdown Editor/RichTextBuilder.swift`
- `Markdown Editor/MarkdownTheme.swift`
- `Markdown Editor/WYSIWYGEditor.swift`
- `Markdown Editor/EditorHost.swift`
- `Markdown Editor/AuthoritativePresentationBuilder.swift`
- `Markdown EditorTests/ProjectionAndSemanticEditTests.swift`
- `Markdown EditorTests/ProjectionCharacterizationTests.swift`
- `Markdown EditorTests/PersistentEditorCharacterizationTests.swift`
- `Markdown EditorTests/AcceptedEditTransactionTests.swift`
- `Scripts/Fixtures/smoke-rich.md`
- `docs/ENGINEERING.md`
- `docs/REQUIREMENTS.md`
- `docs/ROADMAP.md`

### Add

- `Markdown Editor/MarkdownTypography.swift`
- `Markdown Editor/PresentationBlock.swift`
- `Markdown Editor/PresentationInlineStyle.swift`
- `Markdown Editor/AttributedPresentation.swift`
- `Markdown Editor/AttributedPresentationBuilder.swift`
- `Markdown Editor/PresentationAttachment.swift`
- `Markdown EditorTests/TypographyTokenTests.swift`
- `Markdown EditorTests/AttributedPresentationTests.swift`
- `Markdown EditorTests/TypographyLayoutTests.swift`

### Delete

- `Markdown Editor/RichTextBuilder.swift` after all construction routes use
  `AttributedPresentationBuilder`
- font/color selection from `ProjectionCompiler`
- `PlaceholderAttachmentCell` use for thematic breaks
- duplicate task bullet generation
- any synthetic newline inserted solely for visual block spacing
- this plan after implementation

## Type boundaries

### Background-safe semantic values

`PresentationBlock` and `PresentationInlineStyle` are immutable `Sendable` values containing no
AppKit objects.

Minimum block cases:

- paragraph
- heading(level)
- listItem(kind, nesting, markerRange, task)
- blockQuote(depth)
- codeBlock(languageHintPresent)
- table / tableRow / tableCell(alignment, header)
- thematicBreak
- image
- literalHTML

Every block carries its exact projection range and source identity. Ranges are complete, ordered,
and validated by `ProjectionOracle`.

### Main-actor attributed values

`MarkdownTypography` owns immutable numeric/system-color tokens. `AttributedPresentationBuilder`
accepts one complete semantic snapshot plus resolved images and returns:

- complete `NSAttributedString`;
- attachment-node lookup;
- block decoration descriptors that cannot be represented by ordinary attributes;
- the same presentation identity as the semantic snapshot.

No AppKit type enters the parser, source index, semantic compiler, or detached task.

## Implementation

1. Add semantic blocks to the projection output without changing rendered text.
   - Extend oracle validation for complete ordered block coverage where required.
   - Keep inline run coverage independent from block ranges.
2. Separate soft and hard breaks.
   - `.softBreak` emits one presentation space with `.softLineBreak` coordinate policy.
   - `.lineBreak` emits `\n` with a distinct `.hardLineBreak` kind.
   - Paragraph boundary uses block metadata and paragraph style; do not add a blank visual line.
3. Implement typography tokens in one type.
   - Convert em values from the block's effective font size.
   - Use adaptive system colors; no fixed RGB values.
   - Copy paragraph styles before mutation and never mutate a style already installed in storage.
4. Implement reading-column layout in `EditorHost`.
   - Keep the scroll view/window behavior native.
   - Center a text container no wider than 720 points.
   - At narrower widths, retain at least 28 points horizontal inset without clipping the insertion
     point, selection, Find bar, or scroller.
   - Apply 20 points vertical inset.
5. Paragraphs/headings:
   - apply body leading/spacing;
   - heading spacing before/after according to level;
   - do not add leading space before the first block;
   - keep heading with following content where AppKit supports it without pagination assumptions.
6. Lists:
   - use tab stops, `firstLineHeadIndent`, and `headIndent` for hanging layout;
   - increase both by exactly 24 points per nesting level;
   - align wrapped continuation text with item content;
   - remove the ordinary marker when a task checkbox attachment exists;
   - preserve ordered numbering and concrete marker mapping.
7. Blockquotes:
   - indent content;
   - render a three-point adaptive rule through an `NSTextBlock` or tested layout decoration;
   - keep selection and accessibility over the quoted text;
   - do not use color as the only distinction.
8. Inline/code blocks:
   - inline code remains text, editable, and coordinate-backed;
   - code block background/padding spans the block and respects the reading measure;
   - literal code line endings remain semantically correct.
9. Tables:
   - retain current editable `NSTextTable` path;
   - size to contents within the reading measure;
   - use restrained adaptive borders/padding and semibold headers;
   - preserve exact single-cell editing/refusal behavior.
10. Thematic break:
    - replace the dash-text attachment with a semantic separator drawing route;
    - expose an accessibility separator role/label if supported;
    - keep its source span atomic/uneditable as currently required.
11. Images:
    - preserve aspect ratio;
    - fit to the current reading measure, not a fixed 480-point constant;
    - provide authored-description accessibility;
    - use an intentional labeled missing-image placeholder.
12. Raw HTML/literal fallback:
    - remain non-executing;
    - use muted monospaced presentation;
    - remain editable only where the exact existing mapping permits.
13. Replace all `RichTextBuilder.build` call sites with the new builder and delete the old file.
14. Update the rich smoke fixture only when necessary to expose every approved semantic treatment
    in one default window.

## Automated proof

### Semantic tests

- Every supported block emits the expected `PresentationBlock`.
- Soft break renders a space; hard break renders a newline; paragraph boundary carries spacing.
- Source/projection oracle remains valid for LF, CRLF, Unicode, entities, escapes, nested lists,
  tables, and literal fallback.
- Typography construction leaves canonical source unchanged.

### Attribute tests

Inspect exact effective values at representative ranges:

- body font/size and paragraph leading;
- paragraph and heading spacing;
- all six heading sizes/weights;
- list first-line/head indentation at depths 0–4;
- task item has a checkbox and no ordinary bullet;
- quote inset/rule metadata;
- inline/code-block font and background;
- table header/border/padding;
- thematic separator descriptor;
- image bounds/aspect ratio;
- raw HTML literal style.

### Geometry tests

Directly construct AppKit text components—no UI automation—at narrow, 720-point, and wide widths:

- reading measure never exceeds 720 points;
- minimum insets hold where physically possible;
- no horizontal clipping for fixture content;
- wrapped list continuation aligns with its body;
- nested list indentation is cumulative;
- image fits the measure;
- table remains within its container or uses an explicitly tested native overflow behavior.

### Appearance and accessibility

- Resolve adaptive attributes under Light and Dark appearances.
- Verify contrast is not the only semantic distinction.
- Verify task/image/separator roles and labels.

## Performance

Record Release construction time for the approved 100k corpus separately from parse/projection.
This increment does not claim the final native-input budget because it may still perform complete
storage replacement. Preserve measurements as baseline input for COR-20.

## Failure and rollback

- If block decoration requires custom drawing, confine it to a narrow AppKit adapter keyed by
  semantic block identity; do not fork text storage or coordinates.
- If a table cannot satisfy bounded measure through `NSTextTable`, preserve correctness and
  return with measured options; do not silently switch text engines.
- Unsupported style application falls back to readable literal text without changing source.
- The old and new attributed builders may coexist only inside the branch while tests are being
  migrated; the merged result has one builder.

## Conformance and completion gates

- `rg "RichTextBuilder|PlaceholderAttachmentCell\\(text: \"——"` returns no production result.
- `ProjectionCompiler` imports no AppKit.
- Only `MarkdownTypography` defines approved numeric typography tokens.
- ARC-Q14 and ARC-Q15 proofs pass.
- Full Debug/Release tests, documentation/instrumentation gates, smoke, and screenshot review pass.
- Separate-agent review, last-10-PR triage, stale-work sweep, and artifact cleanup pass.
- Reconcile REQ-105–107 to `Done` only after proof; delete this plan.
