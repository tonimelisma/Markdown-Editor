# COR-67 — Make the COR-62 backlog executable

- **Status:** Approved; not implemented
- **Requirements:** the 68 `Correction` rows listed in *Units* below. No new requirement is created: REQ-138 already states the obligation every unit discharges.
- **Delivers:** none (each unit moves its own rows to `Done` in its own change; this plan delivers no requirement by itself)
- **ARC invariants:** none changed. A unit that cannot re-verify a row without changing an `ARC-###` invariant has found an architecture question and stops under §3's architecture-change gate.
- **Architecture impact:** none.
- **Executor:** an agent or engineer working one unit at a time, unattended. It demands one judgement repeatedly — *is this row's cited proof real, or does it merely exist?* — and the discipline to stop when the answer is "the behaviour is wrong" rather than repairing it here.

## Context

COR-62 re-verified every `Done` row against the falsification, proof-results and delivery-status
gates, and returned 81 rows to `Correction`. It restored the plans it could restore: ten increments
whose plans had been deleted in the false 2026-08-10 promotion were recoverable from Git, and their
rows are reachable through those plans today.

The other 68 rows are not. They belong to COR-01–COR-11, COR-14 and INC-01–INC-04 — increments
delivered correctly, whose plans were correctly deleted on delivery, long before any of these gates
existed. There was nothing to restore. So the audit's largest output became its least visible one:
`docs/plans/` describes 26 plans and none of these 68 rows, while §3 requires a build unit to start
from an approved plan.

This plan is that starting point. It adds no behaviour and re-implements nothing. Its deliverable is
that a reader of `docs/plans/` can see the whole backlog and pick up any part of it.

**Re-verification is not repair.** A row is `Correction` because its evidence was never shown to
discriminate, not because the behaviour is known to be broken. Most units are expected to find sound
behaviour under-proved and close by supplying the missing proof. A unit that finds genuinely wrong
behaviour records it as a new `COR-##` increment and leaves the row `Correction`; fixing product
defects inside a re-verification unit would repeat exactly the discovery/build mixing §3 forbids.

## Method, identical for every unit

For each `REQ-###` in the unit:

1. **Read the requirement, then find what actually implements it.** The `Implemented in` cell is `—`
   for every row in this backlog; establishing it is part of the work. Name current production
   types and routes, not files alone.
2. **Decide whether an existing test already discriminates it.** Often one does and was simply never
   cited. Cite it. A test that passes whatever production does is not a proof — check what it
   asserts, not that it is green.
3. **Where nothing discriminates, write the proof.** Unit or component tests only; ARC-014 stands.
   Where the requirement quantifies over a class of inputs ("any command", "either appearance",
   "every block kind"), the proof enumerates that class structurally so a new member fails the build
   until its behaviour is declared — §4, *a proof's inputs are part of the proof*.
4. **Where the requirement promises a capability, prove it succeeds** on ordinary input in every
   mode it is offered in. A refusal-only proof set does not discharge it — REQ-058 was satisfied for
   months by proofs that only asserted availability and refusal.
5. **Write `Falsification/REQ-###.json`** declaring a plausible defect under which a cited proof must
   go red. Run `Scripts/check-falsification.sh --changed`, and observe the mutation turn the proof
   red. A row whose proofs cannot be made to fail cannot be `Done` (REQ-138).
6. **Move the row to `Done`** with `Implemented in` and `Verified by` filled, in the same change.

A unit is finished when `Scripts/full-check.sh` passes with its rows `Done` and its manifests
executed — not when its steps have been performed.

## Units

Sixteen units, grouped by the increment that owns the rows. They share no dependencies and may be
taken in any order; the row counts are the only guide to size. Each is one worktree, one branch
(`cor-67-<unit>`), one PR, one separate-agent review.

