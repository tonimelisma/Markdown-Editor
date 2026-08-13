# COR-72 — Incremental Source pipeline

- **Status:** Approved; not implemented
- **Delivers:** REQ-040, REQ-041, REQ-043, REQ-045
Architecture impact: none; preserves Source as a real persistent native editor
Blockers: COR-69
Executor: A junior developer may implement this plan in order. Obtain senior review of incoming/outgoing lexer state and stabilization rules before migrating token cases.

## Outcome

Replace whole-document retokenization and repeated fence scans with a stateful per-line lexer. An
edit invalidates the touched lines, propagates forward until outgoing state stabilizes, computes off
main, and applies only changed attributes for the same source revision.

## Files and ownership

- Add `SourceLexState.swift`, `SourceLineIndex.swift`, `IncrementalSourceHighlighter.swift`, and
  immutable `SourceHighlightPatch`.
- Refactor `MarkdownHighlighter` token rules into state transitions with closed `SourceTokenKind`.
- Modify `SourceEditor.Coordinator` to submit immutable edit deltas and apply bounded patches.
- Delete whole-document fence pre-scans, main-actor tokenization, and debounce tasks that retain
  superseded full source copies.

## Implementation

1. Characterize every REQ-041 construct plus CRLF, Unicode, nested delimiters, multiline fences,
   tables, malformed/incomplete syntax, and edits that open/close a fence.
2. Maintain line starts and incoming/outgoing lexical state. Relex from the first affected line;
   stop only when both tokens and outgoing state match the prior cache.
3. Run lexing off main with source revision and cancellation. Keep only newest pending demand.
4. On main, validate document/session/revision identity and apply attributes only over changed line
   ranges without changing string, selection, undo, or scroll.
5. Record lexed lines/UTF-16, applied characters, cancellation, compute duration, apply duration, and
   intent identity. Establish Release budgets on every corpus shape.

## Proof and failure behavior

- Differential property tests compare incremental tokens with a fresh full lex after generated edit
  sequences. The full lexer exists only in tests/reference code, not the production typing route.
- Opening and closing fences propagates exactly as far as state changes; a local paragraph edit does
  not scan or restyle the document tail.
- Superseded work and stale patches apply nothing; bounds are exact for CRLF/Unicode; source bytes,
  selection, undo, and scroll remain unchanged.
- Release tests report nonzero samples and p95 budgets for compute and apply on all corpus shapes.

## Deletion/conformance gate

No production path performs whole-source tokenization or two independent fence scans after an
ordinary edit. A closed token/state matrix fails when a new construct lacks incremental behavior.
