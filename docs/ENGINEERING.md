# ENGINEERING

The authoritative current engineering architecture. It describes how the application is allowed
to work today. Production code, tests, this document, and the current requirements must agree.

This is not a history or a proposal. Historical alternatives and experiments belong in
`research/`; approved but unimplemented work belongs in `plans/`; implemented plans are deleted.
Git retains history.

## 1. Architecture drivers

In priority order:

1. **Source fidelity:** untouched bytes and unfamiliar syntax survive.
2. **Edit integrity:** accepted input is applied exactly once at the visible selection.
3. **Native behavior:** TextKit/AppKit document, input, selection, IME, undo, spelling, Find, and
   accessibility semantics remain intact.
4. **Interoperability:** formal GFM is the only generated Markdown dialect.
5. **Deterministic failure:** ambiguity refuses atomically; no clamping, guessing, or partial edit.
6. **Responsiveness:** synchronous edit translation stays below the interactive budget while
   parsing and image work remains off-main.
7. **Maintainability:** one owner, one representation boundary, and one mutation route per concern.

These priorities resolve trade-offs. A design that is faster but can misapply input is invalid.
A design that preserves content by silently creating a second canonical representation is invalid.

## 2. System shape

The app is a native Swift 6 macOS document application:

- `NSDocument` owns each open Markdown document.
- SwiftUI owns application composition and toolbar presentation.
- Narrow AppKit adapters host two persistent TextKit 1 `NSTextView` editors.
- Source mode uses literal Markdown plus an independent lexical highlighter.
- WYSIWYG uses attributed rendered content compiled from pinned direct cmark-gfm semantics and
  exact concrete-source coordinates.
- Image placement is one editor-neutral transaction used by paste, drag-and-drop, and Add Image.
- Parser, source-index, projection compilation, hashing, image inspection, and image decoding run
  from immutable snapshots away from the main actor.

TextKit 2, hidden-delimiter storage, an AST or rich text as canonical state, whole-document rich
serialization, web contenteditable, and duplicate image pipelines are not part of the architecture.

## 3. Authority and state

Every mutable fact has exactly one owner.

| State | Kind | Sole owner | Persistence |
|---|---|---|---|
| Markdown bytes/text | canonical | `MarkdownDocument` | file |
| Source revision | canonical ordering token | `MarkdownDocument` | process lifetime |
| File URL/location generation | canonical document identity | `MarkdownDocument` | document session |
| Undo/redo history and typing groups | canonical history | `MarkdownDocument` | document session |
| Active mode | window state | `EditorSession` | window lifetime |
| Source selection/affinity/scroll | mode state | `EditorSession.SourceModeState` | window lifetime |
| WYSIWYG selection/affinity/scroll | mode state | `EditorSession.WYSIWYGModeState` | window lifetime |
| Presented WYSIWYG text, attributes, coordinate map, revision | derived presentation snapshot | `EditorSession` | replaceable |
| Authoritative parse tree/projection | derived reconciliation result | `EditorSession` | replaceable |
| Marked text/IME composition | transient native input | active `NSTextView`, coordinated by session | one composition |
| Image-placement selection | immutable operation intent | placement operation | one operation |
| Decoded image cache | derived bounded cache | `LocalImageCache` | replaceable |
| Diagnostic run record | derived append-only evidence | `DiagnosticLog` | one file per application run |
| Asset files | external ordinary files | user/filesystem | persistent outside app state |

Rules:

- Canonical, derived, provisional, and transient state are distinct types or fields.
- `EditorSession` owns mode state directly. There is no second view-state owner, type alias, raw
  domain enum, or compatibility selection model.
- The document never stores projection-domain selections.
- A view may report native state; it does not become the authoritative owner of session state.
- Ownership and publication are separate concerns. Session state is published to SwiftUI only
  when a view body renders it. Selection, affinity, scroll offset, the authoritative tree, and
  the one-shot selection instruction are session-owned and unpublished; mode, presentation
  snapshot, and resolved images are session-owned and published.
