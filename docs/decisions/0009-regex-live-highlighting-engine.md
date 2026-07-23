# ADR-0009 — Live source highlighting via regex (swift-markdown reserved for rendering)

- **Status:** Accepted
- **Date:** 2026-07-22
- **Deciders:** Toni Melisma
- **Related:** [ADR-0003](0003-markdown-dialect-gfm-plus-writing-extensions.md) (dialect),
  [ADR-0008](0008-textkit1-nstextview-editor-engine.md) (TextKit 1),
  [ADR-0010](0010-concurrency-highlighting-pipeline.md); [RESEARCH-0003](../research/0003-editor-performance-and-concurrency.md); INC-02

## Context

The live-styled source editor must style Markdown *as the user types*. Two mechanisms:
`swift-markdown`'s GFM AST, or regex. From [RESEARCH-0003](../research/0003-editor-performance-and-concurrency.md):
`swift-markdown`'s `SourceRange` is UTF-8 line/column and converting it to `NSRange` is fiddly/WIP,
it's GFM-only (no Tier-2), and it re-parses the whole document. Regex-based highlighting
(Marklight, HighlightedTextEditor) works natively on `NSRange`, is cheap to run off-main, and
extends trivially to our Tier-2 extensions.

## Decision

Use **compiled `NSRegularExpression` patterns** to drive live source highlighting for INC-02's
scope (GFM core + light Tier-2). **`swift-markdown` is reserved for structured rendering later**
(preview / WYSIWYG / export), where fidelity matters more than per-keystroke speed. This does not
override [ADR-0003](0003-markdown-dialect-gfm-plus-writing-extensions.md) — `swift-markdown`
remains the parser for rendering.

## Consequences

- **Positive:** native `NSRange` (no UTF-8 offset translation), fast, off-main-thread friendly,
  Tier-2-extensible; no dependency added in INC-02.
- **Negative / costs:** regex is lexical, not grammatical — it can mis-handle deeply nested or
  pathological constructs; patterns must be written and tested carefully. In-fence *language*
  coloring is out of scope (needs a code-highlighting engine).
- **Revisit trigger:** if precision/nesting becomes a problem, or for in-fence language coloring,
  evaluate tree-sitter-markdown (+ ChimeHQ Neon); update or supersede this ADR then.

## Alternatives considered

- **swift-markdown AST-driven highlighting:** rejected for live editing — UTF-8→NSRange friction,
  GFM-only, full reparse.
- **Hybrid (AST blocks + regex inline):** rejected as premature complexity (two mechanisms to
  keep in sync).
