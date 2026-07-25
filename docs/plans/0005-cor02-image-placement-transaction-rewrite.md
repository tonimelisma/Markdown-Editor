# PLAN-0005 — COR-02 image placement transaction rewrite

- **Increment:** COR-02
- **Date:** 2026-07-24
- **Status:** Approved
- **Requirements:** REQ-060–REQ-077
- **Depends on:** [RESEARCH-0005](../research/0005-image-placement-correction-architecture.md),
  [RESEARCH-0006](../research/0006-document-save-bridge-spike.md),
  [ADR-0011](../decisions/0011-image-placement-and-portability.md),
  [ADR-0012](../decisions/0012-transactional-descriptor-relative-image-placement.md)

## Goal

Replace INC-03's image-placement pipeline as one coherent system. A supported paste or drop
either completes exactly once—after every final asset safely exists—or ends without changing
source. It never overwrites or deletes unrelated files, never transcodes file-backed HEIC/HEIF,
never blocks the main thread with image or filesystem work, and behaves deterministically across
rapid actions, file promises, Save cancellation, reopening, parent changes, and concurrent
writers.

## Objectives

In priority order:

1. Restore INV-1 and INV-8–INV-10 mechanically, not by timing or path-check conventions.
2. Make every accepted user action a single stateful transaction with one owner and one terminal
   outcome.
3. Keep the main actor limited to AppKit/SwiftUI state and the final text mutation.
4. Preserve ordinary Markdown, shared `assets/`, and exact PNG/JPEG/GIF/HEIC/HEIF bytes.
5. Make every failure and race reproducible through unit/integration seams without UI tests.
6. Remove the flawed implementation rather than layering corrective branches around it.

## Non-negotiable invariants

1. **Single owner:** an editor has zero or one accepted image transaction. Reservation happens
   synchronously before asynchronous work starts.
2. **Single completion:** every accepted transaction reaches exactly one of `committed`,
   `cancelled`, or `failed`; late callbacks are ignored by transaction identity.
3. **Stable insertion intent:** selection tracking starts when the action is accepted, including
   time spent receiving promises or waiting for Save.
4. **No ambiguous overlap:** an edit inserted exactly at a zero-length tracked caret is an
   overlap and cancels source insertion.
5. **No main-thread storage work:** source reads, Image I/O, bitmap encoding, hashing, promise
   callbacks, comparison, publication, and cleanup execute on the dedicated I/O executor.
6. **Regular sources only:** sources are opened without following links and accepted only after
   `fstat` proves a regular file. Directories, packages, aliases, symlinks, sockets, devices, and
   FIFOs are rejected.
7. **Exact file-backed bytes:** file-backed PNG/JPEG/GIF/HEIC/HEIF is streamed unchanged. Only a
   bitmap-only paste is encoded as PNG. HEIC/HEIF is never converted to JPEG.
8. **Preflight before publish:** every batch member is received, staged, typed, and hashed before
   the first final destination is created.
9. **Atomic non-overwrite:** publication never replaces an existing entry. An exclusive
   collision causes byte comparison and deterministic retry, not action failure.
10. **Descriptor containment:** all destination operations are relative to trusted directory
    descriptors with no-follow/beneath semantics; a post-hoc string-prefix check is not the
    security boundary.
11. **Identity-pinned rollback:** every created final entry retains an open descriptor or private
    hard-link pin until commit or rollback. A final file is removed only when the directory entry
    still names the exact pinned object. A newly created `assets/` directory is removed only when
    its identity still matches and it is empty after private staging cleanup.
12. **Commit after storage:** one ordered Markdown replacement occurs only after all final files
    exist and the live document location still resolves under the parent established at acceptance.
    Text undo never removes files.
13. **Explicit Save result:** untitled placement follows the owning document's normal Save
    completion. Cancel or failure creates no `assets/` directory.
14. **Restart-independent warning:** parent-change checks derive canonical local image references
    from source and work after reopening, with no hidden metadata. Conservative false positives on
    equivalent manually authored references are accepted product behavior for REQ-076.

## Options and decision

| Design | Assessment |
|---|---|
| Repair the existing coordinator/service in place | Rejected: several timing fixes would still leave path-based mutation and split transaction ownership |
| Rewrite with `FileManager` and `NSFileCoordinator` only | Rejected: clear code, but no atomic exclusive publication or descriptor-relative containment boundary |
| Explicit state machine + promise/save bridges + dedicated I/O executor + narrow POSIX store | **Selected:** the smallest design that satisfies all invariants under concurrency and hostile filesystem inputs |

## Architecture

