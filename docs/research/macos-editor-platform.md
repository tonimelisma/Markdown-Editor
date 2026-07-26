# macOS editor platform evidence

- **Authority:** Evidence only; `../ENGINEERING.md` is authoritative.
- **First researched:** 2026-07-22
- **Last verified:** 2026-07-25
- **Environment:** Xcode 27 beta (`27A5228h`), Swift 6.4, macOS 27 SDK, arm64 Apple silicon
- **Refresh when:** deployment target, Xcode/SDK, document framework, text engine, or concurrency
  policy changes

## Questions

- Which macOS document and text frameworks satisfy native editing and document behavior?
- Which work must remain synchronous, main-actor, or off-main?
- What platform callbacks affect selection, IME, undo, and document I/O?

## Methods

- Built throwaway strict-Swift-6 component POCs for `FileDocument`, macOS 27 SwiftUI `Document`,
  `NSDocument`, TextKit 1 rich storage, selection callbacks, marked text, undo, and concurrent
  parser execution.
- Exercised empty, LF, CRLF, BOM, Unicode, invalid-UTF-8, edit/undo/redo, and persistent-view
  fixtures without UI automation.
- Measured Release parsing, indexing, projection application, and image decoding.
- Inspected current Apple documentation and SDK declarations.
- Removed all POC code after execution.

## Findings

### `NSDocument` is the correct document boundary

`NSDocument` provides stable reference identity, document-owned `UndoManager`, standard
New/Open/Save/Save As/autosave/Versions/tabs/Recents behavior, direct file URL ownership, and
operation-scoped Save completion. A strict Swift 6 POC passed byte fixtures and edit/undo/redo.

The macOS 27 SwiftUI `Document` API was viable but did not provide operation-scoped Save completion
for a dependent image action and introduced no useful replacement for the existing AppKit
document boundary. `FileDocument` value binding and view-discovered document ownership created
avoidable duplicate authority.

Current Apple behavior reports that documents do not read concurrently by default and do not
write asynchronously unless the subclass opts in. A 2026-07-25 probe confirmed the app inherits
both serialized defaults. The architecture therefore does not need a mutex-protected second text
mirror or asynchronous load gate.

Swift imports `read(from:ofType:)` as `nonisolated`, so the compiler cannot infer the runtime
executor. Apple's document guide states that Open/Finder loading moves to a background thread when
`canConcurrentlyReadDocuments` is explicitly enabled; the default is false. Similarly,
`canAsynchronouslyWrite` defaults to false. The direct implementation must retain those defaults,
assert the main thread in both overrides, and enter the main-actor boundary explicitly. An actual
off-main callback under those defaults would invalidate this conclusion and must fail a component
probe rather than be hidden behind a long-lived mirror.

Sources:

