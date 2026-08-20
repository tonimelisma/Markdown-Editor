# COR-71 — Bounded WYSIWYG input

- **Status:** Approved; not implemented
- **Delivers:** REQ-090, REQ-091, REQ-092
Architecture impact: none; preserves synchronous ARC-005 while removing full parse/compile work from ordinary input
Blockers: COR-69, COR-70
Executor: A junior developer may execute the Stage 0 table and implement only the mechanically selected branch. Obtain senior review of the local-transition class table before production code.

## Stage 0 findings and selected branches

The throwaway probe recorded in
`docs/research/COR-71-stage0-local-transition-probe.md` selected every branch in the decision
table. The production class table is now closed as follows:

| Class | Branch |
| --- | --- |
| punctuation, delimiter edits, line-start markers, escapes | local transition |
| raw HTML literal spans, code spans, fenced code content, IME commit | local transition |
| nested quote/list | bounded enclosing-block oracle |
| soft/hard breaks, list continuation, table cells, and any unlisted class | synchronous refusal |

The local branch is intentionally conservative: it accepts only the exact identity/atomic spans
returned by the existing coordinate map and literal encoder. The bounded branch reparses only the
declared enclosing block and compares its complete result with the current authoritative snapshot.
The refusal branch leaves canonical source unchanged and keeps Source available. A class added to
the enum or probe matrix without one of these assignments fails the structural matrix.

## Outcome

An ordinary WYSIWYG keystroke performs a bounded local source/encoder transition and applies one
bounded presentation patch before returning. Full cmark parse/index/projection remains the async
authority and reconciles only after identity checks.

## Stage 0 decision probe

Build throwaway probes for: delimiter insertion/removal; line-start markers; escapes; soft/hard
breaks; list continuation; nested quotes/lists; table cells; raw HTML; code spans/fences; and IME.
For each, compare the local encoder result with the next authoritative snapshot.

| Observed outcome | Branch |
| --- | --- |
| Local transition is exact for a declared atom/block class | Add that class to `LocalTransitionDomain` |
| Exactness requires a bounded enclosing block reparse with the pinned parser | Add `BoundedBlockParser` for that declared class |
| Neither exact branch is provable | Refuse that class synchronously and leave it Source-editable |
| An outcome is not covered above | Stop; return to discovery without production code |

Commit findings to `docs/research/`, delete POC code, and rewrite the remaining class table before
production implementation.

## Files and ownership

- Add `LocalTransitionDomain.swift` and, only if selected, `BoundedBlockParser.swift`.
- Modify `EditorTransactionKernel`, `MarkdownLiteralEncoder`, `PresentationTransition`,
  `TextStorageApplier`, `EditorSession`, and `ParseCoordinator`.
- Delete `EditorSemanticWorker.sync`/whole-document `ProjectionCompiler` calls from the ordinary
  native-input route. Retain full authority only in background reconciliation and explicit recovery.

## Implementation

1. Encode the Stage 0 class table as a closed enum; a new atom/block case fails compilation or its
   structural matrix until assigned local, bounded-reparse, or refusal behavior.
2. Produce source replacement, next complete presentation snapshot, coordinate map, selection, and
   attributed patch from the same accepted transaction.
3. Schedule one coalesced authoritative parse after commit. Apply only matching source revision,
   location generation, projection identity, and active session.
4. On authoritative disagreement, record a fault, make WYSIWYG unavailable, keep Source available,
   and rebuild from canonical source; never silently patch over the mismatch.
5. Measure callback, attributed writes, parse/compile/oracle counts, and main-thread blocked time per
   intent on every approved corpus shape.

## Proof and failure behavior

- Closed structural matrices prove ordinary insertion/deletion, punctuation, Unicode, selections,
  block boundaries, tables, IME commit/cancel, undo/redo, and every refusal class.
- One ordinary input records zero full-document parses/compiles on the callback path, one bounded
  storage edit, no full replacement, and p95 under the REQ-090 budget in Release.
- Rapid input remains live while authoritative parsing is deliberately blocked; stale results apply
  nothing; the final result equals a fresh authoritative build.

## Deletion/conformance gate

No semaphore, synchronous whole-document cmark parse, whole projection compile, or full attributed
replacement is reachable from ordinary native input. Explicit load/recovery/typography routes remain
named exceptions and are structurally enumerated.
