# ADR-0013 — Source-backed rich projection and semantic edits

- **Status:** Accepted
- **Date:** 2026-07-25
- **Deciders:** Toni Melisma
- **Related:** INC-04; REQ-052–REQ-059, REQ-078–REQ-087;
  [RESEARCH-0007](../research/0007-document-model-and-wysiwyg-architecture.md);
  [ADR-0003](0003-markdown-dialect-commonmark-and-formal-gfm.md);
  [ADR-0008](0008-textkit1-nstextview-editor-engine.md);
  [ADR-0012](0012-transactional-descriptor-relative-image-placement.md)

## Context

The product requires two genuinely editable modes over one ordinary Markdown file. Source must
show literal Markdown. WYSIWYG must contain rendered characters and attachments rather than
hidden Markdown delimiters. Unknown syntax and untouched source spelling must survive edits.

One attributed storage cannot safely be both literal source and delimiter-free rich content:
glyph suppression or transparent source characters break caret movement, selection, IME,
accessibility, and attachments. Making rich text or an AST canonical would normalize entire files
and discard unfamiliar syntax. A web editor would replace native macOS input/undo/accessibility
with an HTML conversion boundary.

SPIKE-02 proved TextKit 1 rich storage, UTF-8/Swift/UTF-16 source mapping, local source
transactions, cross-mode undo, persistent mode state, task/link/image interaction, table blocks,
and editor-neutral COR-02 insertion without UI automation.

## Decision

Use **one canonical Markdown source plus two persistent TextKit 1 editor projections**:

1. `NSDocument` owns the only serialized source, monotonically increasing source version, source
   transaction engine, and `UndoManager`.
2. Source mode remains the current literal, lexically styled TextKit 1 editor.
3. WYSIWYG uses a separate attributed storage containing rendered content and attachments only.
   Parsed control characters do not exist in that storage.
4. A `Sendable` parse/projection snapshot carries semantic node identifiers, source spans,
   projection spans, insertion anchors, attachment descriptors, and the exact source version.
5. Parsing, source indexing, projection-model construction, and image decoding occur off-main.
   AppKit attributed objects are constructed/applied on the main actor only when versions match.
6. Every edit becomes one typed source transaction or a typed refusal. Views never write each
   other and never serialize the whole rich document.
7. Exact source spelling is preserved when a safe patch exists. Otherwise only the smallest
   semantic unit is regenerated: inline node, block, or table—never the whole document.
8. Unsupported syntax and raw HTML appear literally, unformatted, editable, preserved, and
   non-executing in WYSIWYG.
9. Rich clipboard representations paste as plain text for MVP. Rich-to-Markdown conversion is a
   separate later feature.
10. Existing GFM tables render and permit cell-content edits. Table insertion and structural
    row/column controls are deferred.
11. The same semantic formatting toolbar is present in Source and WYSIWYG. An unsafe or ambiguous
    command is disabled or returns a typed refusal.
12. “Add Image…” joins paste and drag-and-drop as another entry into COR-02's single placement
    transaction. It is not document Import. File-backed HEIC/HEIF remains exact-copy and is never
    converted to JPEG.

## Consequences

- **Positive:** one ordinary Markdown source remains authoritative; mode switching cannot rewrite
  it; unknown syntax and untouched spelling survive.
- **Positive:** each mode keeps native TextKit selection, IME, spelling, Find, undo, keyboard, and
  accessibility behavior.
- **Positive:** source transactions, undo, parser versions, and image insertion have one
  document-owned correctness boundary.
- **Cost:** the app owns projection/source mapping and semantic edit translation.
- **Cost:** some structural commands rewrite one complete table or block, and some ambiguous
  edits must be refused rather than guessed.
- **Cost:** the rich storage is derived state and must be rebuilt/version-gated after source
  changes.

## Alternatives considered

- **AST or attributed text as canonical:** rejected because Save would normalize whole documents
  and could discard unknown syntax.
- **One literal storage with hidden delimiters:** rejected because character/glyph disagreement
  compromises editing and accessibility.
- **Web view/contenteditable:** rejected because HTML conversion, non-native behavior, and a
  second document model work against the product.
- **Whole-document Markdown serialization after rich edits:** rejected by source fidelity and
  minimum-normalization requirements.
