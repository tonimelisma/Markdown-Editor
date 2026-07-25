# ADR-0013 — Source-backed rich projection and semantic edits

- **Status:** Accepted; implementation correction approved
- **Date:** 2026-07-25
- **Deciders:** Toni Melisma
- **Related:** INC-04; COR-05/06/07; REQ-052–REQ-059, REQ-078–REQ-090;
  [RESEARCH-0007](../research/0007-document-model-and-wysiwyg-architecture.md);
  [RESEARCH-0008](../research/0008-inc04-correction-architecture-review.md);
  [PLAN-0010](../plans/0010-inc04-correction-program.md);
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

SPIKE-02 proved that TextKit 1 rich storage, native attachments/tables, source-backed edits, and
an editor-neutral COR-02 boundary are viable. The first INC-04 implementation then disproved that
its concrete transaction, mapping, host, interaction, and verification implementations were
adequate: source positions were distributed heuristically, invalid rich selections were clamped,
undo captured stale versions, inactive views were destroyed, and several native behaviors were
claimed without discriminating evidence. RESEARCH-0008 records the reproduced failures.

## Decision

Use **one canonical Markdown source plus two persistent TextKit 1 editor projections**:

1. `NSDocument` owns the only serialized source, monotonically increasing source version, source
   transaction engine, and `UndoManager`.
2. Source mode remains the current literal, lexically styled TextKit 1 editor.
3. WYSIWYG uses a separate attributed storage containing rendered content and attachments only.
   Parsed control characters do not exist in that storage.
4. A `Sendable` parse/projection snapshot carries semantic node identifiers, exact source-backed
   segments, explicitly synthetic segments and insertion policies, literal-fallback segments,
   attachment descriptors, and the exact source version. Every rich boundary maps exactly or
   returns a typed refusal; it is never clamped, proportionally distributed, or guessed.
5. Parsing, source indexing, projection-model construction, and image decoding occur off-main.
   AppKit attributed objects are constructed/applied on the main actor only when versions match.
6. Every edit becomes one content-validated typed source mutation or a typed refusal. Undo/redo
   registers the inverse dynamically against current content rather than capturing a historical
   expected version. Views never write each other and never serialize the whole rich document.
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
13. One window-scoped AppKit host owns both TextKit 1 views for its lifetime. Mode changes switch
    visibility/focus and restore mode-local selection, affinity, and scroll state.
14. `NSTextView` owns transient marked text. WYSIWYG commits one completed composition through the
    source mutation engine and never replaces storage during marked text.
15. Document actions are injected per window. No process-wide notification routes Add Image or
    another document-specific command.
16. File-backed local image display validates actual UTI and returns a bounded off-main `CGImage`
    without encoding an intermediate PNG or JPEG; cache cost is bounded.
17. Architectural claims are accepted through privacy-safe traces, typed invariant oracles,
    focused tests, construction proofs, or reproducible measurements. Instrumentation never
    records user content or complete paths.

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
- **Constraint:** a failed mapping or performance proof blocks delivery; implementation cannot
  weaken a gate or substitute a manual/UI test.

## Alternatives considered

- **AST or attributed text as canonical:** rejected because Save would normalize whole documents
  and could discard unknown syntax.
- **One literal storage with hidden delimiters:** rejected because character/glyph disagreement
  compromises editing and accessibility.
- **Web view/contenteditable:** rejected because HTML conversion, non-native behavior, and a
  second document model work against the product.
- **Whole-document Markdown serialization after rich edits:** rejected by source fidelity and
  minimum-normalization requirements.
