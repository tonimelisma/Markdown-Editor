# COR-78 — Image placement transaction

- **Status:** Approved; not implemented
- **Delivers:** REQ-060, REQ-061, REQ-062, REQ-063, REQ-064, REQ-065, REQ-066, REQ-067, REQ-068, REQ-069, REQ-070, REQ-071, REQ-072, REQ-073, REQ-074, REQ-075, REQ-077
Architecture impact: none; verifies ARC-012 as one exact-copy, contained transaction
Blockers: COR-68, COR-70, COR-73, COR-74
Executor: A junior developer may implement from the specified cross-product matrix. Obtain senior review of containment and rollback ownership before production file operations change.

## Scope and files

Own paste/drop/Add Image entry adapters, `ImagePlacementController`, provider acquisition,
representation inspection, `AssetDirectoryStore`, placement claims, tracked insertion, Markdown
reference creation, operation-scoped Save, rollback, alerts, and diagnostics. Display decode is not
part of this increment.

## Implementation

1. Build a cross-product fixture matrix: entry route × PNG/JPEG/GIF/HEIC/HEIF regular file × bitmap
   data × file promise × meaningful text × multiple providers × saved/untitled document × collision/
   reuse × symlink/alias/package/outside path × edit overlap × failure phase.
2. Exercise each through the public entry adapter. All routes create one immutable
   `ImagePlacementRequest` with ordered claims, source selection/version/location generation, and
   `IntentID`, then enter one controller.
3. Inspect type/size/containment off main; exact-copy supported regular files; PNG-encode only bitmap
   fallback; compute full SHA-256 only for deterministic collision naming; stage writes in the final
   contained directory and commit all files before source.
4. Commit one source replacement through the transaction kernel. Select the one empty description
   for immediate authoring. Register one undo item for source only; never delete assets on undo.
5. On any failure/cancel/stale overlap, remove only action-owned temporary/new files and leave source,
   reused/pre-existing assets, and native text paste untouched. Record typed phases/failures.

## Proof and failure behavior

Every route has success and failure liveness. Byte fixtures remain identical; ordering and one-undo
semantics are exact; Save cancellation creates no assets; case-insensitive collisions never
overwrite; unsafe paths are rejected before I/O; rollback ownership is adversarially proved.
Concurrent placements and edits cannot relocate a captured insertion or cross document identity.

## Deletion/conformance gate

One production placement controller and one asset store exist. No entry route performs its own copy,
hash, Markdown insertion, rollback, or alert assignment; no compatibility scanner or destructive
asset cleanup remains.
