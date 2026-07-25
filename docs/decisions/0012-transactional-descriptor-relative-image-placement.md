# ADR-0012 — Transactional, descriptor-relative image placement

- **Status:** Accepted
- **Date:** 2026-07-24
- **Deciders:** Toni Melisma
- **Related:** COR-02; REQ-060–REQ-077;
  [ADR-0011](0011-image-placement-and-portability.md);
  [RESEARCH-0005](../research/0005-image-placement-correction-architecture.md);
  [PLAN-0005](../plans/0005-cor02-image-placement-transaction-rewrite.md)

## Context

INC-03 implemented the approved user-visible policy but its mechanics do not satisfy the
transaction, concurrency, lifecycle, and containment requirements. The merged design permits
overlapping actions, performs source inspection on the main actor, mishandles multi-file promise
callbacks, races Save completion, forgets generated references after reopening, and relies on
path checks followed by later path mutations.

Small fixes would leave several independent owners of one logical transaction. The correction
needs one architecture whose boundaries make the invariants mechanically testable.

## Decision

Keep ADR-0011's product and compatibility policy, but replace the implementation with:

1. **One explicit transaction per editor.** A main-actor state machine reserves an action
   synchronously and moves through capture, optional Save, promise receipt, staging, publication,
   source commit, and one terminal state. A later action is explicitly rejected while one is
   active. Acceptance also snapshots the document-location generation and URL; the I/O executor
   establishes the selected parent directory identity before storage work. Before source commit,
   the transaction must prove that the live `DocumentGroup` URL still resolves under that same
   parent; a concurrent Save As, rename, or move cancels insertion rather than creating an
   immediately broken reference.
2. **A shallow AppKit adapter.** Paste and drag code snapshots stable declared values but never
   reads files, inspects images, hashes, encodes, or touches destination storage.
3. **An operation-scoped Save bridge.** The documented `DocumentGroup` configuration URL is
   authoritative. Untitled placement resolves the owning `NSDocument` for the editor window via
   `NSDocumentController.document(for:)` (feasibility proven in
   [RESEARCH-0006](../research/0006-document-save-bridge-spike.md)), initiates normal Save, and
   resumes only after the operation-scoped completion callback reports success and the matching
   `DocumentGroup` URL becomes non-nil. It observes no global sheet notification and uses no
   timing heuristic.
4. **A one-to-many promise bridge.** It uses
   `NSFilePromiseReceiver.readableDraggedTypes`, one staging directory per action, a non-main
   operation queue, expected callback accounting from `fileNames`, and exactly one continuation
   completion. Logical cancellation may finish the editor transaction, but it does not destroy
   staging while a provider may still be writing: the receipt owner remains alive, drains and
   ignores late callbacks, and cleans staging only after callback quiescence. If not every
   expected callback arrives within the receipt deadline, the bridge fails the action once and
   keeps draining until expected count or an absolute grace timeout, then removes staging.
5. **A dedicated I/O executor.** All blocking source inspection, PNG encoding, streaming,
   hashing, directory operations, comparison, publication, and cleanup run away from the main
   actor and main thread.
6. **A non-reentrant shared storage lease.** A process-wide keyed lease, not actor isolation
   alone, serializes the complete asynchronous storage transaction. Before `assets/` exists, its
   key is the opened parent directory's device/inode identity plus the literal child name
   `assets`; after creation, the service also validates the opened destination directory's
   identity. Awaiting the I/O executor must not release this lease to a competing transaction.
7. **Coordinated, descriptor-relative exclusive publication.** `NSFileCoordinator` coordinates
   with file presenters and the store opens the accessor-provided location. The correctness
   boundary remains a narrow Darwin/POSIX core using directory descriptors, no-follow/beneath
   resolution, regular-file `fstat`, descriptor-relative same-volume staging, and fully written
   exclusive publication. Prefer `renameatx_np(..., RENAME_EXCL)` and use `linkat` only when it
   preserves the same guarantees. A path-based `copyfile` fallback is prohibited; if no safe
   primitive is available, placement fails closed without source insertion.
8. **Identity-pinned cleanup.** For every created final entry, the transaction retains an open
   descriptor or private hard-link pin until commit or rollback. Rollback removes the final entry
   only when its current device/inode identity matches that pinned object. A newly created
   `assets/` directory is removed only when its identity still matches and it is empty after
   private staging cleanup.
9. **Source-derived move warnings (approved).** A focused CommonMark-aware scanner finds
   canonical local `assets/` image references and compares their old/new resolution without an
   in-memory provenance set or private metadata. It excludes fenced and indented code blocks,
   code spans, escaped image syntax, and other literal contexts. Conservative false positives on
   equivalent manually authored references are accepted product behavior for REQ-076; warnings
   never mutate source or files.

The old placement implementation is deleted after replacement; the product will not retain two
pipelines or compatibility shims.

## Consequences

- **Positive:** concurrency, containment, cleanup ownership, promise completion, and main-thread
  behavior become explicit invariants with deterministic tests.
- **Positive:** exact PNG/JPEG/GIF/HEIC/HEIF bytes and ordinary Markdown remain unchanged.
- **Positive:** warnings work after reopening and across Save As or external moves without
  private provenance.
- **Cost:** the implementation is a larger rewrite and contains a small low-level filesystem
  module that must be narrow, documented, and exhaustively tested.
- **Cost:** promise cancellation can outlive the editor transaction while the bridge safely
  drains provider callbacks.
- **Cost:** REQ-076 may warn about a manually authored canonical `assets/…` reference that
  became unresolved after a parent change.

## Alternatives

- Patch the current classes: rejected because it preserves the ownership and TOCTOU failures.
- Treat `NSFileCoordinator` as the exclusive-write mechanism: rejected because coordination does
  not atomically reserve a destination name.
- Rely on actor isolation to serialize storage: rejected because an actor is reentrant while it
  awaits blocking work on the I/O executor.
- Fall back to path-based `copyfile`: rejected because it loses the descriptor-relative ancestor
  guarantee.
- Add hidden provenance metadata: rejected by INV-3 and ADR-0011.
- Convert HEIC/HEIF: rejected; the file-backed path remains exact-copy.