### `ImagePlacementController` (`@MainActor`)

Own a closed state enum rather than booleans:

```text
idle
  → accepted
  → receivingPromises? / awaitingSave?
  → staging
  → publishing
  → committing
  → committed | cancelled | failed
```

- `begin(action:)` transitions out of `idle` synchronously.
- A later action while non-idle is rejected immediately with one clear message; it is never
  silently queued or allowed to race.
- Each action has a UUID. Every async result must present the active UUID before changing UI.
- At acceptance, snapshot the document-location generation and URL. The I/O executor establishes
  the selected parent directory identity before storage work begins.
- Before source commit, prove that the live `DocumentGroup` URL still resolves under that same
  parent. A concurrent Save As, rename, or move cancels insertion rather than creating an
  immediately broken reference.
- The controller starts edit tracking at acceptance and owns the task/cancellation lifetime.
- Only `committing` mutates `NSTextStorage`; terminal cleanup always clears the tracker and state.

### `ImageActionSnapshot`

An immutable, `Sendable` description of provider order and claims:

- file URL + provider name + declared type;
- bitmap bytes + declared pasteboard type; or
- a promise-receipt token owned by the narrow AppKit bridge.

The main actor does no URL read or Image I/O. Meaningful text still takes native paste/drag
precedence. Obvious non-image URL claims fall through natively; accepted image claims are
content-validated later.

### `DocumentSaveBridge`

Resolve the editor window's owning `NSDocument` via
`NSDocumentController.document(for:)` (feasibility proven in
[RESEARCH-0006](../research/0006-document-save-bridge-spike.md)), invoke
`saveDocumentWithDelegate:didSaveSelector:contextInfo:`, and expose an async result through the
operation-scoped completion callback. Resume placement only after:

- the callback reports success; and
- `DocumentGroup` supplies a non-nil resulting URL for the same document.

Cancellation or save failure terminates the transaction and removes only private promise
staging. Delete the global sheet observer and delay heuristic.

### `FilePromiseBridge`

- Register every type in `NSFilePromiseReceiver.readableDraggedTypes`.
- Use one mode-0700 temporary directory for all receivers in one action.
- Invoke each receiver once and read its `fileNames` afterward to establish callback count.
- Collect all callbacks on one dedicated non-main operation queue.
- Keep per-receiver/provider order; record callback errors but wait for every expected callback.
- Resume its continuation once, after exact accounting; reject the whole action on any error.
- If not every expected callback arrives within the receipt deadline, fail the action once, keep
  draining until the expected callback count or an absolute grace timeout, then remove staging.
- Logical cancellation may finish the editor transaction, but it does not destroy staging while a
  provider may still be writing: the receipt owner remains alive, drains and ignores late
  callbacks, and cleans staging only after callback quiescence.

The callback collector is a separately unit-tested component; it is not an ad hoc continuation
inside the controller.

### `ImageIOExecutor`

A dedicated `OperationQueue` owns all blocking work. An async bridge submits typed operations and
resumes Swift continuations exactly once. Tests use a dispatch/queue-specific identity to prove
the storage and Image I/O seams never execute on the main queue.

Do not use `Task {}` or actor annotations alone as evidence of off-main execution.

### `ImageBatchPreflight`

For each provider-ordered input:

1. open without following links;
2. reject alias/package/non-regular objects;
3. stream bytes into private same-volume staging while computing SHA-256;
4. detect PNG/JPEG/GIF/HEIC/HEIF from staged content with Image I/O caching disabled; and
5. derive the portable stem and canonical extension.

Bitmap-only data is decoded/encoded to PNG on the I/O executor, then enters the same staged
pipeline. No final asset is published until every item passes.

### `AssetDirectoryStore`

A process-wide **non-reentrant keyed lease** serializes the complete asynchronous storage
transaction. Actor isolation alone is insufficient because an actor is reentrant while it awaits
blocking work on the I/O executor; awaiting the executor must not release the lease to a competing
transaction.

- Before `assets/` exists, the lease key is the opened parent directory's device/inode identity
  plus the literal child name `assets`.
- After creation, the service also validates the opened destination directory's identity.
- Blocking store calls execute on `ImageIOExecutor` while the lease is held.

The low-level store:

- opens the document parent and `assets/` with directory descriptors and no-follow/beneath flags;
- creates `assets/` only after Save success and rejects aliases, packages, links, or
  non-directories;
