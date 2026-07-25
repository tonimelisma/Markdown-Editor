# RESEARCH-0005 — Image placement correction architecture

- **Date:** 2026-07-24
- **For:** COR-02
- **Type:** online research + native-API investigation
- **Status:** Done
- **Outcome:** Rebuild placement around an explicit per-editor transaction state machine, a
  callback-safe file-promise bridge, a dedicated non-main I/O executor, and descriptor-relative
  exclusive publication.

## Questions

1. How should paste/drop inputs cross from AppKit into asynchronous work without retaining stale
   pasteboard objects or performing file I/O on the main actor?
2. How can one `NSFilePromiseReceiver` safely deliver either one modern promise or several legacy
   promises?
3. How should an untitled-document action observe Save success, failure, or cancellation without
   watching unrelated sheets?
4. Which macOS filesystem primitives provide non-overwriting publication and resist symlink and
   directory-swap races?
5. How can parent-change warnings work after reopening without private metadata?

## Method

- Re-read REQ-060–REQ-077, ADR-0011, PLAN-0003, the merged implementation, its tests, and the
  post-merge review findings.
- Consulted current Apple documentation and the macOS 27 SDK headers for `NSFilePromiseReceiver`,
  `DocumentGroup`, `NSDocument`, and `NSFileCoordinator`.
- Inspected the installed macOS system-call manuals and SDK declarations for `openat`,
  `renameatx_np`, `linkat`, and `copyfile`.
- Compared three designs: patching the current path-based service, using only high-level
  Foundation APIs, and a transaction-oriented design with a small POSIX storage core.

No production code or POC was created.

## Findings

### 1. The AppKit boundary must be shallow

`NSTextView` paste and drag callbacks are main-actor entry points. They should only:

- decide whether meaningful text requires native fallthrough;
- copy stable scalar values such as strings, URLs, provider names, and declared types;
- snapshot bitmap bytes when the pasteboard offers no file representation; and
- synchronously reserve a placement transaction before launching asynchronous work.

Reading URL contents, validating regular-file status, invoking Image I/O, encoding PNG, hashing,
and touching destination storage are blocking work and do not belong at this boundary. A Swift
actor alone does not prove that blocking syscalls never execute on the main thread; the design
needs an injected, dedicated `OperationQueue` or equivalent executor whose queue identity can be
asserted in tests.

Apple's `DocumentGroup` documentation also warns against reading document contents or metadata
through its URL because that can conflict with SwiftUI's file management. The correction uses the
configuration URL only to locate the sibling destination, never to read or rewrite the Markdown
document itself.

