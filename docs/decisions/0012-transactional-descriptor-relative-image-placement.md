# ADR-0012 — Transactional, descriptor-relative image placement

- **Status:** Proposed
- **Date:** 2026-07-24
- **Deciders:** Toni Melisma
- **Related:** COR-02; REQ-060–REQ-077;
  [ADR-0011](0011-image-placement-and-portability.md);
  [RESEARCH-0005](../research/0005-image-placement-correction-architecture.md)

## Context

INC-03 implemented the approved user-visible policy but its mechanics do not satisfy the
transaction, concurrency, lifecycle, and containment requirements. The merged design permits
overlapping actions, performs source inspection on the main actor, mishandles multi-file promise
callbacks, races Save completion, forgets generated references after reopening, and relies on
path checks followed by later path mutations.

Small fixes would leave several independent owners of one logical transaction. The correction
needs one architecture whose boundaries make the invariants mechanically testable.

## Proposed decision

Keep ADR-0011's product and compatibility policy, but replace the implementation with:

1. **One explicit transaction per editor.** A main-actor state machine reserves an action
   synchronously and moves through capture, optional Save, promise receipt, staging, publication,
   source commit, and one terminal state. A later action is explicitly rejected while one is
   active.
2. **A shallow AppKit adapter.** Paste and drag code snapshots stable declared values but never
   reads files, inspects images, hashes, encodes, or touches destination storage.
3. **An operation-scoped Save bridge.** Untitled placement uses the owning `NSDocument` Save
   completion callback and the resulting `DocumentGroup` URL. It observes no global sheet
   notification and uses no timing heuristic.
4. **A one-to-many promise bridge.** It uses
   `NSFilePromiseReceiver.readableDraggedTypes`, one staging directory per action, a non-main
   operation queue, expected callback accounting from `fileNames`, and exactly one continuation
   completion.
5. **A dedicated I/O executor.** All blocking source inspection, PNG encoding, streaming,
   hashing, directory operations, comparison, publication, and cleanup run away from the main
   actor and main thread.
6. **A shared storage authority.** A process-wide service serializes transactions by destination
   directory identity. A small Darwin/POSIX core uses directory descriptors, no-follow/beneath
   resolution, regular-file `fstat`, fully written staging, exclusive publication, and retry.
7. **Identity-proven cleanup.** Rollback removes a published entry only when its current
   device/inode identity matches the entry created by that transaction.
8. **Source-derived move warnings.** A focused scanner finds canonical local `assets/` image
   references and compares their old/new resolution. No in-memory provenance set or private
   metadata is used.

The old placement implementation is deleted after replacement; the product will not retain two
pipelines or compatibility shims.

## Consequences

- **Positive:** concurrency, containment, cleanup ownership, promise completion, and main-thread
  behavior become explicit invariants with deterministic tests.
- **Positive:** exact PNG/JPEG/GIF/HEIC/HEIF bytes and ordinary Markdown remain unchanged.
- **Positive:** warnings work after reopening and across Save As or external moves.
- **Cost:** the implementation is a larger rewrite and contains a small low-level filesystem
  module that must be narrow, documented, and exhaustively tested.
- **Cost:** canonical-reference scanning can conservatively warn about an equivalent manually
  authored reference; it never mutates source or files.

## Alternatives

- Patch the current classes: rejected because it preserves the ownership and TOCTOU failures.
- Treat `NSFileCoordinator` as the exclusive-write mechanism: rejected because coordination does
  not atomically reserve a destination name.
- Add hidden provenance metadata: rejected by INV-3 and ADR-0011.
- Convert HEIC/HEIF: rejected; the file-backed path remains exact-copy.
