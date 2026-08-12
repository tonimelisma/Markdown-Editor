# COR-18 — Restore the proof floor

- **Status:** Approved; not implemented
- **Delivers:** REQ-088, REQ-104
- **Executor:** implementation agent with a separate review; no architecture change

## Scope

Re-establish the Debug/Release build and passive screenshot proof after the COR-62 audit demoted the requirements. This plan does not change product behavior or architecture; it replaces stale delivery claims with observed proofs.

## Architecture impact

None. The existing Swift 6 and ARC-Q13 contracts remain authoritative.

## Ordered phases

1. Reproduce the Debug and Release test runs and capture the result bundles.
2. Run the smoke verifier and exactly one passive application-window screenshot over the rich fixture.
3. Add falsification manifests for any remaining Done row in scope and run the full proof gates.
4. Reconcile requirements and delete this plan only when the cited proofs and mutations are observed passing.

## Proof and evidence

xcodebuild test, Scripts/check-proof-results.sh, Scripts/smoke-screenshot.sh, and visual review of the produced PNG. No UI automation or XCUITest.

## Failure and rollback

Leave the affected rows Correction and this plan present if any run fails; preserve all result bundles and logs.

## Deletion/conformance gate

Documentation authority, instrumentation coverage, delivery-status, proof-results, falsification, and stale-work checks pass with no displaced route.
