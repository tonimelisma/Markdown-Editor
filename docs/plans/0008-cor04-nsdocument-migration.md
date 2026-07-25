# PLAN-0008 — COR-04 NSDocument migration

- **Increment:** COR-04
- **Date:** 2026-07-25
- **Status:** Proposed — requires explicit approval before code
- **Requirements:** REQ-013–REQ-019
- **Depends on:** [RESEARCH-0007](../research/0007-document-model-and-wysiwyg-architecture.md),
  [ADR-0006](../decisions/0006-document-model-filedocument.md),
  [ADR-0010](../decisions/0010-concurrency-highlighting-pipeline.md),
  [ADR-0012](../decisions/0012-transactional-descriptor-relative-image-placement.md)

> This is a prerequisite infrastructure build, not INC-04. It migrates document ownership without
> adding WYSIWYG, a parser dependency, toolbar controls, or new image storage behavior.

## Goal

Replace the value-type `FileDocument`/`DocumentGroup` ownership path with one `NSDocument` per
file while preserving every currently shipped behavior and byte invariant. At completion,
canonical source, URL/location generation, operation-scoped Save, source transactions, and undo
have one document owner that future Source and WYSIWYG adapters can share.

## Invariants

1. `NSDocument` is the only document/source owner; no shadow `FileDocument`, compatibility model,
   or view-owned canonical string remains.
2. The serialized representation is exactly `Data(source.utf8)`; no metadata or package is added.
3. Empty, LF, CRLF, BOM, Unicode, and valid unedited UTF-8 round-trip byte-for-byte; invalid UTF-8
   remains a read error.
4. Every accepted source transaction advances one source version and registers one logical undo
   action on the document's `UndoManager`.
5. Views receive a document interface. No controller discovers its document by walking from an
   `NSView`.
6. COR-02 storage, staging, hashing, publication, exact-copy HEIC/HEIF, and rollback types remain
   unchanged.
7. AppKit/document mutable state stays on the main actor. Background I/O receives immutable
   `Sendable` snapshots and cannot mutate live source.
8. The migration retains standard Open, New, Save, Save As, autosave, Versions, tabs, Recents,
   close, and reopen behavior by using the native `NSDocument` lifecycle.
9. No UI tests or manual verification are accepted.

## Architecture

### `MarkdownDocumentData`

A small `Sendable` value owns the pure byte contract:

- `init(data:) throws` uses strict UTF-8 validation that preserves BOM and line endings;
- `data()` returns exact UTF-8 bytes; and
- fixtures are shared with the existing `Markdown_EditorDocument` tests.

This isolates byte correctness from AppKit lifecycle and lets the old `FileDocument` type be
deleted rather than retained as a codec.

### `MarkdownDocument: NSDocument`

The document owns:

- canonical `String`;
- monotonically increasing source version;
- document-location generation;
- testable location/save event stream;
- its inherited `UndoManager`; and
- a narrow observable editor-state publisher for SwiftUI.

It overrides `read(from:ofType:)`, `data(ofType:)`, `makeWindowControllers()`, and
`autosavesInPlace`. Thread-safe snapshot storage satisfies `NSDocument` read/write callbacks;
all editor mutations and observation delivery are main-actor operations. Background callbacks
never receive the live document reference.

### `SourceTransactionEngine`

Introduce one document-owned value transaction boundary:

```swift
struct SourceSnapshot: Sendable {
    let text: String
    let sourceVersion: UInt64
    let locationGeneration: UInt64
    let fileURL: URL?
}

struct SourceEdit: Sendable {
    let expectedVersion: UInt64
    let range: NSRange
    let replacement: String
    let actionName: String
}

enum SourceEditResult: Sendable {
    case committed(SourceSelection)
    case refused(SourceEditRefusal)
}
```

The engine validates version/range, captures replaced text, mutates canonical source once,
advances the version once, registers inverse undo through the document, marks the document
changed, and publishes one update. Stale, invalid, or conflict input changes nothing.

The Source view still performs native keystrokes synchronously. Its adapter reports the exact
accepted replacement to the engine rather than copying the entire storage back through a SwiftUI
binding.

### App lifecycle and window hosting

Replace `DocumentGroup` with the standard AppKit document stack:

- an app bootstrap owns the shared `NSDocumentController`;
- `MarkdownDocument.makeWindowControllers()` creates an `NSWindowController`;
- the window content is an `NSHostingController` whose root is
  `ContentView(document: MarkdownDocument)`; and
- File menu commands route through the responder chain/`NSDocumentController`.

SwiftUI remains the content/layout layer. AppKit owns only the document/window lifecycle it is
specifically better at.

### `DocumentActionInterface`

