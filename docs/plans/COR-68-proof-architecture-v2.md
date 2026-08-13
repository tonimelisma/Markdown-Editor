# COR-68 — Proof architecture v2

- **Status:** Approved; not implemented
- **Delivers:** REQ-099, REQ-117, REQ-118, REQ-135, REQ-138
Architecture impact: none; repairs the executable proof of ARC-014 and ARC-027
Blockers: none
Executor: A junior developer may implement this plan exactly. Treat every gate change as a trust-boundary change; if a fixture can turn red for more than one reason, stop and request senior review rather than guessing.

## Outcome

Make delivery mean an observed production route failed under a production defect. Encoding tests,
source-text searches, stricter bookkeeping, and a deleted plan must no longer be able to masquerade
as reachability, discrimination, or delivery.

## Current defect

`DiagnosticLogTests.everyTraceEventMapsToSymbolicPayload` constructs every `EditorTraceEvent` and
writes it into the log union consumed by `check-instrumentation-coverage.sh`. This proves encoding,
not production reachability. Existing falsification manifests may turn a gate red by corrupting the
gate's inputs or making it stricter, without weakening production behavior. `Delivers: none` plans
also have no machine-readable completion evidence.

## Files and ownership

- Modify `Scripts/check-instrumentation-coverage.sh`, `Scripts/check-proof-results.sh`,
  `Scripts/check-delivery-status.sh`, `Scripts/check-falsification.sh`, and their fixture tests.
- Split encoding proof from route proof in `Markdown EditorTests/DiagnosticLogTests.swift`.
- Add `docs/proof-routes.json`: reviewed mapping from every trace case to a production entry route,
  expected record, and allowed process/component harness. It contains symbols only, never content.
- Extend plan metadata with `Completion-Proofs:` for refactor-only increments and teach the delivery
  gate to require those proofs before a plan may disappear.
- Delete any manifest whose mutation does not compile production code or whose expected red can be
  produced without changing the requirement's production responsibility.

## Implementation

1. Add failing fixtures: a synthetically emitted event with no production route; a mutation that
   only makes a gate stricter; a cited test omitted from the result bundle; an unmapped failing test;
   and a deleted `Delivers: none` plan with no observed completion proof.
2. Give test and process logs an explicit evidence origin (`productionRoute`, `encodingProbe`, or
   `gateFixture`). Coverage accepts only `productionRoute`; unknown origin fails closed.
3. Execute every declared route through its real owner. A component harness may directly construct
   an AppKit owner, but may not call `trace.record` as the behavior under test.
4. Change falsification validation to require: production file outside tests/scripts/docs; exact
   preimage; compiling mutation; named requirement responsibility; and at least one cited proof that
   changes from pass to fail. Generic gate errors do not count.
5. Add `Completion-Proofs:` parsing and require every named proof in the closing result bundle for
   refactor plans. Preserve `Delivers:` for behavior status only.
6. Regenerate honest route evidence, update the five requirement rows, and delete displaced
   synthetic coverage input.

## Proof and failure behavior

- Fixture suites rehearse every new gate red before the gate is trusted.
- Removing one production route while retaining its encoder test fails coverage.
- A tautological cited test and a stricter-gate mutation both fail falsification validation.
- A refactor plan cannot be marked delivered or deleted without observed completion proofs.
- `Scripts/fast-check.sh` and `Scripts/full-check.sh` pass at the same commit/tree; all affected
  manifests run, not changed-scope zero.
- On ambiguity, keep requirements in `Correction` and the plan present. Do not add a second gate
  beside an acknowledged-defeatable one; replace it.

## Deletion/conformance gate

`rg` finds no route by which `encodingProbe` or `gateFixture` records enter coverage, no source-text
call-site scan used as reachability evidence, and no active refactor plan lacking
`Completion-Proofs:`. Documentation authority and the full falsification run both pass.
