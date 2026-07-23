# PLAN-0002 — INC-02 Markdown engine + live-styled source

- **Increment:** INC-02
- **Date:** 2026-07-22
- **Status:** Approved
- **Requirements:** REQ-040…046; reconcile REQ-010/011/012
- **Depends on:** [RESEARCH-0003](../research/0003-editor-performance-and-concurrency.md),
  [ADR-0008](../decisions/0008-textkit1-nstextview-editor-engine.md) (TextKit 1),
  [ADR-0009](../decisions/0009-regex-live-highlighting-engine.md) (regex),
  [ADR-0010](../decisions/0010-concurrency-highlighting-pipeline.md) (pipeline)

## Goal

Replace the interim `TextEditor` with a TextKit 1 `NSTextView` that live-styles the raw Markdown
as the user types — GFM core + light Tier-2 — with imperceptible latency, plus a word/char count
and find & replace. Styling uses display attributes only, so the file bytes never change (INV-2).

## Approach (per ADR-0010)

- **`MarkdownTextView`** — `NSViewRepresentable` wrapping `NSScrollView` + `NSTextView(usingTextLayoutManager: false)`.
  `Coordinator` is the `NSTextViewDelegate`, holds the `Binding<String>`, and guards update loops
  (programmatic-update flag + compare-before-set). Enables the find bar (`usesFindBar`) and
  spell-check. Replaces `TextEditor` in `ContentView`.
- **`TokenStyle`** — a `Sendable` enum of styleable element kinds (heading1…6, bold, italic,
  inlineCode, codeBlock, link, image, listMarker, taskMarker, blockquote, table, strikethrough,
  thematicBreak, footnote, highlight, superscript, subscript).
- **`MarkdownHighlighter`** — an `actor` holding once-compiled `NSRegularExpression`s;
  `func tokens(for text: String, version: Int) -> HighlightPass` returning `[(NSRange, TokenStyle)]`.
  Pure, `Sendable` in/out. (Testable seam.)
- **Pipeline** — `textDidChange` → bump `version` → `Task { await highlighter.tokens(...) }` →
  `@MainActor` → drop if stale → apply `NSTextStorage` attributes (display-only; string unchanged)
  for each token. Debounced; size threshold caps live styling for very large files.
- **`MarkdownTheme`** — maps `TokenStyle` → attributes (font/size/weight, color), light/dark aware;
  dims syntax markers.
- **Counts** — `word`/`character` counts from the text (computed off-main for large docs), shown
  in a status bar.

## Steps

1. `TokenStyle` + `MarkdownTheme`. → REQ-041/042/043 · *tests:* theme returns attributes per style.
2. `MarkdownHighlighter` actor + compiled regex patterns for GFM core + light Tier-2. → REQ-041/042/043
   · *tests:* given source, tokens cover the expected ranges/kinds (pure-function tests).
3. `MarkdownTextView` (`NSViewRepresentable` + `Coordinator`), TextKit 1, binding-safe. → REQ-010/011/012
   re-point; REQ-046 find bar · *verify:* `inherent` (NSTextView) + binding tests where feasible.
4. Wire the coalesced pipeline (version + debounce + size threshold) applying `NSTextStorage` attributes.
   → REQ-040/045 · *tests:* highlighting leaves `text` byte-identical (INV-2); stale versions dropped.
5. Word/char count in a status bar. → REQ-044 · *tests:* counts for sample inputs.
6. Replace `TextEditor` with `MarkdownTextView` in `ContentView`.

## Testing

Unit-test the pure pieces: `MarkdownHighlighter.tokens` (ranges/kinds per element), `MarkdownTheme`
(style→attributes), counts, and the INV-2 guarantee (apply a pass, assert the document string is
unchanged) and version-coalescing logic. The `NSViewRepresentable` glue stays thin; its
framework behaviors (editing/undo/spell-check/find) are `inherent`.

## Risks / open questions

- `NSViewRepresentable` update loops (guarded per ADR-0010) — watch for double `updateNSView`.
- Regex correctness on nested/edge constructs — cover with targeted tests; accept lexical limits
  (ADR-0009).
- Large-file threshold value — tune; start conservative.

## Out of scope

In-fence language coloring, images (INC-03), WYSIWYG (INC-04), remaining Tier-2 (definition lists,
emoji, heading anchors), `swift-markdown` structured rendering.
