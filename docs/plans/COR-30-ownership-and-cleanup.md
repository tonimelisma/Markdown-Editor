# COR-30 — Ownership, correctness, and cleanup sweep

- **Status:** Approved; not implemented

## Scope

Individually small defects and inconsistencies found in the `88b7bd3` whole-repository review.
None is urgent alone; together they are the difference between a codebase that reads as
deliberate everywhere and one that reads as deliberate in the places that were reviewed hardest.
Each item below names its exact location and why it is wrong.

### 1. Dead statement in `EditorSession.detach()`

`EditorSession.swift` calls `document?.updateCanonicalAssetReferences(...)` twice: once before
`document = nil` and once after. The second call is unconditionally a no-op on a `nil` optional.
Delete it.

### 2. Coordinate conversion ignores affinity in one direction

`ProjectionCoordinateMap.projectionInsertionPoint(forSource:affinity:)` ends with `_ = affinity`
and returns the first segment match in iteration order. ENGINEERING §4 states affinity is part of
the conversion contract, and the projection→source direction honours it. The source→projection
direction resolves a boundary by segment order instead, so a caret at a boundary between two
segments is decided by array position rather than by the user's affinity. Either honour affinity
here as §4 promises, or state in §4 that this direction is affinity-independent and prove why.
The former is expected; the latter requires the architecture change gate.

### 3. `fileURL` and `locationGeneration` can disagree

`MarkdownDocument.scheduleApplyFileURLChange` applies the location-generation bump on the main
actor, hopping via `DispatchQueue.main.async` when `fileURL` is set off-main. Between the setter
returning and the hop landing, `sourceSnapshot()` reports the **new** URL with the **old**
`locationGeneration`. Every asynchronous identity check in the app — parse application, image
resolution, image placement — is keyed on that pair. Close the window by making the generation
advance atomic with the URL change, or prove by construction that `fileURL` can never be assigned
off-main and remove the branch.

### 4. Word counting is implemented twice, and the tested one is not the shipped one

`TextStats.wordCount` is pure, tested by REQ-044's `countsWordsAndCharacters`, and **unused in
production**. `TextStatsComputer.counts` is a second, differently-written implementation and is
the one that ships. Collapse to one implementation. This is a direct "one obvious path"
violation and a traceability hole: the requirement's correctness proof does not cover the code
that runs.

### 5. Word counting is O(document) per keystroke, outside every measured boundary

`ContentView.swift` uses `.task(id: document.text)` — the task identity is the **entire document
string**, so each keystroke costs a full-string comparison on the main actor plus a task
cancel/restart plus a complete rescan. `TextStatsComputer.counts` additionally reads
`Task.isCancelled` **once per character**. Key the task on `document.sourceVersion`, and check
cancellation on a stride rather than per character.

### 6. `PerformanceSampler` sample buffer is O(n) per record

`record` calls `values.removeFirst()` on a Swift `Array` once `capacity` is reached, copying the
remaining 511 elements on every subsequent sample. Use a ring buffer. Small in absolute terms,
but it is on the keystroke path and inside the boundary the 8 ms budget measures.

### 7. The primary WYSIWYG test seam bypasses the oracle

`EditorSession.installProjectionForTesting` installs a snapshot without
`ProjectionOracle.validate(snapshot:)`, which the production `scheduleParse` path always runs.
Most WYSIWYG tests — including COR-25's regression proof — therefore assert against snapshots
production would have rejected. Run the oracle inside the seam and fail loudly, so the seam
proves the same precondition production does.

### 8. Two test frameworks

`WYSIWYGListCommandRegressionTests` (added in `88b7bd3`) uses XCTest inside
`EditorCommandControllerTests.swift`, a file and suite that otherwise use Swift Testing. Convert
it to Swift Testing so the suite has one idiom, and so structural inventories over `@Test` see
every test.

### 9. Production test hooks

Eleven `…ForTesting` members and the smoke-run affordances ship in the product binary. They are
internal and small, and a separate module boundary is not worth introducing for them — but they
should be inventoried in one place and each justified, rather than accumulating silently. Add a
structural test that enumerates them and fails when the count changes without a documented
reason.