- Publishing state that no view renders is forbidden: it invalidates the view graph for a fact
  the graph does not consume.
- A parser result is never canonical and may be discarded without data loss.
- Presented WYSIWYG text and its coordinate map are one indivisible snapshot with one revision.

## 4. Coordinates and revisions

Source and projection coordinates are different domains and must be unmixable in production APIs.

- `SourceRevision` identifies canonical document content.
- `ProjectionRevision` identifies one exact presented WYSIWYG snapshot.
- `SourceSelection` contains a source UTF-16 range and affinity.
- `ProjectionSelection` contains a projection UTF-16 range, affinity, and projection revision.
- Conversion returns either an exact typed result or a typed refusal.
- Coordinates are never clamped, proportionally distributed, inferred from repeated text, or
  accepted merely because two numeric revisions happen to match.

A presentation snapshot identity covers all content needed to edit it: source revision, rendered
string, attributes/attachments, segment map, structural metadata, and relevant location
generation. Partial replacement is forbidden.

## 5. Edit transaction

### Source edit

1. The source `NSTextView` asks its delegate whether a native replacement may occur.
2. The adapter forms an exact `SourceEditRequest`.
3. The session validates the request against the current document revision.
4. The document commits one `SourceMutation`, advances once, and registers undo.
5. Native source storage and the session's source selection are updated with explicit
   programmatic origin.
6. Asynchronous parse/projection reconciliation is scheduled.

### WYSIWYG edit

An accepted WYSIWYG edit is a synchronous atomic transition:

1. The view submits an immutable native replacement and current `ProjectionSelection`.
2. The session classifies the entire selection against the exact presented snapshot.
3. The semantic engine returns either:
   - `AcceptedEdit { sourceMutation, presentationTransition, selectionAfter }`, or
   - a typed refusal with no mutation.
4. For an accepted edit, the document commits the source mutation once.
5. Before the input callback returns, the session applies the matching presentation transition
   and selection. The next keystroke therefore targets the new source and presentation revisions.
6. An off-main authoritative parse/projection is scheduled.
7. Reconciliation may replace the provisional snapshot only if its complete input identity still
   matches current state.

It is forbidden to commit source and leave the old projection editable while waiting for parsing.

### Literal WYSIWYG typing

Typing inserts visible content; it is not a formatting command. `MarkdownLiteralEncoder` derives
the minimum source spelling needed for the intended literal content in its exact CommonMark/GFM
context. It may escape or encode Markdown punctuation in source, but the WYSIWYG presentation
shows the literal character without exposing the protective source syntax.

Formatting is performed by semantic toolbar/menu commands. If literal encoding cannot be proven,
the edit refuses before source mutation.

### Selection classification

The whole selected range is classified before an edit:

- identity text;
- atomic source representation with a proven decoder/encoder;
- synthetic presentation with an explicit insertion policy;
- one editable table cell;
- unsupported/uneditable content; or
- mixed/ambiguous content.

Cross-cell table edits, mixed structural domains, unsupported normalized source, and any
unprovable edit refuse atomically. Partial selection mutation is forbidden.

## 6. Projection model

Projection compilation uses pinned cmark-gfm semantics plus the original source.

Every presented atom is one of:

1. **Identity:** visible UTF-16 corresponds exactly to source UTF-16.
2. **Atomic source representation:** visible content differs from source spelling, but a concrete
   decoder and inverse encoder prove the transformation.
3. **Synthetic:** presentation does not correspond to source text and has an explicit insertion
   boundary policy.
4. **Uneditable:** rendering is safe but an exact inverse mutation is not proven.

Entity and escape decoding follows the pinned cmark/CommonMark rules, not an application-specific
table or fallback. List/task markers and other editable synthetic controls carry their exact
source representation. Tables use escape-aware concrete cell coordinates. A normalized inline or
fenced-code representation is editable only when its inverse is proven.

`ProjectionOracle` validates:

- rendered content and attributes;
- complete, ordered, non-overlapping segment coverage;
- legal zero-length boundaries and affinity;
- exact round-trip mappings where promised;
- source postconditions after semantic edits; and
- refusal for every unsupported or mixed case.

