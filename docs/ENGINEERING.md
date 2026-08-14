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
- SwiftUI owns document-content composition. A window-scoped native AppKit command surface owns
  the menu and `NSToolbar` presentation.
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
| --- | --- | --- | --- |
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
- cmark reports a node whose content ends exactly at a line boundary — a loose list item followed
  by a blank line, for example — with `end_line` set to the next line and `end_column` 0. The
  source index maps that to the previous line's terminator as an **inclusive** last byte, matching
  every other column, so the shared inclusive→exclusive conversion lands the span exactly after
  that terminator and never one byte into the following line. It is a legitimate cmark convention,
  not an ambiguous or clamped coordinate.

A presentation snapshot identity covers all content needed to edit it: source revision, rendered
string, semantic inline and block spans, resolved attributes/attachments, segment map, structural
metadata, typography identity, and relevant location generation. A snapshot is always complete.
The TextKit adapter may apply a validated local `PresentationPatch`; it may never treat that patch
as an independently authoritative partial snapshot.

## 5. Edit transaction

### Source edit

1. The source `NSTextView` asks its delegate whether a native replacement may occur.
2. The adapter forms an exact `SourceMutation` and submits a typed `EditorInput`.
3. `EditorTransactionKernel.reduce` validates the immutable source/session snapshot and returns
   one accepted transaction or one typed refusal.
4. The main-actor document commit applies one `SourceMutation`, advances once, and registers undo.
5. Native source storage and the session's source selection are updated with explicit
   programmatic origin.
6. Asynchronous parse/projection reconciliation is scheduled.

### WYSIWYG edit

An accepted WYSIWYG edit is a synchronous atomic transition:

1. The view submits an immutable native replacement and current `ProjectionSelection`.
2. The session captures an `EditorStateSnapshot`; the transaction kernel classifies the entire
   selection against the exact presented snapshot.
3. The session plans the request off-main with the originating `IntentID`, then supplies that
   immutable outcome to the pure kernel. The kernel validates and returns either:
   - `AcceptedEdit { sourceMutation, presentationTransition, selectionAfter }`, or
   - a typed refusal with no mutation.
4. For an accepted edit, the document commits the source mutation once.
5. Before the input callback returns, the session derives and applies the matching attributed
   `PresentationPatch`, advances the complete presentation snapshot, and restores selection. The
   next keystroke therefore targets the new source and presentation revisions.
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
unprovable edit refuse atomically for content mutation (`ARC-009`). For `reshapesWholeLine` block rewrites
(setParagraph/setHeading/toggleOrderedList/UnorderedList/TaskList/BlockQuote/CodeBlock) the system
identifies the enclosing `PresentationBlock` by `caretLocation ∈ projectionRange` (total when
`caret ∈ renderedString`; `tableCell` stays exactly classified) and `SourceMutation.exact` on that
block's `sourceRange` — the weaker total rule for block identification. Partial selection mutation is forbidden.

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
source representation. Tables use escape-aware concrete cell coordinates and one presentation paragraph per cell, so native table blocks have the paragraph geometry they require. A normalized inline or
fenced-code representation is editable only when its inverse is proven. Fenced and indented code line breaks that normalise `\r\n`→`\n` in the cmark literal are the approved `ENGINEERING §6` case 2: each `\r\n` inside code is one `.normalizedCodeBlock` atomic with decoder `\r\n→\n` and encoder `\n→\r\n` (`ProjectionAtom.concreteAtoms` per-line, `StructuralSourceSpans.fencedCodeBody` allowing the filtered identity).

`ProjectionOracle` validates:

- rendered content and attributes;
- complete, ordered, non-overlapping segment coverage;
- legal zero-length boundaries and affinity;
- exact round-trip mappings where promised;
- source postconditions after semantic edits; and
- refusal for every unsupported or mixed case.

## 7. Typography and block presentation

`ProjectionCompiler` emits Markdown semantics and exact coordinates; it does not choose AppKit
fonts, colors, paragraph styles, or geometry. `AttributedPresentationBuilder` combines one
complete semantic presentation with immutable `MarkdownTypography` tokens on the main actor.
`TextStorageApplier` applies either an initial complete presentation or one validated
`PresentationPatch`.

The default `MarkdownTypography` is:

