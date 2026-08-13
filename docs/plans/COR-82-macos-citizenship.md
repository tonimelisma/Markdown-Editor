# COR-82 — macOS citizenship

- **Status:** Approved; not implemented
- **Delivers:** REQ-130, REQ-131
Architecture impact: none
Blockers: COR-74, COR-75, COR-77, COR-81
Executor: A junior may implement from the declared command/window/document matrix. Any new product command or shortcut needs separate approval.

## Outcome

Finish native document-window and command behavior without custom platform substitutes: frame
restoration/cascading, tabbing, printing, adaptive toolbar/menu organization, approved shortcuts,
list continuation, link insertion at a caret, validation, and multi-window isolation.

## Files and ownership

- `MarkdownDocument` window-controller construction and printing hooks.
- `EditorCommand`, `EditorCommandController`, `EditorMenuCommands`, `EditorToolbarController`,
  link sheet, Return/list planner, and command construction tests.
- Reuse AppKit/SwiftUI standard window, tab, print, menu, toolbar, validation, and key-equivalent APIs.
  Do not create custom frame stores, tab managers, print windows, or global command controllers.

## Implementation

1. Characterize existing integrated behavior first: frame autosave/cascade/tab identifiers and the
   19-command shortcut table already exist. Keep them if route proofs pass; do not reimplement them.
2. Add a closed command matrix across Source/WYSIWYG, caret/selection, editable/unavailable,
   composition, one/two windows, menu/toolbar/shortcut, and ordinary success/refusal.
3. Implement missing Insert/Format organization, toolbar compression, print pagination, heading/block
   key equivalents, list continuation/termination, and caret-only link authoring through shared
   command/transaction owners.
4. Directly construct two documents/windows/controllers and prove validation and execution remain
   window-scoped. Standard document actions stay with NSDocument/AppKit.
5. Force TextKit layout for print/list/link component proofs where visible geometry or insertion is
   the contract; attribute values alone are insufficient.

## Proof and failure behavior

Every advertised command succeeds on ordinary input in every mode where offered. Conflicts with
standard macOS shortcuts fail the matrix. Printing never mutates source/history. Window restoration
is disabled only for smoke fixture launches. Narrow toolbars remain usable without clipping.

## Deletion/conformance gate

One window-scoped command model feeds menu and toolbar. No global controller, duplicate shortcut
table, custom document subsystem, stale compatibility facade, or already-integrated feature rewrite
remains.
