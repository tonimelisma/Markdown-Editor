# PLAN-0002 — INC-02 Markdown engine + live-styled source

- **Increment:** INC-02
- **Date:** 2026-07-22
- **Status:** Implemented — merged via PR #2 (squash `a139213`, 2026-07-22)
- **Requirements:** REQ-040…046; reconcile REQ-010/011/012
- **Depends on:** [RESEARCH-0003](../research/0003-editor-performance-and-concurrency.md),
  [ADR-0008](../decisions/0008-textkit1-nstextview-editor-engine.md) (TextKit 1),
  [ADR-0009](../decisions/0009-regex-live-highlighting-engine.md) (regex),
  [ADR-0010](../decisions/0010-concurrency-highlighting-pipeline.md) (pipeline)

> **Historical scope note (2026-07-22):** this plan accurately records what INC-02 delivered.
> Its “light Tier-2” dialect choice was later found to conflict with formal GFM and is superseded
> by [ADR-0003](../decisions/0003-markdown-dialect-commonmark-and-formal-gfm.md) and
> [PLAN-0004](0004-markdown-dialect-conformance-correction.md). COR-01 removes those semantic
> styling claims; the TextKit, performance, and concurrency design remains current.

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
  `func tokens(for text: String) -> [Token]`. `Token` is a `Sendable` pair of `NSRange` and
  `TokenStyle`, so the computation crosses the actor boundary without AppKit objects.
- **Pipeline** — `textDidChange` → bump `version` → `Task { await highlighter.tokens(...) }` →
  `@MainActor` → drop if stale → apply `NSTextStorage` attributes (display-only; string unchanged)
  for each token. The pipeline debounces for 120 ms and uses a monotonic version plus matching
  text snapshot to discard stale results. Live styling runs for every document size (no
  length-based suspension); superseded work is cancelled via the version gate.
- **`MarkdownTheme`** — maps `TokenStyle` → attributes (font/size/weight, color), light/dark aware;
  distinguishes headings, inline elements, syntax markers, and code blocks; code blocks receive
  a monospaced font and subtle purple tint.
- **Counts** — `word`/`character` counts are computed by a cancellation-aware `TextStatsComputer`
  actor and published into view state for the status bar; the SwiftUI body does not rescan text.

## Steps

1. `TokenStyle` + `MarkdownTheme`. → REQ-041/042/043 · *tests:* theme returns attributes per style.
2. `MarkdownHighlighter` actor + compiled regex patterns for GFM core + light Tier-2. → REQ-041/042/043
   · *tests:* given source, tokens cover the expected ranges/kinds (pure-function tests).
3. `MarkdownTextView` (`NSViewRepresentable` + `Coordinator`), TextKit 1, binding-safe. → REQ-010/011/012
   re-point; REQ-046 find bar · *verify:* `inherent` (NSTextView) + binding tests where feasible.
4. Wire the coalesced pipeline (version + debounce) applying `NSTextStorage` attributes.
   → REQ-040/045 · *tests:* highlighting leaves `text` byte-identical (INV-2); actor-boundary
   count computation verifies the off-main seam. The version/snapshot gate is verified by
   construction in the thin coordinator.
5. Word/char count in a status bar. → REQ-044 · *tests:* counts for sample inputs and actor path.
6. Replace `TextEditor` with `MarkdownTextView` in `ContentView`.

## Testing

The implemented test suite covers token kinds and UTF-16 bounds, both backtick and tilde fenced
blocks with longer closing fences, theme attributes (including the code-block tint), pure and
actor-based counts, and the INV-2 guarantee that applying attributes preserves the string.
The `NSViewRepresentable` glue remains thin; editing, undo, spell-check, and Find & Replace are
framework-provided/inherent. Version/snapshot stale-result rejection is a coordinator guard, not
separately unit-tested UI behavior.

## Risks / open questions

- `NSViewRepresentable` update loops (guarded per ADR-0010) — watch for double `updateNSView`.
- Regex correctness on nested/edge constructs — cover with targeted tests; accept lexical limits
  (ADR-0009).
- Large-document highlight cost — keep debounce + off-main + cancellation; do not reintroduce a
  document-size styling suspension without explicit product approval.

## Out of scope

In-fence language coloring, images (INC-03), and WYSIWYG (INC-04). The former “remaining
Tier-2” list and preselection of `swift-markdown` were subsequently superseded: writing
extensions now require explicit dialect-profile research, and INC-04 must select a structural
parser against the approved formal dialect.