`ContentView`, `MarkdownTextView`, and `ImagePlacementController` receive one explicit interface
for:

- current source snapshot;
- active source selection capture/tracking;
- source transaction commit;
- document URL and location generation;
- operation-scoped Save; and
- the document-owned undo manager.

COR-02's `DocumentSaveBridge.document(for:)`, `MarkdownSourceTextView.documentURL`, weak source-view
ownership, and final `insertImageMarkdown` dependency are removed. The placement controller keeps
its existing transaction state machine and calls the new interface.

## Steps

1. **Extract and lock the byte contract — REQ-015.**
   - Add `MarkdownDocumentData`.
   - Move all current document byte fixtures to it before removing `FileDocument`.
   - Add zero-edit and repeated read/write snapshot tests.
2. **Introduce source snapshots and transactions — REQ-013/016/018.**
   - Add the value types and typed refusal enum.
   - Test exact UTF-16 replacement, Unicode boundaries, version advancement, invalid/stale
     refusal, one undo group, redo, and immutable background snapshots.
3. **Build `MarkdownDocument` — REQ-013–REQ-019.**
   - Implement `NSDocument` read/write/autosave and location generation.
   - Inject Save execution in tests so success/cancel/failure are deterministic.
   - Test undo ownership and URL-generation notifications without windows.
4. **Replace app/document window ownership — REQ-014.**
   - Add the AppKit document bootstrap/window controller/SwiftUI hosting boundary.
   - Delete the `DocumentGroup` scene and `Markdown_EditorDocument`.
   - Verify menu validation and lifecycle through responder/document-controller component seams,
     never screen automation.
5. **Adapt Source editing — REQ-016.**
   - Replace `Binding<String>` with the document interface.
   - Keep the existing `MarkdownSourceTextView`, highlighter, native insertion, Find, spelling,
     selection, and paste/drop behavior.
   - Remove whole-storage writeback and view-owned undo authority.
6. **Adapt COR-02 — REQ-017/019.**
   - Route capture, tracking, Save, URL, source read, commit, and selection through
     `DocumentActionInterface`.
   - Delete `DocumentSaveBridge` and the controller's weak source-view dependency.
   - Leave every storage/filesystem implementation file unchanged except interface wiring.
7. **Remove superseded paths.**
   - Delete old value-binding, view-derived document lookup, duplicate URL state, and compatibility
     shims.
   - Search for `FileDocument`, `DocumentGroup`, `DocumentSaveBridge.document(for:)`, and
     view-owned canonical writes; none may remain outside historical docs/tests.
8. **Reconcile traceability before PR.**
   - Add REQ anchors to new code/tests, update REQUIREMENTS status/locations and ROADMAP, and
     record any implementation-level correction in ADR-0006.

## Automated verification

| Requirement | Verification |
|---|---|
| REQ-013 | one document/source/version/undo owner component tests; old owner absence inspection |
| REQ-014 | `NSDocumentController`/window-controller/responder component tests and inherent native framework behavior |
| REQ-015 | empty/LF/CRLF/BOM/Unicode/invalid-UTF-8/zero-edit byte tables |
| REQ-016 | exact-range/Unicode/stale/invalid/conflict tables and cross-adapter undo/redo |
| REQ-017 | injected untitled Save success/cancel/failure tests |
| REQ-018 | strict Swift 6 build, `Sendable` snapshots, executor identity tests |
| REQ-019 | URL/location-generation, dependent-resolution, editor-neutral adapter, and full existing COR-02 suite |

Run the complete existing unit suite after each ownership cutover. No UI-test target is run or
added.

## Migration and rollback

Build on one app-code worktree/branch. Keep commits ordered so the byte contract and transaction
engine precede the ownership cutover. Before INC-04 depends on the interface, rollback is a normal
revert of the squash merge. Do not retain both document implementations as runtime fallbacks.

No project-setting change is expected. If the implementation proves one necessary, follow the
repository's project-config-on-`main` rule as an explicit prerequisite commit immediately before
the app-code worktree; never leave `main` unable to build.

## Risks

- `NSDocument` callbacks may arrive outside the main actor: isolate byte snapshots and prove actor
  boundaries under strict concurrency rather than annotating away warnings.
- SwiftUI observation can create recursive writeback: publish document versions/snapshots in one
  direction and commit only through transactions.
- Native lifecycle regression: use `NSDocumentController` and responder-chain APIs directly;
  avoid recreating Save/close logic.
- COR-02 regression: adapt its boundary only and require the entire existing suite unchanged.

## Out of scope

- WYSIWYG projection, parser dependency, toolbar, task/link rich controls
- Changes to Markdown dialect semantics
- Image storage/promise/filesystem rewrites
- Rich paste or table behavior
- UI tests or manual acceptance
