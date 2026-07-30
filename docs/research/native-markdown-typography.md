# Native Markdown typography evidence

- **Authority:** Evidence only; `../VISION.md`, `../ENGINEERING.md`, and
  `../REQUIREMENTS.md` are authoritative.
- **First researched:** 2026-07-30
- **Last verified:** 2026-07-30
- **Environment:** macOS 27 SDK, AppKit `NSTextView`/TextKit, arm64 Apple silicon
- **Refresh when:** the typography tokens, text engine, deployment target, supported Markdown
  dialect, table representation, or screenshot fixture changes

## Questions

- What makes delimiter-free Markdown read as semantic writing rather than uniformly styled text?
- Which spacing and indentation can AppKit express without inserting characters or changing
  source coordinates?
- How should CommonMark soft breaks, hard breaks, and paragraph boundaries differ?
- Which typography properties require geometry proof rather than a screenshot alone?
- Does the design require TextKit 2?

## Method

- Inspected the current semantic projection, attributed builder, text-container geometry, toolbar,
  and rich smoke screenshot.
- Added a high-information fixture covering two paragraphs, soft and hard breaks, headings,
  inline styles, image, nested and task lists, blockquote, code, table, thematic break, and raw
  HTML.
- Captured and reviewed the app's own 720-point-wide window in Dark appearance.
- Compared current output with CommonMark line-break semantics and current Apple typography,
  paragraph-style, `NSTextView`, and toolbar guidance.
- Inspected current AppKit APIs for paragraph spacing, spacing before, line height, hanging
  indentation, table blocks, text-container padding, attachments, and native toolbar validation.

## Evidence

### Markdown structure must drive layout

The reviewed presentation applies fonts and colors to inline runs but supplies no general
paragraph style. Consequently paragraphs touch, headings have no relational spacing, nested
lists flatten, blockquotes depend only on color, code has no block padding, and a thematic break
looks like a small attachment pill.

The correct boundary is semantic:

1. cmark and the concrete source index identify inline and block meaning;
2. projection compilation preserves that meaning plus exact coordinates;
3. immutable typography tokens map meaning to attributed presentation and geometry; and
4. TextKit applies the resulting complete presentation or validated local patch.

Font/color selection inside the parser or coordinate compiler would join unrelated concerns.
Inserting extra newlines for spacing would corrupt rendered/source mapping. Paragraph attributes
are the native representation.

### Break semantics

CommonMark defines a soft line break as a source line ending that does not end the paragraph. A
renderer may render it as a line ending or a space. A hard line break is semantically distinct
and renders as a forced break. For a prose-oriented WYSIWYG editor:

- soft break → one presentation space in the same paragraph;
- hard break → one hard-line-break atom and visible newline; and
- blank-line paragraph boundary → paragraph spacing.

The source editor continues to show every literal line ending and trailing marker. The WYSIWYG
choice is presentation only.

Sources:

- [CommonMark 0.31.2 soft line breaks](https://spec.commonmark.org/0.31.2/#soft-line-breaks)
- [CommonMark 0.31.2 hard line breaks](https://spec.commonmark.org/0.31.2/#hard-line-breaks)

### Native paragraph and container APIs are sufficient

`NSMutableParagraphStyle` provides line spacing, line-height multiple, paragraph spacing, spacing
before, first-line/head/tail indentation, tabs, and text blocks. `NSTextView` supplies default
paragraph style, native input, marked text, selection, accessibility, spelling, and Find.
`NSTextContainer` geometry plus surrounding layout can enforce a centered maximum reading measure
without changing the string.

Sources:

- [Apple `NSMutableParagraphStyle`](https://developer.apple.com/documentation/foundation/nsmutableparagraphstyle)
- [Apple `NSTextView`](https://developer.apple.com/documentation/appkit/nstextview)
- [Apple typography guidance](https://developer.apple.com/design/human-interface-guidelines/typography)

### Approved editorial-density default

The selected default balances the app's “came with macOS” objective with sustained document
reading:

| Element | Approved default |
| --- | --- |
| Body | 15-point system font |
| Leading | approximately 1.35× |
| Reading measure | maximum 720 points |
| Insets | minimum 28 horizontal / 20 vertical points |
| Paragraph spacing | approximately 0.7 em |
| Headings | 30, 24, 20, 17, 15, and 13 points; semibold; more space before than after |
| List nesting | 24 points per level with hanging marker |
| Quote | 3-point leading rule and 16–18-point inset |
| Code | approximately 0.93-em monospaced inline; padded adaptive block |

Alternatives considered:

- **Compact native:** 13-point body and tighter measure. Rejected because the screenshot already
  reads as dense application chrome rather than a writing surface.
- **Roomy long-form:** 16-point body, 1.45× leading, and narrower measure. Rejected as too
  prescriptive for the only default and costly in a small document window.
- **User-configurable themes now:** deferred. One correct adaptive default is required before
  exposing a setting matrix.

### Toolbar is part of typography quality

The current formatting `HStack` consumes document space and truncates controls at the default
window width. A native `NSToolbar` provides window integration, overflow, customization,
validation, and menu-form representation. Every command must also exist in the menu bar so the
toolbar is optional chrome rather than the sole interaction route.

Sources:

- [Apple `NSToolbar`](https://developer.apple.com/documentation/appkit/nstoolbar)
- [Apple toolbar item validation](https://developer.apple.com/documentation/appkit/nstoolbaritemvalidation)
- [Apple toolbar guidance](https://developer.apple.com/design/human-interface-guidelines/toolbars)

## Verification implications

A screenshot is useful oversight but cannot be the automated proof. Component tests must inspect:

- exact rendered soft/hard/paragraph strings;
- paragraph style values for semantic ranges;
- heading hierarchy and spacing;
- hanging indentation and cumulative list nesting;
- absence of a bullet before a task checkbox;
- quote/code/table block metadata;
- reading measure and insets at narrow, default, and wide constructed widths;
- image aspect ratio and maximum width;
- adaptive colors in Light and Dark appearances;
- accessibility roles/labels that do not depend on appearance; and
- unchanged canonical source and coordinate-oracle validity.

The one required screenshot remains a final broad visual review for clipping, density, balance,
and defects that semantic assertions did not anticipate.

## Durable conclusions

- Typography is a semantic presentation subsystem, not a parser concern or source transformation.
- Encode spacing with paragraph/block attributes, never synthetic blank lines.
- Render soft breaks as spaces and hard breaks as forced line breaks.
- Use one approved adaptive editorial default before adding theme settings.
- Keep TextKit 1 for this rewrite; typography does not itself justify a text-engine migration.
- Use a native window toolbar and menu parity so formatting chrome cannot compress the document.
