# COR-88 — The oracle proves tiling, not coverage

> **Status: proposed, not approved.**

- **Executor:** any implementer, unattended, *after* phase 1's property holds. Phase 1 can produce
  a counterexample that stops the increment; that outcome needs a human.
- **Blockers:** COR-86, for the metric that makes the improvement measurable rather than asserted.
- **Requirements moved to `Done`:** none directly. Moves COR-86's new requirement closer without
  closing it; COR-89 decides whether it closes.
- **Architecture impact:** none. `ProjectionOracle`'s contract is strengthened, not redefined; no
  `ARC-###` changes.

## The defect

Evidence: `docs/research/2026-08-22-semantic-command-main-actor-cost.md`.

`ProjectionOracle.validate` is the largest single cost in a formatting command and **costs more
than the cmark parse it validates** — 95.1 ms against 27.5 ms on `heavyLists`, Debug. It runs
synchronously on the main actor for every Cmd+B.

The cost is not structural. `degenerateParagraph` is one block and two segments and costs 22.1 ms,
because the check is a per-character coverage array: an 800 KB allocation and 100,000
bounds-checked increments on a 100,000-character document, to prove a property about a few
thousand segment boundaries.

This is `DECISIONS.md`'s lesson relocated into the running app. There, a verification apparatus
cost more than the work it verified and was removed. Here, a correctness proof costs more than the
computation it validates, on the main thread, in the user's hands.

## Why the obvious fix is a band-aid

Skipping the oracle, sampling it, or running it only in Debug all trade a correctness proof for
latency, and this product ranks correctness above speed. The oracle is right to exist: it is the
independent check that the projection round-trips to source, added deliberately by COR-30.

**The oracle is not too strict. It is written in the wrong complexity class.**

## The proper fix

The property is *"the segments exactly partition the projection"* — a statement about
**boundaries**, not characters. Sort segments by projection location and check that they tile:
the first starts at 0; each starts exactly where the previous ended; the last ends at
`renderedCount`.

O(segments), no allocation, and it decides **overlap, gap, out-of-bounds *and ordering***, which
the coverage array cannot see. A strictly stronger proof at roughly 1 % of the cost.

Two deletions in the same increment:

- **`make()` round-trips segments through atoms and back.** `PresentationSnapshot.from` calls
  `ProjectionAtom.from(segments:…)`; `make` immediately calls `ProjectionAtom.toSegments(atoms)`
  to rebuild what its caller held. 0.3–4.3 ms of pure waste. `make` takes segments directly.
- **`make()` constructs the full snapshot twice** — once as `candidate` for the oracle, then again
  field-by-field to set `oracleValid`.

## The strengthening risk, retired first

Requiring ordering is a strengthening: the current check accepts out-of-order segments that
happen to tile. If production ever emits them, the new oracle rejects a projection the old one
allowed — surfacing as a refusal, not corruption, but a regression.

This is retired **before** any implementation change, using COR-80's machinery: assert segments
are emitted in ascending projection order across the **1,324 imported CommonMark 0.31.2 and
GFM 0.29 spec examples** and the generated corpus. If the property holds across the entire pinned
specification, the strengthening is safe. If it does not, the counterexample is a real defect in
`MarkdownProjectionModel`, and this increment **stops and returns to discovery**.

## Files, types, and routes

**Modify:** `Markdown Editor/ProjectionOracle.swift` (tiling check replaces coverage array; new
`out_of_order` failure code); `Markdown Editor/PresentationSnapshot.swift` (`make` takes segments;
single construction); `Markdown Editor/ProjectionAtom.swift` (`toSegments` loses its only caller —
delete it if no other remains).

**Add:** cases in `Markdown EditorTests/ProjectionCharacterizationTests.swift` and the property
suite.

**Delete:** the `covered` array and its two loops; the `toSegments` round-trip; the duplicate
`PresentationSnapshot` construction; `ProjectionAtom.toSegments` if unreferenced.

## Ordered phases

1. `segmentsAreEmittedInAscendingProjectionOrder` over spec + generated corpora. **Observe it
   pass.** If it fails, stop.
2. Add `oracleRejectsOutOfOrder` against the *current* implementation. **Observe it fail** — this
   proves the new code is load-bearing.
3. Replace the coverage array with the tiling check. All four rejection tests green.
4. Delete the round-trip and the double construction.
5. Re-measure with COR-86's metric; record in research.
6. `Scripts/check.sh`. Report actual output.

## Automated non-UI proof

- `oracleRejectsOverlap`, `oracleRejectsGap`, `oracleRejectsOutOfBounds` — existing failure codes
  must still fire; hand-built segment sets, not corpora.
- `oracleRejectsOutOfOrder` — the new code. Red against the old implementation.
- `segmentsAreEmittedInAscendingProjectionOrder` over 1,324 spec examples + generated corpus.
- `oracleCostIsIndependentOfDocumentLength` — the honest form of the performance claim: validate
  two documents with equal segment counts and very different character counts; assert cost does
  not scale with the latter. A **shape** assertion, not a wall-clock threshold, so it encodes no
  machine's speed and cannot go flaky.

## Failure and rollback behavior

Unchanged: the oracle returns `Result<Void, Failure>` and a failing projection refuses as
`.unprovable`, exactly as today. The set of rejected projections grows by out-of-order ones, which
phase 1 proves is empty in practice. Rollback is reverting the commit.

## Deletion and conformance gate

The coverage array, the round-trip, and the double construction are **deleted**, not bypassed. No
flag, no fast path, no compatibility layer (`CLAUDE.md` §6). A grep proving `covered` is gone is an
absence check with an obvious detector.

## Expected outcome

Debug `heavyLists` ~181 ms → ~85 ms; `degenerateParagraph` ~22 ms → ~6 ms. **Not enough on its own
for the 16 ms budget on the large corpora** — that is COR-89's question. Roughly half the cost
removed by writing a better proof and deleting code.