- [Apple `NSDocument`](https://developer.apple.com/documentation/appkit/nsdocument)
- [Apple document lifecycle and concurrent reads](https://developer.apple.com/library/archive/documentation/DataManagement/Conceptual/DocBasedAppProgrammingGuideForOSX/ManagingLifecycle/ManagingLifecycle.html)
- [Apple asynchronous document writes](https://developer.apple.com/documentation/appkit/nsdocument/canasynchronouslywrite(to:oftype:for:))
- [Apple SwiftUI `Document`](https://developer.apple.com/documentation/swiftui/document)

### TextKit 1 remains the correct native editing substrate

The TextKit 1 POCs demonstrated:

- persistent literal and attributed editors;
- native replacement, selection, undo/redo, spelling, Find, and marked-text composition;
- parsed delimiters absent from rich storage;
- link attributes and task/image attachments;
- native `NSTextTable`/`NSTextTableBlock`; and
- main-actor construction of AppKit attributed objects from immutable off-main models.

No measured failure justifies TextKit 2 or a third-party editor. TextKit 2 would not remove the
hard source/projection inverse-mapping problem.

`NSTextViewDelegate.shouldChangeTextIn` is the synchronous accept/refuse boundary for native
replacement. `setSelectedRange` posts selection-change notification even for programmatic
changes; a 2026-07-25 component probe confirmed the delegate callback. Programmatic view updates
therefore need an explicit origin and cannot be inferred from callback shape.

`NSTextView` owns transient marked text. Projection replacement during marked text can invalidate
the input-client contract; canonical source should receive one completed composition.

Sources:

- [Apple `NSTextView`](https://developer.apple.com/documentation/appkit/nstextview)
- [Apple `shouldChangeTextIn`](https://developer.apple.com/documentation/appkit/nstextviewdelegate/textview%28_%3Ashouldchangetextin%3Areplacementstring%3A%29)
- [Apple selection-change notification](https://developer.apple.com/documentation/appkit/nstextview/didchangeselectionnotification)
- [Apple text input and marked text](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/TextEditing/Tasks/TextViewTask.html)

### Concurrency is part of correctness

Mutable document and AppKit state belongs on the main actor. Parser, source-index, projection
compiler, hashing, image inspection, and decode accept immutable `Sendable` snapshots. Results
publish only after identity checks.

cmark parsing is synchronous and cannot cooperatively cancel mid-parse. Cancellation checks
before/after save work; revision/location checks provide correctness. Eight parallel
parser/source-map runs produced identical results.

Swift 6 complete concurrency checking is a hard gate. A background test that captured a mutable
`MarkdownDocument` generated a data-race warning in the 2026-07-25 Release spike, directly
supporting removal of the custom I/O bridge rather than weakening isolation.

Sources:

- [Apple adopting Swift 6](https://developer.apple.com/documentation/swift/adoptingswift6)
- [WWDC24: Migrate your app to Swift 6](https://developer.apple.com/videos/play/wwdc2024/10169/)

## Measurements

Baseline Release measurements from the architecture POC:

| Input | Parse + AST/source map median | p95 | Source index median | p95 |
|---:|---:|---:|---:|---:|
| 954 bytes | 0.070 ms | 0.094 ms | 0.005 ms | 0.006 ms |
| 9,964 bytes | 0.686 ms | 0.763 ms | 0.045 ms | 0.046 ms |
| 99,958 bytes | 4.809 ms | 6.471 ms | 0.347 ms | 0.394 ms |
| 999,951 bytes | 53.273 ms | 58.486 ms | 3.388 ms | 3.392 ms |

Selected-design follow-up:

| Operation | Median | p95 |
|---|---:|---:|
| local edit translation | 0.000708 ms | 0.000750 ms |
| representative attributed-storage application | 0.097 ms | 0.123 ms |
| 1280×854 HEIC bounded thumbnail decode | 10.900 ms | 12.211 ms |

The storage measurement excludes glyph layout. The image measurement includes detached scheduling
and decode.

The 2026-07-25 COR-09 spike additionally proved:

- the current consecutive WYSIWYG failure: first input commits, second refuses as stale before
  authoritative parsing catches up;
- a synchronous provisional source/map transition on the 100,000-unit corpus passes the existing
  8 ms p95 edit-translation gate;
- full off-main parse/projection passes the existing 100 ms p95 gate;
- serialized `NSDocument` defaults; and
- programmatic selection notification.

All seven focused probes passed in Release with `ENABLE_TESTABILITY=YES`; the temporary test file
was deleted. Release testability must be enabled explicitly because the app target otherwise
cannot be imported by the test bundle.

## Durable conclusions

- Keep `NSDocument`, TextKit 1, two persistent editors, and the main-actor AppKit boundary.
- Do not place a full parser round-trip between consecutive keystrokes.
- Advance exact presentation state synchronously, then reconcile off-main.
- Treat programmatic callbacks as explicit-origin events.
- Use default serialized document I/O unless new measured platform behavior invalidates it.
