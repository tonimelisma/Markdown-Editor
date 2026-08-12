# COR-21 — Latest-work scheduling and resource bounds

- **Status:** Approved; not implemented
- **Delivers:** REQ-076, REQ-081, REQ-112
- **Executor:** implementation agent with a separate review; no architecture change

## Scope

Re-prove latest-request scheduling, encoded-image bounds, cmark-derived asset references, and move checks after the COR-62 audit demoted these requirements.

## Architecture impact

None. The current scheduler, image resolver, and canonical-reference pipeline remain authoritative.

## Ordered phases

1. Run the scheduler, image-resource, and canonical-reference suites over their full fixture matrices.
2. Verify off-main execution, stale-result rejection, size limits, and source/reference agreement.
3. Add and execute a falsifying mutation for every restored Done row.
4. Reconcile requirements and delete this plan only when all cited proofs and gates pass.

## Proof and evidence

LatestParseSchedulerTests, image cache/decoder tests, canonical asset reference tests, proof-results, and falsification.

## Failure and rollback

Keep affected rows Correction and preserve failing result bundles. No broad retry or compatibility path is permitted.

## Deletion/conformance gate

Documentation authority, proof-results, falsification, delivery-status, architecture-conformance, and stale-work checks pass.
