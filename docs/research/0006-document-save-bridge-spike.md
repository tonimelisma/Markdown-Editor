# RESEARCH-0006 — DocumentGroup Save bridge spike

- **Date:** 2026-07-24
- **For:** COR-02 / ADR-0012 §3
- **Type:** native-API investigation
- **Status:** Done
- **Outcome:** Feasible. Untitled placement can resolve the owning `NSDocument` for the editor
  window and bridge `saveDocumentWithDelegate:didSaveSelector:contextInfo:` without global sheet
  observers.

## Question

Does a SwiftUI `DocumentGroup` window for this app’s `FileDocument` reliably expose an owning
`NSDocument` so placement can initiate normal Save and receive an operation-scoped completion?

## Method

- Inspected the macOS 27 AppKit SDK headers for `NSDocumentController.document(for:)` /
  `documentForWindow:` and `NSDocument.saveDocumentWithDelegate:didSaveSelector:contextInfo:`.
- Confirmed the shipping app already routes untitled Save through
  `NSApp.sendAction(#selector(NSDocument.save(_:)), …)`, which only succeeds when an `NSDocument`
  is in the responder/document graph for the key window.
- Cross-checked Apple’s `DocumentGroup` guidance: the configuration `fileURL` remains the
  authoritative document location; the Save callback is the authoritative terminal signal.

No production code was merged from this spike.

## Findings

1. **Resolution API exists and is supported.**
   `NSDocumentController.shared.document(for: window)` returns the document bound to that window.
   Falling back to `window.windowController?.document as? NSDocument` covers the same ownership
   when the controller is present.

2. **DocumentGroup participates in the AppKit document architecture on macOS.**
   The existing INC-03 path’s successful `NSDocument.save(_:)` action dispatch is empirical proof
   that untitled and saved `DocumentGroup` windows in this app have an `NSDocument` target. The
   correction replaces the global sheet observer with the document’s own save-completion selector.

3. **Completion signature is stable.**
   The did-save selector receives `(NSDocument, Bool /*didSaveSuccessfully*/, contextInfo)`.
   Success plus a subsequent non-nil matching `DocumentGroup` `fileURL` is the resume gate from
   ADR-0012. Cancel and failure both invoke the callback with `didSaveSuccessfully == false`.

4. **Bridge shape for PLAN-0005.**
   Inject a `@MainActor` adapter that:
   - resolves `NSDocument` from the text view’s window;
   - calls `saveDocumentWithDelegate:didSaveSelector:contextInfo:`;
   - resumes a checked continuation exactly once from the `@objc` callback;
   - lets the placement controller wait for the live `fileURL` for that same document generation
     before leaving `awaitingSave`.

## Outcome

The Save bridge is approved for implementation. No ADR/plan revision is required for §3.