### 10. Repository hygiene

`default.profraw` is produced by instrumented runs in the repository root and is not ignored;
`Scripts/smoke-screenshot.sh` already redirects `LLVM_PROFILE_FILE` for its own run, so the
remaining producer is an ordinary local test run. Add the ignore rule.

(The `/private/tmp/wt-cor11-*` directories left over from COR-11 were investigated during this
increment's stale-work sweep and removed: they contained only derived build output — `Build/`,
`CompilationCache.noindex`, `Index.noindex` — with no source and no Git metadata, despite the
`wt-` prefix suggesting worktrees. No work was lost. Nothing remains to do here.)

## Requirements and invariants

- REQ-044, REQ-045: word/character counts and imperceptible typing latency — items 4 and 5.
- REQ-015, REQ-019, REQ-085: location generation participates in every identity check — item 3.
- REQ-090, REQ-103, ARC-020: sampler is bounded and lifetime-owned — item 6.
- REQ-087, ARC-007: coordinate conversion is exact or refused, with affinity — item 2.
- ARC-002: one session-owned typed state, no parallel compatibility state — items 1 and 7.
- **Architecture impact: none**, unless item 2 is resolved by declaring the source→projection
  direction affinity-independent, which requires the ENGINEERING §4 change gate. The expected
  resolution honours affinity and leaves §4 as written.

## Production route

Modify: `EditorSession.swift`, `ProjectionCoordinateMap.swift`, `MarkdownDocument.swift`,
`TextStats.swift`, `ContentView.swift`, `PerformanceSampler.swift`,
`Markdown EditorTests/EditorCommandControllerTests.swift`, `.gitignore`.

Delete: the duplicated `updateCanonicalAssetReferences` call; whichever word-count implementation
loses; the inline `Task.isCancelled` per-character check.

## Implementation phases

Each item lands as its own commit with its own discriminating proof, in this order, so a
regression bisects to one item:

1. Items 1 and 10 (no behavior change).
2. Item 4, then item 5 — collapse first, then change the trigger, so the latency change is
   measured against a single implementation.
3. Item 6.
4. Item 7, then item 8 — tighten the seam before converting the test that uses it, so the
   conversion is proven against the stricter seam.
5. Item 2, with a boundary-affinity table test.
6. Item 3, with a test that asserts URL and generation are observed atomically.
7. Item 9.

## Automated non-UI proof

- Item 2: a table test over caret positions at every segment boundary in a document containing
  identity, atomic, synthetic, and literal-fallback segments, asserting upstream and downstream
  affinity resolve to the declared source positions.
- Item 3: set `fileURL` from a non-main context and assert that no observation of
  `sourceSnapshot()` ever reports the new URL with the old generation.
- Item 4: the surviving implementation carries REQ-044's existing assertions; a structural test
  proves only one word-count implementation exists.
- Item 5: assert the counting task is not restarted when `sourceVersion` is unchanged; re-record
  the focused Release `nativeInputCallback` gate.
- Item 6: assert bounded memory and O(1) amortised `record` by construction; sampler lifetime
  proofs (REQ-110) unchanged.
- Item 7: a test proving the seam refuses an oracle-invalid snapshot.
- Item 9: the inventory test.

## Instrumentation and performance evidence

No new trace events. Re-record the focused Release `nativeInputCallback` gate after items 5 and
6; both are on the keystroke path and both are expected to reduce main-actor work. Record the
before/after so the improvement is evidence rather than assertion.

## Failure and rollback behavior

Every item is behaviour-preserving except items 2, 3, and 5, which change *when* a value is
observed rather than what it is. Item 2 must refuse where it refuses today; a boundary that
becomes newly exact requires an explicit proof that the new answer is correct, not merely
non-refusing. Canonical source is untouched throughout.

## Deletion and conformance gate

- Prove one word-count implementation, one sampler buffer route, one projection-install seam.
- Prove `git status` is clean after a full local test run.
- Both gate scripts pass; both smoke scripts pass; delete this plan in the implementing change.