| Token | Default |
| --- | --- |
| Body | system font, 15 pt, regular |
| Body line height | approximately 1.35× |
| Reading measure | maximum 720 pt, centered when wider |
| Content inset | minimum 28 pt horizontal and 20 pt vertical |
| Paragraph spacing | 0.7 em after an ordinary paragraph |
| H1 | 30 pt semibold; 1.0 em before and 0.35 em after |
| H2 | 24 pt semibold; 0.9 em before and 0.3 em after |
| H3 | 20 pt semibold; 0.8 em before and 0.3 em after |
| H4 | 17 pt semibold; 0.7 em before and 0.25 em after |
| H5 | 15 pt semibold; 0.6 em before and 0.25 em after |
| H6 | 13 pt semibold, secondary label color; 0.5 em before and 0.25 em after |
| List nesting | 24 pt per level with a hanging marker |
| Blockquote | `NSTextBlock` with a 3 pt adaptive leading border and 14 pt padding — 17 pt content inset |
| Inline code | monospaced at approximately 0.93 em with adaptive subtle background |
| Code block | `NSTextBlock` with 12 pt padding and an adaptive background; monospaced |
| Thematic break | one-pixel separator across the available reading measure |

Heading spacing is expressed in em of the *body* size, is always larger before than after, and is
the same mechanism at every level. Block decoration that cannot be an ordinary text attribute —
the quote rule, the code-block container — is a native `NSTextBlock`, so AppKit performs its
layout and drawing and a component test can assert on `NSParagraphStyle.textBlocks` without
rendering. Blocks nested inside a decorated block inherit its geometry instead of replacing it.

Rules:

- A cmark `softBreak` emits a presentation space in the same paragraph. A cmark `lineBreak` emits
  a distinct hard-line-break atom and a visible newline. A paragraph boundary remains a semantic
  block boundary and receives paragraph spacing.
- Paragraph spacing and heading spacing are `NSParagraphStyle` attributes. Synthetic extra
  newline characters are not inserted merely to create visual spacing.
- **Spacing belongs to a semantic boundary, not to a newline character.** TextKit ends a
  paragraph at every `\n` and applies `paragraphSpacing` after each one, but a semantic block is
  not always one TextKit paragraph: a formal hard break puts a real newline *inside* one
  CommonMark paragraph, and a fenced code block is one block spanning many lines. A block's
  paragraph style is therefore installed per TextKit paragraph — only the last carries
  `paragraphSpacing`, only the first carries `paragraphSpacingBefore`, and every other attribute
  (indents, tab stops, text blocks, alignment) is identical across the block. Applying one style
  uniformly across a block's whole range made a hard break lay out identically to a paragraph
  boundary and spaced a code block's own lines apart. A requirement about what the reader sees is
  proved by forcing layout on a directly constructed `NSTextView` and asserting on
  `NSLayoutManager` line-fragment rectangles; asserting the attribute value is not the same claim.
- List marker, body, continuation lines, nested children, and task controls share explicit block
  metadata. A task checkbox replaces the ordinary bullet. Nesting changes indentation, never
  source spelling.
- Blockquotes have an inset and leading rule. Color is supplementary and cannot be their only
  distinction.
- Code blocks use block geometry and padding. Inline code remains inline; neither treatment
  changes source or edit coordinates. The two are distinct projection style tags (`.codeBlock`
  and `.code`), so they cannot compose: fenced content carrying the inline tag drew the inline
  run background *inside* the block's own container.
- Every toolbar command item carries an image as well as a label. An `NSToolbarItem` with neither
  an image nor a view draws as an empty control, and accessibility meaning never depends on the
  glyph: label, palette label, tooltip, and accessibility description all remain.
- Tables size to their contents within the reading measure. They do not expand solely to fill the
  viewport. Header emphasis and borders use adaptive system colors.
- Images preserve aspect ratio and fit the reading measure. Missing images use an intentional
  labeled placeholder rather than an unrelated generic file icon.
- Raw HTML remains non-executing literal text with a muted monospaced treatment.
- A full attributed-storage replacement is permitted for initial load, recovery, and an explicit
  typography/theme change. An ordinary accepted local edit applies one validated attributed
  patch and must not rebuild or replace the entire text storage.
- A patch is built from the touched semantic block scope only — never from a complete rebuild
  that is then sliced. Expanding beyond the literal replacement requires proving that the
  surrounding text is identical in both snapshots; an unprovable patch refuses.
- The patch scope comes from the real difference between two snapshots, never from a declared
  replacement range. A semantic formatting command declares a whole-document replacement, so
  trusting the declaration would make every command a full rebuild.
- A newer snapshot whose rendered text is unchanged — an authoritative snapshot replacing a
  provisional one — is applied as an attribute refresh that mutates no characters. The refresh
  rebuilds and reapplies only the semantic blocks whose runs, blocks, attachments, tables, or list
  markers differ; it does not build or invalidate an unrelated document range. This is why the
  full-replacement allowlist stays at three routes rather than gaining a fourth.
- Every full replacement other than a first application records a typed `presentationRecovered`
  fault, so a rebuild can never be mistaken for an ordinary application. A failed proof from the
  native input callback or while applying a newer snapshot makes WYSIWYG unavailable until an
  authoritative snapshot lands: an exceptional rebuild may reestablish storage, but never proves
  that continued rich-text editing is safe.
