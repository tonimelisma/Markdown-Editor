# COR-76 — Formal-GFM and Source contract

- **Status:** Approved; not implemented
- **Delivers:** REQ-047, REQ-048, REQ-049, REQ-050, REQ-053, REQ-054, REQ-055, REQ-056, REQ-059
Architecture impact: none; preserves formal GFM 0.29-gfm as the sole MVP dialect
Blockers: COR-68, COR-72
Executor: A junior may implement the declared fixture matrix. Any proposal to add syntax or change the dialect requires separate discovery and approval.

## Scope and files

Own the dialect at parser/highlighter/projection boundaries: `CMarkGFM.swift`, parser options and
extensions, `MarkdownHighlighter`, `ProjectionCompiler`, `MarkdownLiteralEncoder`, source-index
mapping, and formal-GFM fixtures. Do not add writing extensions, rich paste, table controls, or
language-aware fence coloring.

## Implementation

1. Vendor or generate a traceable fixture manifest from the pinned CommonMark/GFM version, naming
   each supported core/extension class and unsupported extension spelling.
2. Through production parser and highlighter routes, prove double-tilde strikethrough; single tilde;
   footnote/highlight/super/subscript spellings; focused image destinations; tables; task lists;
   autolinks; raw HTML; code spans/fences; escapes; entities; CRLF; and Unicode.
3. Add exact source-range/byte-range round trips for each fixture. Parsed semantics, source styling,
   projection mapping, and literal encoding must agree or refuse—never guess.
4. Add a closed parser-extension declaration and a project conformance test. A newly enabled cmark
   extension or parser option fails until requirements and fixtures are approved.
5. Fix mismatches in the narrowest shared owner and delete duplicate regex/line scanners.

## Proof and failure behavior

- Ordinary supported examples succeed through parser→index→projection/highlighter routes.
- Unsupported writing extensions preserve exact text and gain no supported semantics.
- Invalid/malformed examples remain bounded and unchanged; all ranges stay inside source.
- Differential renderer checks normalize only where the formal contract permits and retain original
  spelling through the source fidelity layer.
- A mutation disabling one formal extension or enabling one unsupported extension turns a named
  proof red.

## Deletion/conformance gate

Only one production declaration enables the pinned five formal GFM extensions. No secondary Markdown
scanner or unapproved syntax branch remains. Requirements are promoted individually, never as one
blanket dialect claim.
