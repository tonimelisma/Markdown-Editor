# ADR-0009 — Live source highlighting is lexical regex

- **Status:** Accepted
- **Date:** 2026-07-22
- **Deciders:** Toni Melisma
- **Related:** [ADR-0003](0003-markdown-dialect-commonmark-and-formal-gfm.md) (dialect),
  [ADR-0008](0008-textkit1-nstextview-editor-engine.md) (TextKit 1),
  [ADR-0010](0010-concurrency-highlighting-pipeline.md); [RESEARCH-0003](../research/0003-editor-performance-and-concurrency.md); INC-02

## Context

The live-styled source editor must style Markdown *as the user types*. Two mechanisms:
`swift-markdown`'s GFM AST, or regex. From [RESEARCH-0003](../research/0003-editor-performance-and-concurrency.md):
`swift-markdown`'s `SourceRange` is UTF-8 line/column and converting it to `NSRange` is fiddly/WIP,
it re-parses the whole document. Regex-based highlighting works natively on `NSRange` and is
cheap to run off-main.

## Decision

Use **compiled `NSRegularExpression` patterns** for live source highlighting. This is a lexical
presentation aid, not the product's Markdown parser and not evidence of formal conformance.
Patterns should approximate the supported CommonMark/GFM constructs without rewriting source.

No structural parser has yet been selected for WYSIWYG. `swift-markdown`, `cmark-gfm`, and other
options must be evaluated against [ADR-0003](0003-markdown-dialect-commonmark-and-formal-gfm.md)
when semantic rendering is planned.

## Consequences

- **Positive:** native `NSRange` (no UTF-8 offset translation), fast, off-main-thread friendly;
  no dependency added in INC-02.
- **Negative / costs:** regex is lexical, not grammatical — it can mis-handle deeply nested or
  pathological constructs. Tests prove bounded styling behavior, not Markdown parsing.
  In-fence language coloring is out of scope.
- **Correction:** COR-01 removed the extension claims introduced in INC-02 and aligned tilde
  styling with formal GFM (REQ-047–REQ-051).
- **Revisit trigger:** if precision/nesting becomes a problem, or for in-fence language coloring,
  evaluate tree-sitter-markdown (+ ChimeHQ Neon); update or supersede this ADR then.

## Alternatives considered

- **swift-markdown AST-driven highlighting:** rejected for live editing in INC-02 because of
  UTF-8→NSRange friction and full-document reparsing; it is not preselected for WYSIWYG.
- **Hybrid (AST blocks + regex inline):** rejected as premature complexity (two mechanisms to
  keep in sync).