- Typography is derived and replaceable. It never enters canonical source, source history,
  coordinate meaning, or serialization.

## 8. Native editor integration

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
- Marked-text arrival crosses the kernel as a transient `.markedText(.update)` transaction. The
  main-actor document owns the short-lived undo group around the native mutation because AppKit
  registers marked-text edits on the document undo manager, while the WYSIWYG adapter only applies
  the accepted/refused result. The completed composition is a separate source transaction.
- Native plain-text paste, spelling, Find, keyboard input, selection, and accessibility remain
  available. There are no UI-test dependencies.

### Native command surface

- A window-scoped command model is the sole route for semantic formatting availability and
  execution. The menu bar and `NSToolbar` are presentations of that model.
- The owning window is resolved from the view hierarchy, never from the application's key window:
  during a second document's opening the key window is still the first one, so an ambient lookup
  can bind a controller or install a toolbar on the wrong document's window.
- Every toolbar command has a menu equivalent. Standard shortcuts include Command-B for bold,
  Command-I for italic, and Command-K for link editing.
- Toolbar items validate against the active window, mode, exact typed selection, and current
  source/presentation revision. Unsafe commands are disabled or refuse atomically through the
  same command route.
- The toolbar uses native overflow and never compresses labels into ambiguous ellipses inside the
  document content area.
- Link editing is a window-attached sheet. Application-modal formatting alerts are forbidden.

## 9. Document and concurrency model

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
- `save(to:ofType:for:completionHandler:)` is the AppKit override every save that determines a
  destination routes through — manual Save, Save As, autosave-in-place, and the delegate-based
  `DocumentSaveBridge` this app's own operation-scoped `saveDocument()` uses — verified
  empirically rather than assumed, and confirmed to run on the main actor. It is where save
  outcome (REQ-100) is recorded for that case. `saveDocument()` separately detects and records
  a save that never reaches it at all — the user cancelling the Save panel for an untitled
  document through this app's own bridge — by comparing a sequence counter before/after.
- **Known gap:** the stock, unoverridden `save(_:)` selector Cmd+S invokes decides whether to
  show a Save panel and calls `runModalSavePanel(for:delegate:didSave:contextInfo:)` before ever
  reaching `save(to:ofType:for:completionHandler:)`. Cancelling that panel for an untitled
  document through the plain Cmd+S/File-menu path (as opposed to this app's own `saveDocument()`
  bridge) is therefore not currently recorded. Closing this fully would mean overriding
  `runModalSavePanel` itself — deeper, unresearched AppKit surface than this increment's
  approved scope covers, and a heavier proof burden. This is a narrower gap than it may sound:
  a cancelled save is a deliberate user choice, not a failure needing a diagnostic.
- Reading a URL that itself cannot be read — file removed, unreadable, permission denied — is
  recorded by the URL-based `read(from:ofType:)` override, distinct from the Data-based
  override's invalid-UTF-8 content failure; a private flag distinguishes the two so a content
  failure (which the Data-based override already records) is never double-recorded.
- A document's own history of "has `read(from:ofType:)` ever run on this instance" cannot
  distinguish an initial load from a revert in one specific case: a document saved for the
  first time while still untouched (Save never advances `sourceVersion`) and then reverted is,
  from that instance's own perspective, its first-ever read too. `revert(toContentsOf:ofType:)`
  is NSDocument's dedicated entry point for "Revert to Saved" — distinct from the initial-open
  path — and is overridden solely to flag that an in-flight read is a revert regardless of
  instance history. Unlike the `nonisolated` read/data overrides, this one is main-actor-isolated
  in the current SDK; it needs no `MainActor.assumeIsolated` hop.
- Background work receives immutable `Sendable` value snapshots only.
- Background work never captures a mutable document or AppKit object.
- Results publish on the main actor only after complete source revision, location generation, and
  operation identity checks.
- Identity checks remain the correctness boundary. Cancellation and coalescing are additionally
  required to prevent obsolete work from consuming unbounded time ahead of the latest revision.
- One latest-generation parse scheduler owns parse demand. At most one parse occupies cmark's
  process-wide critical section, and at most the newest pending revision remains queued.
- A parse task rechecks cancellation after acquiring the parser lock and before copying source or
  entering cmark. A superseded waiter performs no parse.
- Swift 6 complete concurrency warnings are failures, including warnings in tests.

## 10. Undo and selection

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

## 11. Image placement

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

Displaying a referenced image is also resource-bounded before bulk input work:

- inspect file identity and stat metadata before reading;
- reject an encoded file larger than 256 MiB before mapping, hashing, or decoding it;
- inspect type and pixel metadata without eager full-image caching;
- hash accepted content off-main for cache identity;
- create only a bounded display representation; and
- keep decoded display cache cost at or below 64 MiB.

