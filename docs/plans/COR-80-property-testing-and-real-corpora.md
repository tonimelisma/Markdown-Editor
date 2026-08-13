# COR-80 — Property testing and real corpora

- **Status:** Approved; not implemented
- **Delivers:** REQ-132
Architecture impact: none
Blockers: COR-71, COR-72, COR-73, COR-76, COR-77, COR-78
Executor: A junior may implement generators and imported corpora from this specification. A senior reviews shrinkers, oracle choice, and any discovered production defect.

## Outcome

Turn parser/index/projection/encoder/transaction/file invariants into generated properties over
declared input classes, and import traceable CommonMark/GFM examples. Every minimized failure becomes
a permanent fixture before its production fix is planned separately.

## Files and ownership

- Add test-only `GeneratedMarkdown`, `GeneratedEditSequence`, deterministic RNG, shrinkers, and a
  corpus manifest under `Markdown EditorTests/PropertySupport/`.
- Import upstream examples into `Markdown EditorTests/Fixtures/Specifications/` with version,
  source URL, license, digest, expected semantics, and refresh command; do not hand-edit generated data.
- Add suites for source-index round trips, projection oracle, local-vs-authoritative transition,
  incremental-vs-full highlighting, undo/redo, image filename/containment, and diagnostic privacy.

## Implementation

1. Define closed generator dimensions: block/inline kind, valid/malformed, delimiter spelling,
   nesting, CRLF/LF, BOM, Unicode/grapheme, edit operation, selection class, and file/path class.
2. Use fixed seeds in normal CI and an opt-in recorded seed/count for long runs. Every failure prints
   replay data and shrinks deterministically.
3. Compare only to independent oracles: pinned cmark renderer/AST, fresh full lexer, fresh full
   presentation build, exact inverse map, source-before/after, filesystem spy, and transaction log.
   Never compare an implementation to the same helper it calls.
4. On failure, commit the minimized fixture and leave the affected requirement `Correction`; stop the
   increment. Production repair requires its own approved plan or an existing plan that explicitly
   owns the defect.
5. Bound runtime and report executed cases per dimension; zero cases or an unvisited enum member fails.

## Proof and failure behavior

Mutation rehearsals break one coordinate boundary, lexer propagation, undo inverse, containment
check, and diagnostic payload restriction and observe the matching property red. Corpus digests and
license metadata are checked. Generated tests are deterministic under parallel execution.

## Deletion/conformance gate

No “variety chosen by hand,” unseeded randomness, self-oracle, swallowed failure, or fixture without
provenance remains. The structural dimension matrix covers every declared enum case.
