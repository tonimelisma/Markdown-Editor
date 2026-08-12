# COR-26 — Enabled implies performable

- **Status:** Approved; not implemented
- **Delivers:** REQ-113

## Scope

Four semantic commands report `availability == .enabled` and then refuse without mutating source
when invoked on an ordinary WYSIWYG paragraph selection. Correct the shared planner gate so every
enabled command performs, and add the structural gate that makes an unperformable enabled command
a build failure rather than a defect discovered by hand.

Measured on `88b7bd3`, source `"First paragraph.\n\nSecond paragraph.\n"`, WYSIWYG projection
selection `{0,16}`, driven through the real `EditorCommandController` route:

| Command | Planner call site | Outcome |
| --- | --- | --- |
| bold, italic, strikethrough, inlineCode | `InlineEditPlanner` | accepted |
| unordered/ordered/task list | `ListEditPlanner.toggle` | accepted (COR-25) |
| paragraph, heading | `BlockEditPlanner.transformLine` | **refused, `mappingFailure`** |
| blockQuote | `ListEditPlanner.toggleBlockQuote` | **refused, `mappingFailure`** |
| codeBlock | `BlockEditPlanner.toggleCodeFence` | **refused, `mappingFailure`** |

The correspondence is exact: every refusing command routes through a `SemanticPlannerGate`
call site that does not pass an explicit `selectionAfter`; every accepted command either passes
one (COR-25) or produces a replacement with no trailing newline.

This increment does not broaden support for mixed, cross-cell, synthetic, or unprovable
selections. Every existing refusal proof must still pass.

## Root cause

`SourceMutation.exact` defaults `selectionAfter` to a caret at
`range.location + (replacement as NSString).length`. For a block rewrite whose replacement ends
with a newline, that caret lands on a source position at a block boundary — the blank-line
separator between two blocks. Block-boundary source positions have no exact projection preimage,
so `SemanticEditEngine.planAuthoritativeTransition` (`SemanticEditEngine.swift:323`) refuses when
it re-projects the post-mutation caret through
`nextFixed.coordinateMap.projectionRange(forSource:affinity:)`.

Selection classification is not implicated: the selection classifies correctly as
`.identityText(sourceRange: {0,16})` before the planner runs. COR-25's plan directed the
implementer at `ProjectionSelectionClassifier`; that was the wrong layer, and this plan records
the correction so the same misdirection is not repeated.

## Requirements and invariants

- **REQ-113 (new):** WHEN a semantic formatting command reports `enabled` availability for the
  current selection, the system shall apply it rather than refuse.
- REQ-058: the same formatting commands in both modes through one window-scoped route.
- REQ-057: regenerate only the smallest proven semantic unit.
- REQ-087, ARC-007, ARC-009: exact or atomically refused, never guessed or clamped.
- ARC-005, ARC-019: an accepted command advances source and presentation synchronously through
  the bounded patch route.
- ARC-024: menu and toolbar remain presentations of one command model with shared validation.
- **Architecture impact: none.** The exact-or-refuse rule is unchanged; this corrects which
  coordinate the planners hand it. The deeper question of whether command dispatch should use
  the same coordinate machinery as free-form edits is deliberately excluded and belongs to the
  separately approved architecture discovery unit (ROADMAP: DISC-01).

## Production route

Modify:

- `Markdown Editor/SemanticEditPlanners.swift`
  - `BlockEditPlanner.transformLine` — accept and forward an explicit `selectionAfter`.
  - `BlockEditPlanner.toggleCodeFence` — same.
  - `ListEditPlanner.toggleBlockQuote` — same.
  - Hoist COR-25's per-planner caret arithmetic into one shared helper on `SemanticPlannerGate`
    so the rule exists once. COR-25 solved this correctly for one of eleven call sites by
    inlining the arithmetic; eleven copies of that arithmetic is the defect waiting to recur.
