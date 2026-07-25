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

No structural parser has yet been selected for WYSIWYG. SPIKE-02 evaluated `swift-markdown` and
direct cmark-gfm. Direct cmark-gfm supplies usable source positions and implements coherent formal
GFM 0.29, but it fails 11 CommonMark 0.31.2 cases and therefore does not implement ADR-0003's
hybrid label. Parser selection is blocked on the user's dialect decision.

## Consequences

- **Positive:** native `NSRange` (no UTF-8 offset translation), fast, off-main-thread friendly;
  no dependency added in INC-02.
- **Negative / costs:** regex is lexical, not grammatical — it can mis-handle deeply nested or
  pathological constructs. Tests prove bounded styling behavior, not Markdown parsing.
  In-fence language coloring is out of scope.
- **Correction:** COR-01 removed the extension claims introduced in INC-02 and aligned tilde
  styling with formal GFM (REQ-047–REQ-051).
- **Revisit trigger:** if precision/nesting becomes a problem in Source mode, investigate an
  incremental highlighting engine without treating it as the semantic parser. The
  tree-sitter-markdown maintainers explicitly warn against correctness-sensitive use, so it is
  not a WYSIWYG semantic-authority candidate. SPIKE-02 found direct cmark-gfm technically suitable
  if the accepted dialect becomes coherent formal GFM 0.29.

## Alternatives considered

- **swift-markdown AST-driven highlighting:** rejected for live editing in INC-02 because of
  UTF-8→NSRange friction and full-document reparsing. SPIKE-02 also found its default extension
  configuration is not the complete formal-GFM set; it is not the WYSIWYG semantic authority.
- **Hybrid (AST blocks + regex inline):** rejected as premature complexity (two mechanisms to
  keep in sync).