Source:
[Apple — DocumentGroup](https://developer.apple.com/documentation/swiftui/documentgroup/).

### 2. File promises are one-to-many callbacks

Apple documents two shapes:

- item-based promises normally produce one receiver per file; and
- a legacy non-item-based pasteboard item can promise several files through one receiver.

The SDK header says `fileNames` is empty until `receivePromisedFiles` is invoked and is an array
specifically because a legacy receiver can represent multiple files. The reader callback runs
once for each ready or failed file, on the supplied operation queue. An error callback may point
at a partial file and that URL must be ignored.

Therefore a one-shot continuation around the reader callback is invalid. A correct bridge must:

1. use one private staging directory for every receiver in the drag;
2. invoke each receiver exactly once;
3. capture its expected `fileNames` after invocation;
4. collect exactly that receiver's callbacks in a lock/actor-protected accumulator;
5. record errors but wait for all expected callbacks;
6. resume the outer continuation exactly once; and
7. clean the entire staging directory on every terminal path.

The view must register `NSFilePromiseReceiver.readableDraggedTypes`, rather than a hand-maintained
subset, or AppKit may not deliver some legacy promise drags.

Sources:
[Apple — NSFilePromiseReceiver](https://developer.apple.com/documentation/appkit/nsfilepromisereceiver),
[Apple — receivePromisedFiles](https://developer.apple.com/documentation/appkit/nsfilepromisereceiver/receivepromisedfiles(atdestination:options:operationqueue:reader:)),
[Apple — readableDraggedTypes](https://developer.apple.com/documentation/appkit/nsfilepromisereceiver/readabledraggedtypes).

### 3. Save completion must come from the document operation

A global `NSWindow.didEndSheetNotification` cannot identify which document or operation ended and
necessarily races propagation of `FileDocumentConfiguration.fileURL`.

AppKit's document save API has a delegate callback that runs for success and failure, including
user cancellation. The adapter can resolve the `NSDocument` associated with the editor's window,
initiate the normal Save operation, and bridge that callback into the placement state machine.
The updated SwiftUI `fileURL` remains the authoritative resulting location; the callback is the
authoritative terminal signal. Placement resumes only when both indicate success.

Sources:
[Apple — NSDocument](https://developer.apple.com/documentation/appkit/nsdocument),
[Apple — save delegate callback](https://developer.apple.com/documentation/appkit/nsdocument/save(to:oftype:for:delegate:didsave:contextinfo:)).

### 4. Path validation followed by path mutation is not containment

`fileExists`, `resolvingSymlinksInPath`, and a later `copyItem` leave time-of-check/time-of-use
windows. A hostile or merely concurrent process can replace an ancestor or destination after the
check.

The installed macOS interfaces provide stronger building blocks:

- `openat` with `O_DIRECTORY`, `O_NOFOLLOW_ANY`, and `O_RESOLVE_BENEATH` opens relative to a
  trusted directory descriptor and rejects symlink traversal or escape;
- `fstat` establishes that an opened source is a regular file and supplies stable device/inode
  identity;
- `renameatx_np(..., RENAME_EXCL)` publishes a fully written same-volume staging file without
  replacing an existing destination;
- `linkat` can provide an atomic exclusive directory entry on volumes where the exclusive rename
  capability is unavailable; and
- `copyfile(..., COPYFILE_EXCL | COPYFILE_NOFOLLOW)` is a final non-overwriting fallback, with
  identity-checked cleanup if an incomplete destination is created.

These operations should run inside a coordinated directory write so cooperating file providers
and processes can prepare, but `NSFileCoordinator` is coordination—not an exclusive-create
primitive. The exclusive syscall remains the correctness boundary.

Local primary references: `man 2 open`, `man 2 rename`, `man 2 link`, `man 3 copyfile`, and the
macOS 27 SDK declarations in `sys/stdio.h`. Foundation coordination behavior:
[Apple — NSFileCoordinator](https://developer.apple.com/documentation/foundation/nsfilecoordinator).

### 5. Exact-copy validation should stream once

File-backed PNG, JPEG, GIF, HEIC, and HEIF need no decoded bitmap. The I/O service can open a
regular source without following links, stream it into private staging while computing SHA-256,
then ask Image I/O for the container type with caching disabled. This bounds memory use and
preserves every source byte, including HEIC/HEIF. Bitmap-only paste is the only path that encodes
PNG.

Before any destination is published, every batch item should be staged, typed, and hashed. This
turns unsupported/corrupt input into a preflight failure and sharply reduces rollback work.

### 6. Collision decisions need actual directory entries and a retry loop

A set of lowercased names loses the real entry spelling. On a case-sensitive volume,
`Photo.PNG` reserves the portable candidate `photo.png`, but the latter path does not name the
same entry. Reusing it would create a reference that behaves differently after copying the folder
to another filesystem.

The service should build a case-folded map to actual entries:

- reuse only an exact portable candidate whose regular-file bytes match;
- treat any case-only variant as a collision and choose the deterministic lowercase hash form;
- publish with an exclusive primitive;
- on `EEXIST`, reopen and compare the winner, then reuse or advance the deterministic candidate;
  and
- repeat until publication or a terminal I/O error.

A process-wide directory transaction registry prevents races among the app's own documents.
Exclusive publication and retry handle other processes.

### 7. Cleanup requires object identity

A filename that the transaction created can later be replaced. Cleanup must not unlink by name
alone. For every published file, retain its device/inode identity. Before rollback, inspect the
current directory entry without following links and unlink it only if the identity still matches.
Staging objects are always private to the transaction and can be removed wholesale.

This establishes a mechanical ownership proof for REQ-071.

### 8. Move warnings can be source-derived

In-memory generated-filename state cannot survive reopening, while private document metadata is
forbidden. Provenance is neither necessary nor recoverable.

Instead, a focused source scanner can find canonical local image destinations of the form
`assets/<portable-name>.(png|jpg|gif|heic|heif)`, excluding fenced code and code spans. On a
parent transition it compares resolution under the previous and new parents. If a reference
resolved before and does not resolve afterward, it warns. This is restart-independent and
non-destructive. It may also warn for a manually authored reference with the same canonical
shape; that conservative false positive is preferable to silently missing a broken companion
file and requires no hidden state.

## Options considered

| Option | Strengths | Failure |
|---|---|---|
| Patch the current coordinator and `FileManager` service | Small diff | Retains split ownership, path-based TOCTOU windows, memory-only lifecycle state, and weak test seams |
| High-level Foundation rewrite only | Idiomatic and compact | `NSFileCoordinator` does not supply atomic exclusive creation or descriptor-relative containment |
| Explicit transaction + non-main executor + descriptor-relative storage core | Mechanical invariants, deterministic races, bounded main-actor work, testable failure paths | Larger rewrite and a small audited Darwin/POSIX layer |

## Recommendation

Choose the third option and delete the current placement pipeline once its replacement passes.
This is a correction increment, not an incremental patch. Keep the stable product choices from
ADR-0011—ordinary Markdown, shared `assets/`, exact HEIC/HEIF, no Import command—but replace the
transaction, promise, save, warning, and filesystem mechanics as one coherent system.

No unresolved product question blocks a proposed plan. The proposed architecture still requires
the user's approval before implementation.
