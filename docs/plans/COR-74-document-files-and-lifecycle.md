# COR-74 — Document files and lifecycle proof

- **Status:** Approved; not implemented
- **Delivers:** REQ-002, REQ-003, REQ-004, REQ-005, REQ-006, REQ-013, REQ-014, REQ-015, REQ-017, REQ-019, REQ-020, REQ-021
Architecture impact: none; verifies and corrects the NSDocument ownership boundary in ARC-001 and ARC-Q04
Blockers: COR-68
Executor: A junior may implement this plan exactly. Stop for discovery if an NSDocument behavior cannot be proved by direct construction or a documented framework contract.

## Scope

One vertical document boundary: new/open/read/write/autosave/Versions/tabs/Recents, operation-scoped
Save outcomes, file-location generation, and default serialized NSDocument behavior. Do not change
editing, presentation, image placement, commands, or visual design.

## Files and ownership

- Production: `MarkdownDocument.swift`, `MarkdownDocumentData.swift`, `MarkdownContentType.swift`,
  app/document-controller setup, and `Info.plist` only if a reproduced defect requires it.
- Tests: add `DocumentLifecycleContractTests.swift` and extend byte-fidelity fixtures. Construct
  documents/controllers directly; no XCUITest, accessibility automation, or screen driving.
- Diagnostics: reuse typed document I/O records; add a case only when a real lifecycle outcome has
  no representation and give it a production route in the same change.

## Implementation

1. Build a requirements matrix with one ordinary-success and each declared failure/cancellation case.
   Record current responsible symbol before editing production.
2. Add discriminating tests for empty untitled creation; valid open; invalid UTF-8 refusal; zero-edit
   empty/BOM/CRLF/Unicode round trip; edit autosave handoff; operation-scoped Save success/cancel/
   failure; URL generation; New/Open/Save As; Versions construction; tabs; and Recents.
3. For framework-inherent behavior, cite the exact public API and prove the app has not intercepted
   or disabled it. If direct construction exposes a defect, fix the single NSDocument owner rather
   than adding an app-level shadow state.
4. Remove any duplicate location, save-state, or source authority discovered. Keep fixture writes in
   temporary directories and prove repository fixtures remain unchanged.
5. Promote only rows whose named success/failure proofs pass and whose production mutation turns a
   cited proof red. Leave any unresolved row `Correction`.

## Failure and conformance

Invalid input and cancelled Save mutate no source/location/history. Stale async outcomes apply
nothing. `MarkdownDocument` remains the sole source/location/version/undo owner; no custom recent,
tab, version, or autosave subsystem is introduced. Full checks and process smoke pass.

## Deletion/conformance gate

Compiler visibility and a structural owner test find no second source, location, revision, undo,
autosave, Versions, tabs, or Recents owner. Every promoted row names its current production route,
observed liveness proof, and behavior-discriminating mutation.
