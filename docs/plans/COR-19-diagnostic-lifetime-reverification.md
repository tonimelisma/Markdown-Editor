# COR-19 — Diagnostic lifetime and shutdown

- **Status:** Approved; not implemented
- **Delivers:** REQ-095, REQ-096
- **Executor:** implementation agent with a separate review; no architecture change

## Scope

Re-prove diagnostic lifetime, fault durability, periodic summaries, and detached-session cleanup after the COR-62 audit demoted the requirements. Repair is out of scope until a reproduced failing proof identifies it.

## Architecture impact

None. DiagnosticLog, PerformanceSampler, DiagnosticRunCoordinator, and the main-actor fault path retain their current ownership.

## Ordered phases

1. Run the cited unit/component suites and process smoke with isolated diagnostic output.
2. Verify termination, repetition collapse, fault durability, and sampler invalidation from structured records.
3. Add and execute a falsification mutation for each restored Done row.
4. Reconcile requirements and delete this plan only after the complete gates pass.

## Proof and evidence

DiagnosticLogTests, DiagnosticLifetimeTests, ReconciliationInvariantTests, smoke verification, proof-results, and falsification gates.

## Failure and rollback

Keep rows Correction and preserve logs/results; do not weaken the diagnostic contract to make a gate pass.

## Deletion/conformance gate

Documentation authority, instrumentation coverage, proof-results, delivery-status, falsification, and stale-work checks pass.
