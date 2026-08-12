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
- a fixed, licensed, real-world `README.md` corpus, resolved below — replacing "a dozen files
  chosen for variety" (2026-08-10 draft) with a named list and a verified coverage property, so no
  implementer has to exercise judgement about which files or how many.

**Real-world corpus — 2026-08-11 addendum, resolving the open judgement call.** Vendored once at
implementation time (not fetched by CI, per `VISION.md`'s local-first/no-networking product
principle, which this test-time-only tooling honours even though it is not shipped) from twelve
repositories chosen for two properties: an unambiguous permissive licence (no copyleft, so
reproducing one file as a test fixture with attribution carries no encumbrance), and, as a set,
coverage of every GFM construct REQ-047 names.

| Repository | Licence | Repository | Licence |
| --- | --- | --- | --- |
| `microsoft/vscode` | MIT | `sveltejs/svelte` | MIT |
| `facebook/react` | MIT | `rust-lang/rust` | MIT OR Apache-2.0 |
| `twbs/bootstrap` | MIT | `golang/go` | BSD-3-Clause |
| `nodejs/node` | MIT | `django/django` | BSD-3-Clause |
| `vuejs/vue` | MIT | `kubernetes/kubernetes` | Apache-2.0 |
| `angular/angular` | MIT | `apache/spark` | Apache-2.0 |

**Vendoring procedure**, run once, by a human or agent, at implementation time — not automated in
CI, so it cannot introduce network flakiness into the gate:

1. For each repository, fetch `README.md` from its default branch.
2. Read that repository's own `LICENSE`/`LICENSE.md`/`LICENSE-MIT` at the same commit and confirm
   it names the licence in the table above. **If it does not match, do not vendor that file** —
   substitute the next-best-known repository under the same licence family and record the
   substitution and why in `Markdown EditorTests/Corpora/README.md`. The table above is this plan's
   best evidence at authoring time (2026-08-11), not a verified-at-fetch-time guarantee — licences
   and default branches can change, so the check in this step is mandatory, not a formality.
3. Record, per file, in `Markdown EditorTests/Corpora/README.md`: source URL, the exact commit SHA
   the file was fetched at, licence, retrieval date, and the SHA-256 of the vendored bytes.
4. Vendor the file byte-for-byte; do not reformat, re-wrap, or otherwise touch it — the corpus's
   value is that it is real authorial Markdown, not this project's own style.

```swift
// Verifies: REQ-132 — the real-world corpus, as a set, exercises every construct it claims to.
@Test func realWorldCorpusCoversDeclaredConstructs() throws {
    let required: Set<GFMConstruct> = [
        .headingLevel(1), .headingLevel(2), .headingLevel(3), .strongEmphasis, .emphasis,
        .strikethrough, .inlineCode, .fencedCodeBlock, .fencedCodeBlockWithLanguageTag,
        .inlineLink, .autolink, .image, .orderedList, .unorderedList, .nestedList,
        .taskListItem, .blockQuote, .table, .thematicBreak, .rawHTMLBlock, .rawHTMLInline,
    ]
    let observed = Set(RealWorldCorpus.allFiles.flatMap { GFMConstruct.present(in: MarkdownParser.parse($0.text, sourceVersion: 1)) })
    let missing = required.subtracting(observed)
    #expect(missing.isEmpty, "real-world corpus never exercises: \(missing)")
}
```

`GFMConstruct.present(in:)` walks the parsed cmark tree — never a string/regex match, which would
produce false positives from, e.g., a literal `#` inside a fenced code block. **Rehearsed failing**
by vendoring only `microsoft/vscode`'s `README.md` alone and observing which constructs the single-
file corpus fails to cover (at minimum: task list items and raw HTML blocks are unlikely to appear
in any one README, which is exactly why the corpus is twelve files and not one).

If, after fetching, the twelve files as vendored do not jointly satisfy the coverage set, add
`CommonMark-org/commonmark-spec`'s or `github/gfm`'s own `README.md` (BSD-3-Clause and CC-BY-SA-4.0
respectively — the CC-BY-SA file requires an attribution line in
`Markdown EditorTests/Corpora/README.md`, which is a licence obligation this project can meet for a
test fixture) as a thirteenth file rather than relaxing the coverage set.

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

**A found failure becomes a permanent fixture, not a one-off bug report — 2026-08-11 addendum.**
Reproducibility (the printed seed) means a failure *can* be replayed by a human; it does not mean
the suite protects against that exact input regressing again once fixed, since future random runs
draw new seeds and have no reason to rediscover an old one. Every seed that produces a failure in
either fuzz test is committed as one file under
`Markdown EditorTests/Corpora/RegressionSeeds/<seed>-<one-line-description>.json` (the seed value,
the operation sequence it drove, and the assertion that failed). Both fuzz tests gain a **first**,
mandatory pass that replays every committed regression seed byte-for-byte before drawing any new
random one:

```swift
// Verifies: REQ-007/016/091 — every previously found fuzz failure stays fixed.
@Test(arguments: RegressionSeedCorpus.allSeeds)
func committedRegressionSeedStillPasses(_ seed: RegressionSeed) throws { /* replays seed.operations, same assertions as the random pass */ }
```

This is the same "coverage only grows, never silently shrinks" discipline `CLAUDE.md` §2 already
applies to specs, moved into the fuzz corpus: a regression seed is deleted only when the defect
class it represents becomes structurally impossible (e.g. superseded by a stronger property that
provably subsumes it), recorded as such in the commit, never because the seed stopped triggering by
chance. `RegressionSeedCorpus.allSeeds` starts empty at this increment's landing and is expected to
grow over the life of the project — an empty corpus is not a failure of this proof, since Phase 1–2
and this increment's own first run are what populate it.

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