Encoded-file bytes, source pixel dimensions, and decoded-cache cost are distinct limits and
distinct performance measurements. Opening Markdown cannot map or hash an arbitrarily large file
merely because its relative destination appears in source.

Referenced-asset analysis derives from the canonical cmark tree and concrete source index. There
is no regex or line-oriented second Markdown parser for deciding which assets are referenced.

**Instrumentation (REQ-101/102; ARC-017):** every phase transition, claim count, byte count, and
typed failure is recorded through `EditorTraceEvent`, reusing the existing closed
`ImagePlacementPhase`/`ImagePlacementEvent`/`ImagePlacementError` vocabulary rather than inventing
a parallel one. Phase transitions are recorded in exactly one place
(`ImagePlacementController.apply`, plus the two `.begin` call sites that apply the reducer
directly), so no call site can add a transition without it being recorded; a terminal reset back
to idle — after a commit, a cancellation, or a failure — goes through `resetToIdle()`, the sole
place that resets `state`, rather than assigning a fresh `ImagePlacementState()` inline, so that
transition is never silently unrecorded either. A failure records `imagePlacementFailed` before
`resetToIdle()` runs, so the run log shows the reason before the terminal transition it caused,
not after. `alert` is `private(set)`; `presentAlert(_:reason:)` is the only way to assign it, so
a presented failure or warning can never be absent from the run log — enforced by the compiler,
not merely by convention (an attempt to assign `alert` directly from outside
`ImagePlacementController` fails to compile), and the same conformance test scans inside
`ImagePlacementController.swift` itself for any assignment other than `presentAlert`'s and
`dismissAlert`'s own two lines. Rollback is recorded through two routes, both reporting the
actual number of files removed (not the number of pins attempted): a rollback the controller
drives itself goes through `ImagePlacementController.rollbackAndRecord`, which reports
`AssetDirectoryStore.rollback`'s real return count; `AssetDirectoryStore.publishLockedUncoordinated`
can also roll back internally, before ever throwing back to the controller, when a later artifact
in a multi-image batch fails after an earlier one already published — that path throws
`PartialPublishRollback` (the removed count plus the classified failure) specifically so the
controller can still record `imagePlacementRolledBack` for a rollback it did not itself drive.
An Add Image picker result whose immutable target no longer matches current source or location
records its known claim count and a `parentChanged` failure without mutating placement state.
`DocumentSaveOutcome` preserves successful, cancelled, and failed operation-scoped Save results;
an untitled-save failure takes the ordinary `.saveFailed` placement-failure route rather than
being represented as a cancellation. `assetDirectoryPublished` is distinct from
`imagePlacementCommitted`: files can be published to
`assets/` and then still be rolled back or the transaction cancelled before the source mutation
commits (a parent-changed race, or the tracked insertion point changing), so the two milestones
are not always both reached.

## 12. Instrumentation and diagnostics

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
- Ordinary editor records buffer without synchronous file I/O and are appended by one serialized
  sink actor; sequence allocation and sink reservation are atomic, and terminal closure reserves `runEnd` before rejecting late appends. A process-level fault has a non-main route to that same
  sink, so reporting a main-actor stall never depends on the stalled actor. Faults flush
  immediately, and the terminating record is made durable before the process may exit.
- Retained runs and per-file size are bounded; the oldest runs are removed first.
- A background watchdog races a hop onto the main actor against a one-second threshold. The
  threshold crossing is written through the non-main process route while the stall is still in
  progress, including when it never recovers. A recovery record carries the measured duration
  once the hop lands. Both records use the same diagnostic sink and schema.
- Reconciliation instrumentation records any session publication during view reconciliation, and
  the host-update meter reports a sustained update rate — the signature of a self-feeding loop,
  which presents as high CPU rather than as a hang.
- A `MARKDOWN_EDITOR_DIAGNOSTICS_DIR` environment variable overrides the diagnostics directory,
  so process-level smoke verification writes to a hermetic location instead of the user's own
  production or unit-test directory.

There is no second instrumentation route. `os_log` is not used for editor events.

**Observed proof route (COR-68):** the coverage gate consumes only records emitted by an executed
production route through a gate-owned FIFO capture. Each such record carries its closed route name
and `productionRoutePipe` channel marker; encoding probes and gate fixtures have different origins
and cannot satisfy reachability. `docs/proof-routes.json` maps every event to an owner and entry,
and the gate parses that owner's entry-function body, after masking comments and strings, for the
event-specific typed route call rather than accepting an aggregate source match.

Performance sampling is explicitly lifetime-owned:

- each attached `EditorSession` owns one sampler;
- the sampler owns bounded samples and its periodic timer;
- detach/invalidation stops the timer, flushes once, and unregisters the sampler;
- the run coordinator weakly observes only live samplers for terminal flush; and
- no global collection strongly retains a session or sampler.