- enumerates a case-folded map that retains every actual directory-entry spelling;
- reuses only an exact portable candidate that is regular and byte-identical;
- treats case-only variants as occupied, selecting a lowercase hash candidate;
- publishes a fully written same-volume staged file with `renameatx_np(..., RENAME_EXCL)`;
- uses `linkat` only when it preserves the same exclusive, no-follow, descriptor-relative
  guarantees; a path-based `copyfile` fallback is prohibited—if no safe primitive is available,
  placement fails closed without source insertion;
- on collision, reopens the winner, compares bytes, and either reuses or advances the
  deterministic SHA-256 candidate; and
- returns device/inode ownership records plus open descriptor or private hard-link pins for every
  file created by the transaction.

Rollback compares the current entry identity with its pinned object before `unlinkat`. Anything
that cannot be proven remains untouched.

### `InsertionRangeTracker`

Replace the interval logic with explicit edit cases:

- insertion strictly before the tracked range shifts it;
- insertion at a zero-length caret cancels;
- insertion at the start or inside a non-empty replacement range cancels;
- replacement/deletion with a non-empty intersection cancels;
- an edit entirely after, including insertion at the non-empty range's end, does nothing.

All arithmetic uses checked/clamped UTF-16 ranges. Table-driven tests cover every boundary.

### `CanonicalAssetReferenceScanner`

A focused CommonMark-aware scanner finds canonical local `assets/` image references and compares
their old/new resolution without an in-memory provenance set or private metadata. It excludes
fenced and indented code blocks, code spans, escaped image syntax, and other literal contexts.
Conservative false positives on equivalent manually authored references are accepted product
behavior for REQ-076; warnings never mutate source or files.

On a parent change:

1. scan the current source;
2. retain references that resolved under the previous parent;
3. test the same relative paths under the new parent; and
4. emit one non-destructive warning if any became unresolved.

This replaces `knownGeneratedFilenames`; it works after reopening and adds no metadata.

## Implementation sequence

Each numbered step is one reviewable commit unless a root-cause fix requires two adjacent steps
to compile together.

1. **Remove prohibited UI-test infrastructure.** In a config-only mainline change, delete the
   UI-test target and generated UI-test source. Confirm the app and unit-test targets still build.
2. **Introduce pure models and state transitions.** Add action IDs, snapshots, terminal results,
   document-location generation/URL capture at acceptance, parent-identity establishment, and a
   fully unit-tested controller reducer/state machine. No existing path uses it yet.
3. **Replace insertion tracking.** Implement the explicit boundary policy and exhaustive
   zero/non-zero range fixtures (REQ-060, REQ-069, REQ-072).
4. **Build Save and promise bridges.** Add fakeable callback adapters via
   `NSDocumentController.document(for:)` and `saveDocumentWithDelegate`, exact callback
   accounting, receipt-deadline and grace-timeout hung-provider policy, documented drag-type
   registration, ordering, error, cancellation, and cleanup tests (REQ-060, REQ-063, REQ-075,
   REQ-077).
5. **Build the non-main preflight pipeline.** Add the executor, regular-file source checks,
   streaming hash/copy, content detection, bitmap PNG path, and all five exact-copy formats
   including fixture-backed HEIC and HEIF (REQ-061–REQ-063, REQ-077).
6. **Build the descriptor-relative store.** Add the non-reentrant keyed lease, safe directory
   opening/creation with post-create identity validation, actual-name collision maps, exclusive
   publication via `renameatx_np(RENAME_EXCL)` (or equivalent `linkat` only), identity-pinned
   ownership, and rollback (REQ-065–REQ-071, REQ-077).
7. **Build restart-independent parent checks.** Add the CommonMark-aware reference scanner with
   fence/code-span/escape exclusion and old/new resolution comparison; accept conservative false
   positives for REQ-076.
8. **Integrate the new controller.** Route paste/drop through the new action boundary, prove
   live document location still resolves under the accepted parent before source commit, make one
   source commit/undo group, preserve native non-image behavior, and verify actionable terminal
   messages (REQ-060, REQ-064, REQ-069–REQ-075).
9. **Delete the old pipeline.** Remove the old coordinator flags, global sheet observer,
   one-shot promise continuation, synchronous file classifier, path-based exclusive copy, and
   in-memory generated-name set. No dual implementation or feature flag remains.
10. **Reconcile and review.** Update exact code/test anchors and statuses only after tests pass;
    perform the separate-agent review and PR-comment triage before squash-merge.

## Automated verification

No UI tests and no manual tests.