| Unit | Owner | Rows | Requirements |
| --- | --- | ---: | --- |
| 1 | INC-01 | 12 | REQ-002, REQ-003, REQ-004, REQ-005, REQ-006, REQ-010, REQ-012, REQ-020, REQ-021, REQ-022, REQ-030, REQ-031 |
| 2 | INC-01 / COR-05 | 1 | REQ-011 |
| 3 | INC-02 | 6 | REQ-040, REQ-041, REQ-043, REQ-044, REQ-045, REQ-046 |
| 4 | INC-03 | 5 | REQ-062, REQ-064, REQ-066, REQ-068, REQ-073 |
| 5 | INC-04 | 2 | REQ-053, REQ-059 |
| 6 | INC-04 / COR-06 | 3 | REQ-054, REQ-055, REQ-056 |
| 7 | INC-04 / COR-07 | 2 | REQ-079, REQ-082 |
| 8 | COR-01 | 2 | REQ-047, REQ-050 |
| 9 | COR-02 | 10 | REQ-061, REQ-063, REQ-065, REQ-067, REQ-070, REQ-071, REQ-072, REQ-074, REQ-075, REQ-077 |
| 10 | COR-02 / COR-08 | 1 | REQ-069 |
| 11 | COR-03 | 2 | REQ-048, REQ-049 |
| 12 | COR-04 | 4 | REQ-013, REQ-014, REQ-017, REQ-019 |
| 13 | COR-09 | 12 | REQ-015, REQ-052, REQ-060, REQ-080, REQ-083, REQ-084, REQ-085, REQ-086, REQ-087, REQ-091, REQ-092, REQ-093 |
| 14 | COR-10 | 2 | REQ-089, REQ-094 |
| 15 | COR-11 | 2 | REQ-097, REQ-098 |
| 16 | COR-14 | 2 | REQ-101, REQ-102 |

Rows owned jointly with a planned increment (COR-18, COR-20, COR-21, COR-26, COR-29, COR-32,
COR-33, COR-34, COR-35, COR-38, COR-40, COR-45, INC-05) are **out of scope here** and are cleared
by those increments' own plans. That is the boundary between this plan and the restored ones; a unit
that finds itself editing a row already claimed by another plan has crossed it.

## Production files to add, modify, delete

None planned. This increment adds tests, falsification manifests and requirement rows.

Any production change a unit believes it needs is, by definition, outside the unit: it means the
behaviour does not match the requirement, which is a finding to report as a new increment, not a
repair to make here. The one exception is a change whose sole purpose is to make existing behaviour
observable to a component test — and even that is worth stating in the PR, because a requirement
that cannot be observed without changing production is telling you something about the design.

## Ordered phases

1. Pick one unit. Create its worktree and branch.
2. Apply *Method* to each row in the unit.
3. Reconcile `docs/REQUIREMENTS.md` rows and this plan's table on the branch: strike the unit from
   the table, and delete this file entirely in the change that completes the last unit.
4. Run `Scripts/full-check.sh`; observe it pass.
5. PR, separate-agent review, last-10-PR comment sweep, squash-merge, DoD.

## Automated non-UI proof

Per row, as *Method* steps 3–5. No XCUITest, no screen automation (ARC-014). Direct construction of
AppKit components and forced layout is permitted and is the required approach wherever a row is
about rendered geometry rather than a model value — §4, *proofs must assert the thing the
requirement is about*; REQ-106 was `Done` for months on a proof that asserted the rendered string
while a hard break laid out identically to a paragraph boundary.

## Instrumentation and performance evidence

None expected. A unit that adds an `EditorTraceEvent` case must give it a real production call site
in the same change or delete it — `Scripts/check-instrumentation-coverage.sh` establishes coverage
from records an executed run actually emitted, so a receiver bound to `nil` will not satisfy it.

No unit commits a measurement. `Scripts/benchmark.sh` cannot currently produce one (see COR-45), and
`Scripts/check-measurement-provenance.sh` rejects any measurement that is not machine-written.

## Failure and rollback behavior

A unit that cannot discharge a row leaves it `Correction`, states plainly why in the PR, and
narrows its own scope. Partial completion of a unit is acceptable and expected; a row silently
promoted without an observed falsifying mutation is not, and is the specific failure this whole
programme exists to make unrepresentable.

Rollback is per-unit: each is an independent squash commit on `main`.

## Deletion and conformance gate

No production path is displaced, so there is nothing to delete. The conformance gate is
`Scripts/full-check.sh` at each unit's close, plus the arithmetic that closes this plan: when the
last unit lands, no row in the table remains `Correction`, and this file is deleted in that same
change.

Until then this plan's presence is the standing statement that the work is unfinished — which is
the whole reason it exists, since the audit's own register could not say so where anyone would look.