Metric names describe their actual boundaries:

- `nativeInputCallback`: native replacement delegate entry through source commit, attributed
  patch application, and selection restoration;
- `modeTransition`: requested mode change through visibility, focus, and selection restoration;
- `parseProjection`: parser, source index, and semantic projection only;
- `imageResolution`: inspection, hashing, thumbnail decode, and cache lookup; and
- `authoritativeApplication`: main-actor application of a completed authoritative result; and
- `layoutApplication`: TextKit layout for the range an applied patch changed. The
  `nativeInputCallback` boundary ends when the input delegate returns — after
  `storage.endEditing()` but before glyph generation, layout, and drawing — so without this
  metric every boundary measured a phase the app owns and none measured one TextKit owns, which
  is where perceived jank lives on the TextKit 1 compatibility path.

Every metric has a p95 budget in one exported table (`PerformanceSampler.budgetNanos`), asserted
against the values REQ-090 states. The budgets previously existed twice — as prose here and as
literals inside `flush()` — with nothing tying them.

Every Release performance proof records configuration, corpus identity, warmups, sample count,
median, p95, and failures. Zero executed samples is a failing proof, never a skipped success.
Terminal diagnostic close signals durability immediately after the sink closes; re-enabling
sudden termination on the main actor is not part of the synchronous durability wait.

**Process-level smoke verification (`ARC-Q12`):** `Scripts/smoke-test.sh` launches the built
application directly (bypassing Launch Services) on `Scripts/Fixtures/smoke-basic.md` with
`--diagnostic-smoke-exit` and the diagnostics-directory override, then asserts only on the
structured JSON Lines records the run produces — sequence order, a `documentOpened` record, a
bounded `hostUpdateEnded` count (the livelock guard; a healthy run settles at 2), no `error`/
`fault` record, and a terminating `runEnd` record. It never drives, reads, or asserts on the UI.
The run additionally performs one accepted text insertion and one accepted semantic command
before settling (REQ-115). Without them the verification proved only open-and-idle, so
`editRefused` — the record that would have surfaced COR-25 and the four commands COR-26 fixed —
could never fire in a process-level run.

**How those edits reach the app, and why that is still inside the carve-out.** They are invoked
on the same window-scoped `EditorCommandController` a toolbar click would use, obtained by
walking `NSApp.windows` to that window's toolbar delegate (ARC-024 makes the command controller
window-scoped, so the window *is* its owner). No synthetic event is dispatched, no accessibility
API is used, no pixel or view state is read, and every assertion afterward is still made purely
on structured diagnostic records. This is a deliberate judgement, recorded rather than left
implicit: reaching a controller through `NSApp.windows` touches a UI object, so a stricter
reading of "must not drive, read, or assert on any user interface" would require a non-UI
accessor instead. There is no such accessor today, and inventing a parallel registry purely for
verification would add exactly the kind of second route this architecture forbids. If that
judgement is ever revisited, the alternative is a non-UI production handle on the session — not a
relaxation of the assertion rule.

The idle-settle ceiling is 8 for this script (it edits) and 4 for the screenshot script (it does
not). A healthy run measures 2, reproducibly; the previous ceiling of 20 left ten-fold slack on
the one metric that exists to catch a self-feeding reconciliation loop.

Both scripts copy the fixture tree to a temporary working directory before launching. Autosave in
place (REQ-005) means a launched app can write to whatever it opens, so a verification run must
never be pointed at the repository's own fixtures.

This is the narrow, explicit exception described in `CLAUDE.md` §4; it does not replace or excuse
any other automated proof.

