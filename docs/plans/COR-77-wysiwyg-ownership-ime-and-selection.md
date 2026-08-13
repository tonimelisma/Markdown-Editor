# COR-77 — WYSIWYG ownership, IME, selection, and undo

- **Status:** Approved; not implemented
- **Delivers:** REQ-052, REQ-079, REQ-080, REQ-082, REQ-083, REQ-084, REQ-086, REQ-087, REQ-089, REQ-093, REQ-094
Architecture impact: none; closes ARC-002 through ARC-013 at the native adapter boundary
Blockers: COR-70, COR-71, COR-76
Executor: A junior developer may implement from the closed callback matrix. Obtain senior review of IME and re-entrancy transitions before changing production adapters.

## Scope and files

Own `WYSIWYGEditor` construction/input/application/interaction/layout components,
`EditorTransactionKernel`, `EditorSession`, projection coordinate types, marked-text state,
selection/affinity/scroll snapshots, undo integration, mode switching, and editor-host reconciliation.
Image display and placement belong to COR-73/COR-78.

## Implementation

1. Enumerate native callbacks: insert, replace, delete, set/unmark marked text, selection change,
   paste text, drag text, undo, redo, checkbox press, programmatic patch, mode switch, attach/detach,
   and SwiftUI reconciliation. Assign origin and allowed state transition to every case.
2. Add directly constructed component tests for Unicode/graphemes, UTF-16 boundaries, caret/range
   affinity, multi-range rejection, composition update/commit/cancel, commands during composition,
   stale projection, rapid mode toggles, scroll restoration, undo grouping, and re-entrant callbacks.
3. Route user input once through the kernel. Capture AppKit state before planning; apply returned
   source/presentation/selection/undo atomically; suppress callbacks from programmatic application.
4. Keep two persistent native editors and one typed session state per mode. Mode changes never mutate
   source and unavailable WYSIWYG never exposes stale editable content.
5. Split oversized coordinators so no object both captures native input and owns document mutation,
   parsing, layout policy, interaction state, and result application.

## Proof and failure behavior

Every offered route has ordinary-input liveness. Accepted actions advance source/presentation/map/
selection/undo once; refused or stale actions change none. Marked text is transient until commit and
is never duplicated. Reconciliation publishes/captures no live state and unchanged updates are
no-ops. Blocked authoritative parsing does not block locally supported typing.

## Deletion/conformance gate

The closed callback matrix maps every entry to one owner and origin. No adapter-local document
mutation, duplicate IME commit, selection clamping, compatibility state, or hidden full parse/apply
route remains. All requirement-specific mutations fail a route-level proof.
