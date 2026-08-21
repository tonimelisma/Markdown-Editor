# COR-74 — Document files and lifecycle proof

- **Status:** Approved; not implemented

- **Delivers:** REQ-002, REQ-003, REQ-004, REQ-005, REQ-006, REQ-013, REQ-014, REQ-015, REQ-017, REQ-019, REQ-020, REQ-021

Architecture impact none; verifies/corrects NSDocument ownership ARC-001/ARC-Q04.

Blockers COR-68.

## Scope

Prove New/open/read/write/autosave/Versions/tabs/Recents, operation-scoped Save outcomes, file-location generation, and default serialized NSDocument behavior. Do not change editing, presentation, image placement, commands, or visual design.

## Implementation

Add direct lifecycle contract tests and byte-fidelity fixtures. Prove standard AppKit behavior through direct component construction and framework-inherent routes. Remove duplicate document owners if found. Register one falsifying mutation for each delivered requirement and promote rows only after the focused tests, changed-scope falsification, and full gate pass.

## Failure condition

Invalid input or cancelled Save mutates no source/location/history; one NSDocument remains the source/location/version/undo owner; no custom recent/tab/version/autosave subsystem exists; and all required gates pass. If a review finds a proof gap, keep affected rows in Correction and this plan in place until the corrected proofs are observed.