## 7. Native editor integration

- Both TextKit 1 editors exist for the window lifetime. Mode changes alter visibility and focus;
  they do not recreate views or rewrite source.
- View reconciliation is a pure reader of session state. `updateNSView` rebinds references,
  applies a newer presentation snapshot, restores a pending one-shot selection, and applies a
  mode change. It publishes nothing and captures no live AppKit state.
- Applying a mode is driven by an actual mode change, not by reconciliation. Reconciling an
  unchanged mode performs no work and mutates no session state.
- Live native selection, affinity, and scroll offset enter the session only from real AppKit
  event callbacks — selection-change and bounds-change notifications — and only under
  `nativeUserInput` origin. Programmatic restoration never writes back.
- WYSIWYG is enabled only when its presentation snapshot matches current source/location state.
  Otherwise it is visibly unavailable until a current snapshot exists; stale rich content is
  never editable.
- `EditorUpdateOrigin` distinguishes native user input, programmatic projection application,
  selection restoration, mode restoration, undo/redo, and composition handling.
- Programmatic `setSelectedRange` notifications must not close typing groups or masquerade as user
  selection changes.
- Selection restoration is a one-shot session instruction consumed by the relevant adapter.
- `NSTextView` owns marked text. Canonical source receives one completed composition transaction;
  projection replacement never occurs through active marked text.
- Native plain-text paste, spelling, Find, keyboard input, selection, and accessibility remain
  available. There are no UI-test dependencies.

## 8. Document and concurrency model

- `MarkdownDocument` is main-actor-owned mutable state.
- AppKit's default serialized `NSDocument` read/write behavior is used. The app does not maintain
  a second mutex-protected text mirror or asynchronous load gate unless a future measured platform
  requirement proves it necessary.
- Swift imports the data-read override as `nonisolated`, but AppKit performs background document
  opening only when the subclass opts into concurrent reads. The override asserts the main thread
  under the retained default and enters `MainActor.assumeIsolated` for the canonical load.
- Asynchronous writes remain disabled. The data-write override likewise asserts the serialized
  main-thread contract and snapshots canonical document data inside the main-actor boundary.
- A failed executor assertion is an architecture counterexample, not permission to restore a
  long-lived mirrored source.
- Background work receives immutable `Sendable` value snapshots only.
- Background work never captures a mutable document or AppKit object.
- Results publish on the main actor only after complete source revision, location generation, and
  operation identity checks.
- Cancellation is an optimization; identity checks are the correctness boundary.
- Swift 6 complete concurrency warnings are failures, including warnings in tests.

## 9. Undo and selection

- All source changes use one document-owned mutation route.
- Typing coalesces until a real boundary: user selection change, mode change, focus/action
  boundary, or discrete command.
- Programmatic selection notifications do not create boundaries.
- Toolbar actions, task toggles, link edits, image insertion, and table edits are discrete unless
  explicitly defined as typing.
- History stores source-domain before/after selections with the patch.
- Undo and redo validate current content, apply exactly once, and publish one one-shot selection
  restoration.
- Asset files are not part of text undo.

## 10. Image placement

Paste, drag-and-drop, and Add Image create immutable claims and enter one transaction:

1. Capture an immutable source-domain selection intent before asynchronous work.
2. Save an untitled document through its operation-scoped `NSDocument` action.
3. Inspect and stage all claims off-main.
4. Validate actual PNG/JPEG/GIF/HEIC/HEIF representation.
5. Copy file-backed images byte-for-byte; never transcode HEIC/HEIF.
6. Publish every required contained destination without overwriting.
7. Commit one ordered Markdown source mutation only after all files exist.
8. On failure, remove only action-owned temporary/new files proven by identity.

The shared `assets/` directory is not app-owned. Symlinks, aliases, packages, non-regular sources,
symlinked destinations, and path escape are rejected.

## 11. Instrumentation and diagnostics

