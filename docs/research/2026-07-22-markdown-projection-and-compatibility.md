# Markdown projection and compatibility evidence

- **Authority:** Evidence only; `../vision.md` and `../architecture.md` are authoritative.
- **First researched:** 2026-07-22
- **Last verified:** 2026-07-25
- **Pinned parser:** `swift-cmark` `5d9bdaa4228b381639fff09403e39a04926e2dbe`,
  containing cmark-gfm 0.29.0.gfm.13
- **Refresh when:** parser revision, supported dialect, projection representation, or generated
  Markdown policy changes

## Questions

- Which named Markdown dialect is executable without maintaining a private parser fork?
- What source information does cmark provide?
- Which rendered representations can be edited without normalizing unrelated source?

## Methods

- Ran the cmark-gfm bundled specification, selected extension fixtures, official CommonMark
  0.31.2 fixtures, and the pathological suite.
- Compared direct cmark-gfm, `swift-markdown`, upstream cmark, and tree-sitter candidates.
- Built a UTF-8/Swift-index/UTF-16 source index and exercised ASCII, multibyte, emoji,
  composed/decomposed Unicode, BOM, LF/CRLF, tabs, links, delimiters, code, tables, and malformed
  syntax.
- Built throwaway delimiter-free TextKit 1 projection and semantic-edit POCs.
- Probed entity, numeric-reference, escape, list, task, code, and table source positions.

## Dialect findings

Formal GFM 0.29 is one coherent executable dialect. Direct cmark-gfm with smart punctuation
disabled and exactly table, strikethrough, autolink, task-list, and tag-filter extensions enabled
produced:

| Suite | Result |
| --- | --- |
| Complete cmark-gfm bundled specification | 670 passed, 0 failed |
| Pathological suite | 21 passed, 0 errored, 0 ignored |
| Official CommonMark 0.31.2 suite | 641 passed, 11 failed |

The CommonMark failures reflect genuine version differences in numeric references and
emphasis/strong behavior. Combining CommonMark 0.31.2 with formal GFM 0.29 would be a house dialect
requiring a large private parser fork. `swift-markdown` embeds the same older cmark core and
changes extension/options behavior; it is not a more conforming authority.

Formal GFM requires double-tilde strikethrough. Focused fixtures render `~single~` literally and
`~~double~~` as strikethrough.

Sources:

- [GitHub Flavored Markdown 0.29-gfm](https://github.github.com/gfm/)
- [cmark-gfm](https://github.com/github/cmark-gfm)
- [Pinned swift-cmark](https://github.com/swiftlang/swift-cmark/tree/5d9bdaa4228b381639fff09403e39a04926e2dbe)
- [CommonMark 0.31.2](https://spec.commonmark.org/0.31.2/)
- [RFC 7763 Markdown variants](https://www.rfc-editor.org/rfc/rfc7763.html#section-2)

## Source-position findings

cmark reports one-based UTF-8 source positions. The source-index POC mapped them to absolute
UTF-8, Swift `String.Index`, and TextKit UTF-16 ranges across the fixture matrix.

Positions are necessary but not a complete editable projection:

- parser literals may normalize entity spelling, escapes, code content, or line endings;
- omitted delimiters and synthetic presentation create additional caret boundaries;
- the table delimiter/alignment row has no semantic node;
- repeated rendered text cannot identify a source occurrence; and
- a semantic node span alone does not define every legal insertion affinity.

The 2026-07-25 entity probe confirmed source positions remain available when the rendered literal
differs from the concrete source. CommonMark specifies entity and numeric-reference normalization;
the inverse layer must use the pinned concrete parsing rules rather than identity mapping or an
application-specific escape table.

Sources:

- [cmark-gfm source-position API](https://github.com/github/cmark-gfm/blob/master/src/cmark-gfm.h)
- [GFM entity and numeric references](https://github.github.com/gfm/#entity-and-numeric-character-references)

## Projection findings

A separate attributed TextKit storage containing rendered content only is viable. POCs proved
attributes for headings, emphasis, strong, strikethrough, inline code, and links; attachment
characters for tasks/images; literal fallback for unsupported/malformed syntax and raw HTML; and
native table blocks.

The inverse-edit contract must classify each presented atom as:

- identity source;
- atomic source representation with a concrete decoder and encoder;
- synthetic presentation with an insertion policy; or
- uneditable.

Proportional mapping, endpoint clamping, and whole-document serialization are invalid. Exact local
source patching is viable for inline content, formatting, links, task markers, image descriptions,
and many block prefixes. Table structure requires table scope; the MVP edits cell content only.

## WYSIWYG literal-input finding

Visible punctuation typed in WYSIWYG is content, not a formatting gesture. Because Markdown
punctuation can become syntax depending on context, source insertion may need an escape or entity
while WYSIWYG continues to show the literal character.

The correct operation is therefore:

1. classify the exact semantic/source context;
2. derive the minimal formal-GFM source spelling for the intended literal;
3. patch source and presentation atomically; and
4. reparse to validate the postcondition.

If the inverse cannot be proven, refuse before mutation. Formatting remains a separate semantic
command.

## Durable conclusions

- Pin direct cmark-gfm and run its complete specification on dependency changes.
- Keep literal source and delimiter-free presentation as different representations of one
  canonical Markdown document.
- Require exact concrete-source inverse rules before declaring rendered content editable.
- Preserve unknown source and refuse ambiguous edits rather than normalize or guess.
