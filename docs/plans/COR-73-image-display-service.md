# COR-73 — Image identity and decode service

- **Status:** Approved; not implemented
- **Delivers:** REQ-085
Architecture impact: none; consolidates derived image display under ARC-006, ARC-023, and ARC-Q19
Blockers: COR-69
Executor: A junior developer may implement this plan in order. Obtain senior review of filesystem identity, containment, and in-flight coalescing before deleting the old routes.

## Outcome

Resolve and decode a referenced local image only on metadata-cache miss, at the actual backing scale,
under one dedicated service. Full SHA-256 remains an asset-placement naming decision—not a display
cache precondition. MD5 and sampled hashes are never correctness identities.

## Files and ownership

- Add `ImageDisplayService.swift` with `ImageReferenceKey`, `FileIdentitySnapshot`,
  `ImageDecodeRequest`, and bounded `ImageDisplayCache`.
- Consolidate `LocalImageResolver`, `LocalImageDecoder`, `ParseCoordinator` image tasks, and any view
  decode logic into the service; delete displaced duplicate caches/routes.
- Thread document location generation, source revision, reference identity, request generation,
  pixel target, appearance, and backing scale through immutable requests/results.
- Keep `AssetDirectoryStore` SHA-256 exact-copy naming independent from display cache identity.

## Implementation

1. Write red file-operation-spy tests for cache hit reread, stat identity change, symlink/package,
   over-limit sparse file, rapid backing-scale changes, cancellation, eviction, and stale result.
2. Resolve containment and regular-file identity without bulk read. Cache key uses canonical reference,
   stable file metadata available on macOS, pixel target, scale, and appearance.
3. On miss, read/decode off main with encoded and decoded size limits checked before allocation.
   Coalesce identical in-flight requests and cap memory with deterministic cost eviction.
4. Apply only to the same document/session/location/source/reference/request identity. Failed results
   are typed, short-lived where retryable, and never poison a changed file.
5. Record cache hit/miss, bytes read, decode count/duration, rejected size/type, cancellation, and
   identity discard under the originating intent.

## Proof and failure behavior

- A hit performs zero open/read/hash/decode operations; a metadata change causes exactly one miss.
- Scale 1×/2×/3× requests produce bounded pixel dimensions derived from the real backing scale.
- Over-limit/symlink/package/outside-assets inputs are rejected before bulk read or decode.
- Concurrent equal requests decode once; cancellation and stale identities apply nothing.
- Existing exact-byte image placement and SHA-256 collision naming tests remain green.

## Deletion/conformance gate

No display route computes MD5, a sampled digest, or a full-file hash before cache lookup; no view or
parse coordinator decodes directly; no duplicate image cache remains.
