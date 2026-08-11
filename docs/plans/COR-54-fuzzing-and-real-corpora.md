# COR-54 — Correctness fuzzing and real-world corpora

- **Status:** Approved; not implemented
- **Requirements:** REQ-007, REQ-011, REQ-016, REQ-047, REQ-054, REQ-056, REQ-083, REQ-091; new REQ-132 (dialect conformance proved against the named specification's own example set)
- **Delivers:** REQ-132
- **ARC invariants:** ARC-007 (exact or refused, never a different exact answer) and ARC-009 (atomic refusal) get their first adversarial proofs. No architecture change.

## Context

Every fixture in the repository is hand-written. The projection and coordinate machinery is the
highest-risk code in the application, and all of its test inputs were authored by the same people who
wrote it — so the suite proves the cases someone thought of, and nothing else.

`VISION.md` names a specific dialect: *"the complete GitHub Flavored Markdown 0.29-gfm specification"*.
That specification ships with its own normative example set. The app has never been run against it.

There is also one class of defect the oracle structurally cannot catch. `ProjectionOracle` validates a
projection against **itself** — coverage, ordering, round-trips, refusals. If the projection compiler
and the parser disagree about what the document *is*, both the projection and the oracle can be
internally consistent and jointly wrong.

## Production changes

None. This increment is entirely verification. That is deliberate: it should be possible to land it
against the current build and learn what is already broken.

## Phase 1 — real-world corpora

Vendor under `Markdown EditorTests/Corpora/`:

- the CommonMark 0.29 specification's own example set, extractable from `spec.txt` in the already-
  pinned cmark-gfm source — no new dependency, and it is the normative definition of the dialect
  VISION names;
- the GFM extension specification's examples (tables, task lists, strikethrough, autolinks, tag
  filtering);
- a dozen real `README.md` files chosen for construct variety, each with provenance and licence
  recorded in `Markdown EditorTests/Corpora/README.md`.

```swift
// Verifies: REQ-047/054/132 — every specification example projects to an oracle-valid snapshot.
@Test(arguments: SpecCorpus.allExamples)
func everySpecExampleProducesAnOracleValidProjection(_ example: SpecExample) throws
```

**Expect failures.** Each is either a real defect or a documented dialect boundary. Every one is
triaged and recorded per example in `REQUIREMENTS.md` beside REQ-047 — an example that fails and is
neither fixed nor documented fails the increment. This is the point of the increment: converting
unknown unknowns into a written list.

## Phase 2 — coordinate round-trip property

```swift
// Verifies: REQ-056; ARC-007 — every projection position maps to source exactly or refuses.
@Test(arguments: SpecCorpus.allExamples)
func everyProjectionPositionRoundTripsOrRefuses(_ example: SpecExample) throws
```

For every position from 0 to `renderedString.length`, `sourceRange(forProjection:)` followed by
`projectionRange(forSource:)` must return the original range **or a typed refusal**. It must never
return a *different exact answer* — that is silent corruption, and it is precisely what ARC-007 exists
to forbid. The distinction matters: a refusal is a safe outcome the product already handles; a wrong
exact answer applies an edit somewhere the user did not look.

Run the same property with both affinities, since COR-30 found an affinity defect by hand.

## Phase 3 — edit fuzzing

Seeded and reproducible; the seed is printed on failure so any failure replays exactly.

```swift
// Verifies: REQ-007/016/091 — random accepted edits never corrupt source.
@Test func randomAcceptedEditsLeaveSourceReparseable() throws
```

Ten thousand random operations drawn from `SemanticCommand.allCases` at random positions. After each
one: source re-parses successfully, the resulting snapshot is oracle-valid, bytes outside the mutation
range are unchanged, and **every refusal left source byte-identical**. The last clause is the one that
matters — ARC-009 promises atomic refusal, and a refusal that mutated anything is the worst defect
this codebase can have.

```swift
// Verifies: REQ-011/083 — undo and redo restore exact source across mode switches.
@Test func randomUndoRedoSequencesRestoreExactSource() throws
```

Random edits interleaved with undo, redo and mode toggles; assert source equals the recorded history
at every step. This is where ordering bugs live, and nothing tests it today.

## Phase 4 — differential against the parser's own renderer

```swift
// Verifies: REQ-054 — the projection's text agrees with the pinned parser's own rendering.
@Test(arguments: SpecCorpus.allExamples)
func projectionTextAgreesWithCmarkHTMLTextContent(_ example: SpecExample) throws
```

`MarkdownParser` already exposes `renderHTMLUTF8`. Strip tags, normalise whitespace, and compare
against the projection's rendered string modulo the declared synthetic insertions — list markers, task
checkboxes, thematic breaks — which are enumerated rather than skipped by pattern, so a new synthetic
kind cannot silently widen the exemption.

A divergence means the projection compiler and the parser disagree about the document. This is the one
class the oracle cannot catch, because the oracle checks a projection against itself.

## Proof

The tests above are the proof. Additionally:

- `specCorpusIsNotEmptyAndNamesItsSource` — a fail-closed guard in the shape of
  `check-proof-results.sh`'s: a corpus that silently extracts zero examples must fail, not pass. A
  check that matches nothing is the same defect wearing a new hat.
- `fuzzSeedIsReportedOnFailure` — proves a failure is reproducible before anyone needs it to be.
- `refusalsAreCountedAndBounded` — reports the refusal rate across the fuzz run. A run where 99 % of
  operations refuse is technically passing and practically worthless; this makes the liveness of the
  fuzzer itself visible, in the spirit of `CLAUDE.md` §4's liveness rule.

## Instrumentation and performance evidence

The fuzz suites are slow by nature. They run in the full suite, not in `Scripts/fast-check.sh`, and
`Scripts/check-performance-suite.sh`'s bounded wall-clock guard is extended to cover them so "the
fuzzer now never completes" fails loudly rather than silently — the exact failure mode COR-32 found in
`PerformanceBoundaryTests`.

Iteration counts are parameterised by environment variable with the CI default recorded, so a local
run can be short and the closing run is full.

## Failure / rollback

Verification-only; nothing ships. The increment cannot break the product.

It can fail to land: if Phase 1 surfaces a large number of specification failures, the triage is the
work, and it may exceed this increment. In that case land Phases 1–2 with every failure recorded as
either a `Correction` row or a documented dialect boundary, and defer Phases 3–4 to a follow-up. A
recorded list of known dialect gaps is a strictly better position than the current silence, and
splitting is preferable to shipping an increment that quietly skips its own findings.

## Deletion / conformance gate

- No specification example is skipped without a recorded reason in `REQUIREMENTS.md`; a skip list that
  lives only in test code fails the increment.
- The synthetic-insertion exemption in Phase 4 is an enumeration over the declared synthetic kinds, not
  a regular expression — so adding a synthetic kind fails the build until it is declared.
- `Scripts/check-documentation-authority.sh` and `Scripts/check-proof-results.sh` pass, with every new
  test carrying a `// Verifies:` anchor per REQ-118.