| Area | Required unit/integration cases |
|---|---|
| State machine | simultaneous begin; late result from old UUID; every state/error/cancel reaches one terminal state; state always returns idle; document-location generation/URL snapshot at accept |
| Main boundary | injected executor proves file read, Image I/O, encoding, hashing, promise callback, publish, and cleanup never run on main queue |
| Tracker | zero-length insertion before/at/after; non-empty start/interior/end; deletion/replacement boundaries; UTF-16 and range clamping |
| Promise | modern one receiver/one file; several receivers; legacy one receiver/many files; out-of-order callbacks; partial error; duplicate/late callback; receipt deadline with grace drain; cancellation leaves staging until quiescence; exact one resume; cleanup |
| Save | saved document; untitled success via `document(for:)` + delegate callback; cancel; failure; unrelated sheet signal has no effect; URL update before/after callback |
| Sources | regular files for PNG/JPEG/GIF/HEIC/HEIF; exact bytes and SHA-256; alias; package; symlink; directory; FIFO; socket/device seam; provider failure |
| Batch | all preflight before publish; provider order; unsupported later item publishes nothing; cancellation at every phase |
| Names | portable stems; case-only existing entry on case-sensitive fixture; identical exact reuse; deterministic hash extension |
| Races | two documents same candidate/same bytes; same candidate/different bytes; external winner before exclusive publish; repeated prefix conflicts; no overwrite; lease held across I/O await |
| Containment | swapped parent/assets entry; destination symlink; `..`; hostile provider name; no-follow/beneath failures; post-create assets identity validation |
| Cleanup | private staging; first/last publish failure; winner replaced before rollback; inode mismatch leaves entry untouched; identity-pinned descriptor/hard-link proof; reused/pre-existing entries untouched; empty `assets/` removed only on identity match |
| Commit/undo | one ordered replacement; selection replacement; single-image description selection; overlap leaves files but no source; undo removes source only; Save As/rename/move before commit cancels insertion |
| Parent change | reopen then move; Save As; rename same parent; previously missing reference; old-resolved/new-missing warning; fence/indented-code/code-span/escape exclusion; conservative false positive on manually authored canonical reference |
| Native fallthrough | meaningful text+image; obvious non-image URL; unsupported pasteboard type; standard plain-text paste remains native |
| Publication | `renameatx_np(RENAME_EXCL)` success; `linkat` only when equivalent guarantees; no path-based `copyfile`; fail closed when no safe primitive |

Use injected filesystem, save, promise, and executor seams for deterministic errors. Use real
temporary directories for descriptor, identity, race, and exact-byte integration tests. Tests
must assert the intended behavior, not merely invoke the implementation.

## Acceptance gates

COR-02 cannot be marked Done unless:

- every invariant above has an automated verification or a narrowly justified inherent proof;
- repeated concurrent-race tests pass under Thread Sanitizer in a non-UI unit-test scheme;
- no blocking storage/Image I/O call is reachable from a main-actor paste, drag, or Save callback;
- no code path uses `fileExists` followed by mutation as its exclusivity or containment boundary;
- no code path uses path-based `copyfile` as a publication fallback;
- the non-reentrant keyed lease prevents overlapping storage transactions for the same parent
  across I/O awaits;
- identity-pinned cleanup is proven for every created final entry and newly created `assets/`;
- source commit is blocked when the live document location no longer resolves under the accepted
  parent;
- no one-shot continuation wraps a one-to-many callback API;
- promise cancellation does not destroy staging before callback quiescence;
- reopening a document does not change parent-warning behavior;
- the old implementation is absent; and
- REQUIREMENTS and ROADMAP no longer claim the defective INC-03 implementation is complete.

## Risks and mitigations

- **Low-level filesystem code:** keep it in one small module with errno-to-domain-error mapping,
  descriptor lifetime wrappers, no force unwraps, and real-volume integration tests.
- **Volume capability differences:** test preferred `renameatx_np(RENAME_EXCL)` and equivalent
  `linkat` only; if no safe exclusive mechanism exists, fail without source insertion or overwrite.
- **Provider callbacks do not honor assumptions:** callback accounting is based on documented
  `fileNames`, records all errors, rejects mismatch, never resumes twice, and drains through
  receipt deadline and grace timeout before staging removal.
- **Conservative move warnings (approved):** they are informational and non-destructive; false
  positives on equivalent manually authored canonical references are accepted for REQ-076; false
  negatives would be worse.
- **Large files:** stream with bounded buffers; never load file-backed images or existing assets
  wholly into `Data`.

## Out of scope

WYSIWYG rendering, thumbnails, image dimensions, transcoding, metadata stripping, optimization,
remote images, file-picker insertion, automatic asset relocation, garbage collection, package
documents, and “Save a Copy with Assets.” There is still no Import command.
