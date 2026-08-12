# INC-05 — Semantic presentation and typography

- **Status:** Approved; not implemented
- **Delivers:** REQ-106
- **Executor:** implementation agent with a separate review; no architecture change

## Scope

Re-prove the rendered typography, break geometry, and composed semantic block treatments that COR-62 demoted. Proofs must assert laid-out geometry or constructed presentation behavior, not only model attributes.

## Architecture impact

None. PresentationBlock, AttributedPresentationBuilder, and MarkdownTypography remain the current owners.

## Ordered phases

1. Run the geometry, typography, and semantic composition suites across their declared widths and block matrix.
2. Inspect the passive rich-fixture screenshot without driving the application.
3. Record falsifying mutations against the cited proofs and observe them turn red.
4. Reconcile requirement rows and delete this plan only after all gates pass.

## Proof and evidence

ParagraphGeometryTests, TypographyLayoutTests, semantic composition tests, VisualReviewFixtureTests, proof-results, and falsification.

## Failure and rollback

Keep the rows Correction and the plan present. Do not replace rendered proofs with token-value assertions.

## Deletion/conformance gate

Documentation authority, proof-results, falsification, screenshot review, and stale-work checks pass.