Instrumentation is local evidence, not telemetry. Nothing is transmitted. Records are written to
ordinary files the user owns and can read, delete, or ignore.

- One JSON Lines file per application run under `~/Library/Logs/Markdown Editor/`. Line-oriented
  so a truncated or crashed run stays parseable.
- The first record identifies the run: schema version, run identifier, build, host kind
  (`production` or `unitTest`), OS version, and process identifier. Its fields are fixed process
  facts, so the closed payload value type below does not constrain them. A final record marks
  clean termination, so a reader distinguishes a crash from an orderly exit.
- Every record carries wall-clock time, monotonic seconds since launch, a strictly increasing
  sequence number, a level, a category, an event name, and a flat payload.
- Payload values are a closed type admitting integers, doubles, booleans, and code-defined
  symbols. There is no string case. Recording document text, replacement text, selected text, a
  URL, a description, a filename, or a path is not prevented by review — it is unrepresentable.
- Documents appear as opaque per-run handles, never as names or paths.
- Repeated events collapse into a counted summary above a rate threshold, so a defect that fires
  every run-loop pass produces bounded evidence instead of an unbounded file. Faults are never
  collapsed: they are the evidence.
- Records buffer on the main actor and are appended by a serialized actor off the main actor;
  the editing path never performs synchronous file I/O, and record order is preserved. Faults
  flush immediately, and the terminating record is made durable before the process may exit.
- Retained runs and per-file size are bounded; the oldest runs are removed first.
- A background watchdog races a hop onto the main actor against a one-second threshold. A stall
  is recorded while it is still in progress, so an unrecovered stall is reported too; a second
  record carries the measured duration once the hop lands.
- Reconciliation instrumentation records any session publication during view reconciliation, and
  the host-update meter reports a sustained update rate — the signature of a self-feeding loop,
  which presents as high CPU rather than as a hang.

There is no second instrumentation route. `os_log` is not used for editor events.

## 12. Quality scenarios

| ID | Scenario and measure |
|---|---|
| ARC-Q01 | Given a current editable WYSIWYG snapshot, 100 consecutive accepted insertions appear exactly once and in order; zero are refused merely because authoritative parsing is pending. |
| ARC-Q02 | A WYSIWYG edit either advances source and presentation together before return or changes neither. No observable state contains new source with an editable old projection. |
| ARC-Q03 | A stale parse, projection, image decode, load, or placement result performs zero state applications. |
| ARC-Q04 | Opening and saving without edits preserves the byte fixtures exactly, including empty, BOM, CRLF, and Unicode cases; invalid UTF-8 refuses. |
| ARC-Q05 | On the approved 100,000 UTF-16 corpus in Release: keystroke translation p95 <8 ms, mode toggle p95 <16 ms, off-main parse/index/projection p95 <100 ms. |
| ARC-Q06 | Parser, source-index, projection compilation, image inspection/decode, hashing, and file I/O do not execute on the main actor. |
| ARC-Q07 | Every supported presentation atom satisfies the oracle; every unsupported, cross-cell, mixed-domain, or unprovable selection refuses without mutation. |
| ARC-Q08 | Mode changes preserve each mode's logical selection/affinity/scroll and never change source. |
| ARC-Q09 | File-backed PNG/JPEG/GIF/HEIC/HEIF fixtures retain exact bytes and metadata; display decoding creates no intermediate JPEG or PNG. |
| ARC-Q10 | Instrumentation proves routing, revision, result, refusal class, and timing, and cannot represent document content, selected content, URLs, descriptions, filenames, or paths. |
| ARC-Q11 | Opening a document and leaving the window idle performs a bounded number of editor-host view updates and settles; sustained reconciliation without user input is a reported fault. |

## 13. Architectural invariants and proof