- `Markdown Editor/EditorCommandController.swift` — no behavior change; confirm `availability`
  and `perform` consult one predicate so the new gate cannot be satisfied by disabling commands.

Add:

- `Markdown EditorTests/CommandLivenessMatrixTests.swift` — the structural gate.

Delete: nothing. No displaced route is created by this increment.

The shared helper places the post-command caret at the concrete end of the rewritten line's
content — before any trailing newline and before any block separator — which is a source
position inside the rewritten block's own identity text and therefore always re-projectable.

## Implementation phases

1. Add the failing matrix test first. It must fail on current `main` for exactly `paragraph`,
   `heading(1…6)`, `blockQuote`, and `codeBlock`, and pass for the other seven.
2. Hoist the caret rule into `SemanticPlannerGate`; convert `ListEditPlanner.toggle` to use the
   shared helper rather than its own inlined copy, proving no behavior change for the three list
   commands.
3. Apply the shared helper to `transformLine`, `toggleCodeFence`, and `toggleBlockQuote`.
4. Confirm the matrix test passes for every command in both modes.
5. Re-run every refusal suite unchanged; no refusal proof may be weakened to make a cell pass.
6. Reconcile REQ-058 and REQ-113 traceability; delete this plan.

## Automated non-UI proof

`CommandLivenessMatrixTests` enumerates `EditorCommand.allCases` × `{source, wysiwyg}`. For each
cell it drives the real `EditorCommandController` bound to a real `MarkdownDocument`/
`EditorSession`, and requires one of exactly two declared outcomes:

- `enabled` → `perform` returns `.accepted` **and** an asserted source postcondition holds; or
- a declared, named refusal reason recorded in an in-test table.

A command with no table entry fails the test. A new `EditorCommand` case therefore fails the
build until its behavior in both modes is declared — the same closed-set discipline
`Scripts/check-instrumentation-coverage.sh` applies to `EditorTraceEvent`.

Selection shapes covered per cell, because the defect is selection-shape-dependent (a partial
`{0,5}` heading selection accepts today while a full-paragraph `{0,16}` selection refuses):

- caret at block start, caret mid-block, caret at block end;
- partial intra-block selection;
- exact whole-block content selection;
- and, retained as refusals, cross-block, synthetic-only, and cross-cell selections.

The WYSIWYG cells must reach the presentation through the authoritative path rather than
`installProjectionForTesting`, which bypasses `ProjectionOracle.validate(snapshot:)` and so
proves the command against a snapshot production would have rejected. Use the
`EditorHarness.settle()` pattern already proven in `PerformanceBoundaryTests`.

## Instrumentation and performance evidence

- No new `EditorTraceEvent` case. `editRefused(category:)` already covers the failure and is the
  record that would have surfaced this defect had any process-level run exercised a command;
  COR-29 closes that separately.
- Each accepted cell asserts `storage.fullReplacements == 0` (ARC-Q16) using the existing spy
  `NSTextStorage`, so restoring liveness cannot reintroduce the COR-23 full-rebuild route.
- Re-record the focused Release native-input callback gate (REQ-090); the caret change is on the
  command path, not the typing path, so no budget movement is expected and a movement is a
  finding.

## Failure and rollback behavior

If a command's post-command caret cannot be placed at a re-projectable concrete source position,
the command refuses atomically as it does today, and the matrix test must declare that refusal
explicitly rather than the command silently remaining unperformable. Source is never partially
mutated. No filesystem or asset state participates.

## Deletion and conformance gate

- Prove no second caret-placement rule exists: exactly one helper on `SemanticPlannerGate`
  computes a post-command caret, and no planner inlines its own arithmetic.
- Prove no alternate command dispatch route was introduced (ARC-024).
- `Scripts/check-documentation-authority.sh` and `Scripts/check-instrumentation-coverage.sh`
  pass; `Scripts/smoke-test.sh` and `Scripts/smoke-screenshot.sh` pass; delete this plan in the
  implementing change.