**Process-level screenshot verification (`ARC-Q13`; REQ-104):** `Scripts/smoke-screenshot.sh`
runs the same shape of process-level smoke verification against a richer fixture
(`Scripts/Fixtures/smoke-rich.md`, covering headings, emphasis, strikethrough, inline code,
links, a local image, ordered/unordered/task lists including nesting, blockquotes, a fenced code
block, a table, a thematic break, and literal raw HTML) and additionally captures exactly one
screenshot of the application's own on-screen window — never the full screen, which would leak
whatever else happens to be displayed and is unrelated to this verification. The window is
located by the exact process ID the script launched via `Scripts/find-window-id.swift`
(`CGWindowListCopyWindowInfo` matched on `kCGWindowOwnerPID`, which needs no Accessibility
permission, only the calling process's own Screen Recording permission) — not by owner-name
substring, which could otherwise select a window belonging to a real document the user already
had open — and captured with `screencapture -l<windowID>`, which does not require the target
application to be frontmost or key. Screenshotting waits for a `hostUpdateEnded` record after
`availabilityChanged` turns editable, plus a short fixed margin, since availability changing is
a session-state signal that precedes the host view's own update pass and the window server's
actual compositing. The screenshot is mandatory visual-review evidence for the agent and the
user at the close of every build increment — it is never itself a pass/fail assertion. This
script's exit status is not determined solely by the structured diagnostic checks it shares with
`Scripts/smoke-test.sh`: it also fails earlier, with a distinct error message, if the environment
cannot support a capture at all (no Screen Recording permission, the window never appears, or
`screencapture` itself fails) — a caller must distinguish an environment/capture failure from a
genuine application diagnostic failure by the error text, not by exit code alone. Restoration-
state veto uses the same `-ApplePersistenceIgnoreState YES` process argument as
`Scripts/smoke-test.sh`, for the same reason.

## 13. Quality scenarios

| ID | Scenario and measure |
| --- | --- |
| ARC-Q01 | Given a current editable WYSIWYG snapshot, 100 consecutive accepted insertions appear exactly once and in order; zero are refused merely because authoritative parsing is pending. |
| ARC-Q02 | A WYSIWYG edit either advances source and presentation together before return or changes neither. No observable state contains new source with an editable old projection. |
| ARC-Q03 | A stale parse, projection, image decode, load, or placement result performs zero state applications. |
| ARC-Q04 | Opening and saving without edits preserves the byte fixtures exactly, including empty, BOM, CRLF, and Unicode cases; invalid UTF-8 refuses. |
| ARC-Q05 | On the approved 100,000 UTF-16 corpus in Release: complete native-input callback p95 <8 ms, complete mode transition p95 <16 ms, and off-main parse/index/semantic-projection p95 <100 ms; every gate proves a nonzero sample count. |
| ARC-Q06 | Parser, source-index, projection compilation, image inspection/decode, hashing, and file I/O do not execute on the main actor. |
| ARC-Q07 | Every supported presentation atom satisfies the oracle; every unsupported, cross-cell, mixed-domain, or unprovable selection refuses without mutation. |
| ARC-Q08 | Mode changes preserve each mode's logical selection/affinity/scroll and never change source. |
| ARC-Q09 | File-backed PNG/JPEG/GIF/HEIC/HEIF fixtures retain exact bytes and metadata; display decoding creates no intermediate JPEG or PNG. |
| ARC-Q10 | Instrumentation proves routing, revision, result, refusal class, and timing, and cannot represent document content, selected content, URLs, descriptions, filenames, or paths. |
| ARC-Q11 | Opening a document and leaving the window idle performs a bounded number of editor-host view updates and settles; sustained reconciliation without user input is a reported fault. |
| ARC-Q12 | Launching the built application on a fixture document produces a parseable run log whose host-update count is bounded, contains no fault, and ends with a clean-exit record. |
| ARC-Q13 | Launching the built application on a rich fixture, capturing exactly one screenshot of only its own on-screen window, and closing it produces the same clean, bounded run log as ARC-Q12, plus one image containing no on-screen content outside that window. |
| ARC-Q14 | Constructed attributed presentation proves the approved body, heading, paragraph, list, quote, code, table, thematic-break, image, and raw-HTML semantic styles in Light and Dark appearance without changing the rendered string or source. |
| ARC-Q15 | At narrow, default, and wide constructed TextKit container widths, the reading measure/insets, hanging list indentation, nested depth, block spacing, and image bounds satisfy the approved typography tokens without clipped content. |
| ARC-Q16 | One ordinary accepted WYSIWYG insertion performs one bounded attributed-storage edit and no full-storage replacement; initial load, recovery, and explicit typography change remain the only full-replacement routes. |
| ARC-Q17 | Releasing or detaching 100 editor sessions leaves zero live sampler timers; a main-actor stall writes its threshold record before recovery; terminal close completes without waiting on a main-actor hop. |
| ARC-Q18 | Given many revisions while one parse holds the parser lock, only the running revision and newest pending revision may enter parsing; all older pending revisions are discarded before source copy/cmark work. |
| ARC-Q19 | A referenced regular image above 256 MiB is rejected before full read, mapping, hashing, or decode, while accepted images retain the 64 MiB decoded-cache bound. |
| ARC-Q20 | Every semantic formatting action has one window-scoped command route, matching menu and toolbar presentation, shared validation, and no application-modal formatting dialog. |

## 14. Architectural invariants and proof

| ID | Invariant | Required proof |
| --- | --- | --- |
| ARC-001 | One canonical source, revision, URL generation, and undo owner: `MarkdownDocument`; all editor inputs cross `EditorTransactionKernel` before the document commit. | type/API inspection; `EditorTransactionKernelTests`; document transaction tests |
| ARC-002 | One session-owned typed state per editor mode; no parallel compatibility state. | compiler types; documentation/source conformance check |
| ARC-003 | Presented string, attributes, structure, coordinate map, and revision form one snapshot. | snapshot construction API; oracle |
| ARC-004 | Editable WYSIWYG always matches current canonical source/location identity. | state-machine tests and traces; `EditorTransactionKernelTests` |
| ARC-005 | Accepted WYSIWYG edits advance source and presentation synchronously and exactly once. | `acceptedEditAdvancesSourcePresentationSelectionAndUndoOnce`; rapid-input property tests |
| ARC-006 | Background reconciliation cannot overwrite newer state. | adversarial generation tests and traces |
| ARC-007 | Coordinate conversion is exact or refused; never guessed or clamped. | typed APIs; projection oracle; generated fixtures |
| ARC-008 | Literal typing and semantic formatting are separate commands. | punctuation/context fixtures; toolbar tests |
| ARC-009 | Content mutation (insertText/deleteBackward/replaceTableCell) that is unsupported, mixed, cross-cell, or unprovable refuses atomically; `reshapesWholeLine` block identification is total via enclosing `PresentationBlock` (`caretLocation ∈ projectionRange`; `tableCell` stays exact). | exhaustive selection-classification tests + block-identification totality tests |
| ARC-010 | All text changes and history use one document-owned source mutation path behind the transaction kernel. | `everyInputRouteUsesEditorTransactionKernel`; API restriction; history tests |
| ARC-011 | Mutable document/AppKit state remains main-actor-owned; background work uses immutable values. | Swift 6 complete-concurrency clean build |
| ARC-012 | Image entry points share one exact-copy, contained, non-destructive transaction. | route tests; filesystem adversarial suite |
| ARC-013 | Programmatic view updates cannot masquerade as user input or alter undo grouping. | explicit origin type; callback tests |
| ARC-014 | No production or verification claim depends on manual or UI testing. | target/source conformance check |
| ARC-015 | Editor-host view reconciliation publishes no session change and captures no live AppKit state; unrendered session state is never published. | reconciliation re-entrancy counter; zero-mutation and zero-publication host update tests |
| ARC-016 | Diagnostic payloads cannot represent document content, URLs, descriptions, filenames, or paths. | closed payload value type without a string case; encoder tests |
| ARC-017 | Every user-visible failure or warning alert has a corresponding diagnostic record. | `alert` is `private(set)`; `presentAlert(_:reason:)` is its only assignment route (compiler-enforced); structural conformance test |
| ARC-018 | Typography is derived from semantic inline/block presentation plus immutable tokens and never changes canonical source, history, or coordinate meaning. | attributed-presentation semantic tests; source-before/after equality |
| ARC-019 | An ordinary accepted WYSIWYG edit applies one validated attributed patch and performs no full-storage replacement. | instrumented `NSTextStorage` component test; native-input performance corpus |
| ARC-020 | Performance samples are lifetime-owned, bounded, honestly named, and include every synchronous operation claimed by their boundary. | sampler lifetime tests; nonzero Release evidence; boundary-spy tests |
| ARC-026 | One explicit sendable intent identity owns all downstream work across actor, task, GCD, parser, presentation, and terminal lifecycle boundaries; late or cancelled work is typed and durably emitted. | `COR69IntentMeasurementTests/editorSessionRouteRetainsIntentThroughParse()`; `asyncAndGCDWorkRetainTheExplicitIntent()`; `presentationLeaseDefersTerminalLedger()`; `lateWorkAfterFinishIsTypedOrphan()`; process smoke diagnostics |
| ARC-021 | A main-actor stall can be made durable without scheduling the report onto the main actor, and terminal durability never waits on a main-actor hop. | blocked-main component test; bounded terminal-close test |
| ARC-022 | Superseded pending parses do not enter source-copy/cmark work after the parser lock becomes available. | deterministic scheduler/lock test with controlled generations |
| ARC-023 | Image display rejects over-limit encoded files before bulk read/hash/decode and derives references from the canonical parse tree. | file-operation spy; over-limit sparse-file test; scanner deletion gate |
| ARC-024 | Menu and native toolbar are presentations of one window-scoped command model with shared validation. | command-router tests; menu/toolbar construction inspection |
| ARC-027 | Trace-vocabulary coverage and delivery status are derived from observed production-route evidence and passing requirement proofs; encoding probes and gate fixtures cannot satisfy reachability, and every evidence artefact remains bound to the exact pushed commit and tree before local publication. | Gate-owned FIFO production records with trusted run harness; exact nested owner-entry route checks; `Scripts/check-instrumentation-coverage.sh`; `Scripts/check-delivery-status.sh`; `Scripts/check-proof-results.sh`; `Scripts/check-falsification.sh` |

**Reserved identifiers — approved but not yet true, and therefore not invariants of this
architecture.** They are recorded here so no later increment reassigns them:

| Identifier | Reserved by | Becomes an invariant when |
| --- | --- | --- |
| `ARC-025` | COR-81 (accessibility semantics) | that increment lands |
| `ARC-Q21` | COR-81 (accessibility semantics) | that increment lands |
| `ARC-Q22` | COR-68 (proof architecture v2) | every retained `Done` claim has an observed production mutation that turns its cited behavior proof red |
| `ARC-Q23` | COR-81 (contrast conformance) | that increment lands |
| `ARC-Q24` | DISC-08 / REQ-140 (text-scaling boundary) | only after a new documented third-party platform API or separately approved in-app scaling requirement; currently Deferred |
| `ARC-Q25` | COR-81 (reduced motion/transparency/increase contrast) | that increment lands |
| `ARC-Q26` | COR-83 (process lifecycle) | a Stage 0-selected deterministic tool proves zero process leaks |

## 15. Architecture change gate

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

## 16. Current risks

- Concrete inverse mapping remains the hardest part of delimiter-free WYSIWYG editing.
- AppKit delegate callbacks are reentrant and include programmatic selection notifications.
- `@Published` invalidates on assignment, not on change. A write to observed session state from
  inside view reconciliation is self-sustaining and presents as sustained CPU use rather than a
  hang; only the re-entrancy counter and host-update instrumentation make it visible.
- Tables combine presentation structure with escape-sensitive source spelling.
- cmark semantic literals may normalize source spelling; source positions plus a concrete decoder
  are required before claiming editability.
- Full projection compilation is fast enough off-main but not an acceptable dependency between
  consecutive keystrokes. Complete attributed-storage replacement is likewise forbidden on the
  ordinary local-edit path.
- Ordinary WYSIWYG planning still reaches a synchronous full-document parse/compile route before
  the pure kernel reduction. COR-70 creates the transaction seam and preserves the originating
  intent through that plan; COR-71 then replaces the full-document work with a bounded local
  transition plus identity-checked asynchronous authority.
- Source highlighting bounds attribute application but still tokenizes the full source and performs
  whole-document fence scans. COR-72 replaces it with per-line state propagation.
- Native `NSTextTable` currently keeps the WYSIWYG editor on the TextKit 1 compatibility path. A
  TextKit 2 migration requires a separate table, attachment, selection, IME, and performance POC.
- Dense semantic typography makes patch boundaries more demanding: a local source edit can change
  paragraph or list structure beyond the replaced characters, so the patch planner must expand
  to the smallest complete affected semantic blocks and otherwise choose explicit recovery.
- Image placement interacts with external files and asynchronous providers; containment and
  identity-pinned rollback remain mandatory.
- Display cache identity must be established before bulk I/O. Full SHA-256 is correct for exact-copy
  asset collision naming but not as a display-cache lookup precondition; sampled digests and MD5 are
  not correctness identities. COR-73 creates the single display owner.
- COR-69 is current architecture: one explicit sendable intent identity is retained through parser,
  presentation, actor, task, and GCD boundaries; presentation leases defer terminal ledger closure
  until downstream work finishes; late or cancelled work is typed and durably emitted; frame
  acknowledgements are generation-safe; and the benchmark matrix and provenance-bound baseline are
  structurally and operationally verified. The full gate observed the required tests and falsifying
  mutations before ARC-026 and REQ-123/125/128 were promoted to current truth.
- macOS's Accessibility ▸ Display ▸ Text Size preference has no documented, observable third-party
  API (`docs/research/DISC-08-macos-text-scaling.md`); the approved fixed typography default
  (§7) has no platform-provided route to user scaling. REQ-140 therefore remains `Deferred` rather
  than pretending structural absence is a delivered feature. Any future animation or translucent view must gate on
  `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` /
  `...ShouldReduceTransparency`; COR-81 makes that policy executable and closes the semantic,
  keyboard, contrast, and display-preference matrices together.

## 17. Glossary

- **Accepted edit:** a fully validated operation whose source mutation commits.
- **Authoritative reconciliation:** a full parse/index/projection built from canonical source and
  applied only after complete identity checks.
- **Canonical:** state whose loss or replacement changes the document's meaning.
- **Derived:** state rebuildable from canonical source.
- **Presentation snapshot:** the indivisible WYSIWYG rendered content, attributes, structure,
  coordinate map, and revision.
- **Presentation transition:** a synchronous exact update that keeps WYSIWYG editable immediately
  after an accepted edit.
- **Presentation patch:** a validated attributed replacement derived from two complete snapshots;
  it is an application instruction, never partial authority.
- **Semantic block:** a projection-level paragraph, heading, list item, quote, code block, table,
  thematic break, image block, or literal fallback carrying layout meaning but no AppKit objects.
- **Projection:** delimiter-free rendered representation derived from Markdown source.
- **Refusal:** a typed no-mutation outcome returned before any partial source or view change.
- **Source mutation:** one exact, versioned UTF-16 replacement owned by the document.
- **Transient:** native interaction state such as marked text that is not serialized.