| ID | Invariant | Required proof |
|---|---|---|
| ARC-001 | One canonical source, revision, URL generation, and undo owner: `MarkdownDocument`. | type/API inspection; document transaction tests |
| ARC-002 | One session-owned typed state per editor mode; no parallel compatibility state. | compiler types; documentation/source conformance check |
| ARC-003 | Presented string, attributes, structure, coordinate map, and revision form one snapshot. | snapshot construction API; oracle |
| ARC-004 | Editable WYSIWYG always matches current canonical source/location identity. | state-machine tests and traces |
| ARC-005 | Accepted WYSIWYG edits advance source and presentation synchronously and exactly once. | reducer/adapter integration tests; rapid-input property tests |
| ARC-006 | Background reconciliation cannot overwrite newer state. | adversarial generation tests and traces |
| ARC-007 | Coordinate conversion is exact or refused; never guessed or clamped. | typed APIs; projection oracle; generated fixtures |
| ARC-008 | Literal typing and semantic formatting are separate commands. | punctuation/context fixtures; toolbar tests |
| ARC-009 | Unsupported, mixed, cross-cell, and unprovable edits refuse atomically. | exhaustive selection-classification tests |
| ARC-010 | All text changes and history use one document-owned source mutation path. | API restriction; history tests |
| ARC-011 | Mutable document/AppKit state remains main-actor-owned; background work uses immutable values. | Swift 6 complete-concurrency clean build |
| ARC-012 | Image entry points share one exact-copy, contained, non-destructive transaction. | route tests; filesystem adversarial suite |
| ARC-013 | Programmatic view updates cannot masquerade as user input or alter undo grouping. | explicit origin type; callback tests |
| ARC-014 | No production or verification claim depends on manual or UI testing. | target/source conformance check |
| ARC-015 | Editor-host view reconciliation publishes no session change and captures no live AppKit state; unrendered session state is never published. | reconciliation re-entrancy counter; zero-mutation and zero-publication host update tests |
| ARC-016 | Diagnostic payloads cannot represent document content, URLs, descriptions, filenames, or paths. | closed payload value type without a string case; encoder tests |

## 14. Architecture change gate

An implementation plan may conform to this architecture; it may not silently redefine it.

Changing an `ARC-###` invariant requires, before production code:

1. a reproduced counterexample or new approved constraint;
2. fresh research, including real API probes when platform behavior matters;
3. credible options compared against the architecture drivers and quality scenarios;
4. explicit informed user approval;
5. an atomic update to this document and affected requirements;
6. a new or changed executable proof that would fail under the old behavior; and
7. deletion of the displaced production path in the same build.

There are no architectural compatibility shims, indefinite migrations, exceptions, or
supersession documents. The working tree states current truth; Git records history.

## 15. Current risks

- Concrete inverse mapping remains the hardest part of delimiter-free WYSIWYG editing.
- AppKit delegate callbacks are reentrant and include programmatic selection notifications.
- `@Published` invalidates on assignment, not on change. A write to observed session state from
  inside view reconciliation is self-sustaining and presents as sustained CPU use rather than a
  hang; only the re-entrancy counter and host-update instrumentation make it visible.
- Tables combine presentation structure with escape-sensitive source spelling.
- cmark semantic literals may normalize source spelling; source positions plus a concrete decoder
  are required before claiming editability.
- Full projection compilation is fast enough off-main but not an acceptable dependency between
  consecutive keystrokes.
- Image placement interacts with external files and asynchronous providers; containment and
  identity-pinned rollback remain mandatory.

## 16. Glossary

- **Accepted edit:** a fully validated operation whose source mutation commits.
- **Authoritative reconciliation:** a full parse/index/projection built from canonical source and
  applied only after complete identity checks.
- **Canonical:** state whose loss or replacement changes the document's meaning.
- **Derived:** state rebuildable from canonical source.
- **Presentation snapshot:** the indivisible WYSIWYG rendered content, attributes, structure,
  coordinate map, and revision.
- **Presentation transition:** a synchronous exact update that keeps WYSIWYG editable immediately
  after an accepted edit.
- **Projection:** delimiter-free rendered representation derived from Markdown source.
- **Refusal:** a typed no-mutation outcome returned before any partial source or view change.
- **Source mutation:** one exact, versioned UTF-16 replacement owned by the document.
- **Transient:** native interaction state such as marked text that is not serialized.
