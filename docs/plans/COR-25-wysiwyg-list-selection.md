# COR-25 — WYSIWYG list toggle over an ordinary paragraph

- **Status:** Approved; not implemented

## Scope

Correct the existing REQ-058 command route so an ordinary WYSIWYG paragraph selection can toggle
an unordered list rather than refusing with `mappingFailure`. This preserves the current
source/projection architecture and exact-or-refuse rule; it does not broaden support for mixed,
synthetic, table, or otherwise ambiguous selections.

## Requirements and invariants

- REQ-058: ordered/unordered/task list commands are available through the shared native command
  route in both editor modes.
- REQ-057: regenerate only the smallest proven semantic unit.
- REQ-087 and ARC-007/009: a selection remains exact or atomically refused, never guessed.
- ARC-005/019: an accepted WYSIWYG command advances source and presentation synchronously through
  the bounded patch route.
- Architecture impact: none.

## Production route

Modify the WYSIWYG semantic-command mapping in `SemanticEditEngine` and, only if the failing
characterization proves it necessary, the typed `ProjectionSelectionClassifier` boundary logic.
Preserve `ListEditPlanner` as the sole source transformation owner. The accepted source range
must be derived from the current presentation snapshot's concrete identity mapping and must
cover only the selected ordinary paragraph line.

## Implementation phases

1. Add a component characterization using the real `EditorCommandController`/`EditorSession`/
   WYSIWYG adapter route for `"First paragraph.\n\nSecond paragraph.\n"` and projection range
   `{0,16}`; it must fail on the current `mappingFailure` route.
2. Trace the failing classification or transition proof and correct only the exact mapping gate.
3. Prove the command commits `"- First paragraph.\n\nSecond paragraph.\n"`, updates the visible
   projection synchronously, and uses no full-storage replacement.
4. Retain refusal proofs for mixed, cross-cell, synthetic, and uneditable selections; update
   REQ-058 traceability and remove this implemented plan.

## Failure and completion gates

The correction refuses without mutation if the selection cannot be proven as one ordinary
identity paragraph. Run the focused regression and adjacent command/patch/refusal suites, the
documentation and instrumentation gates, and the window-only screenshot verifier. Delete this
plan in the implementing change and prove no alternate list-command route was introduced.
