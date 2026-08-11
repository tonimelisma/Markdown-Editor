# COR-47 — Image identity, sampled digest, and Retina decode

- **Status:** Approved; not implemented
- **Requirements:** REQ-081 (bounded display decode), REQ-085 (off-main work), REQ-067 (asset naming — explicitly unchanged), REQ-107 (image presentation), REQ-123 (`fileBytesRead` gate)
- **Delivers:** REQ-081, REQ-085, REQ-107
- **ARC invariants:** ARC-023 restated as "rejects over-limit encoded files **and satisfies cache hits** before bulk read, hash, or decode"; ARC-012 (one exact-copy placement transaction) unchanged

## Context

`LocalImageDecoder.decode` (`LocalImageDecoder.swift:39`) unconditionally performs, for every
referenced image, on every call: `stat`, a full `Data(contentsOf:, .mappedIfSafe)`, a **SHA-256 over
the whole file**, `CGImageSourceCreateWithData`, a property read, and a full thumbnail decode.

Only afterwards does the main actor consult `LocalImageCache.image(for:)`
(`LocalImageResolver.swift:101`) — and because the cache key **contains the content digest**, the
expensive work is a precondition of the lookup. The cache cannot prevent any of the work it exists to
prevent; all it saves is wrapping an already-decoded `CGImage` in an `NSImage`.

`ParseCoordinator.scheduleParse` runs this for every image attachment on every parse, and
`EditorSession.perform` schedules a parse after every accepted edit. `LatestParseScheduler` coalesces,
so it is not literally per keystroke — it is continuously, as fast as the pipeline allows, for as long
as the user keeps typing. A document with ten 5 MB photos re-reads and re-hashes 50 MB per cycle while
a sentence is typed. This contradicts `ENGINEERING.md` §11's own stated intent, which is true of
opening a document and false of editing one.

Separately, `maxDisplayEdge` is 512 **pixels** while `maximumReadingMeasure` is 720 **points** —
1440 px on a Retina display. Every image is upscaled roughly 2.8× and is visibly soft, and
`AttributedPresentationBuilder.makeAttachment`'s `image.size.width > maxWidth` downscale branch
(`:381`) is unreachable dead code.

## Phase 0 — POC: measure the cost of identity before choosing an algorithm

Throwaway executable at `/POC/ImageDigestBench/`, deleted before the PR opens; findings commit to
`docs/research/`.

Ten warmups, forty samples, Release, over synthetic files of 64 KiB, 1 MiB, 8 MiB, 64 MiB, 200 MiB:

| ID | Measure |
| --- | --- |
| P1 | `CryptoKit.SHA256` over the whole file |
| P2 | `CryptoKit.Insecure.MD5` over the whole file |
| P3 | `crc32_z` (zlib, hardware path) over the whole file |
| P4 | stdlib `Hasher` over the whole file |
| P5 | **Sampled SHA-256**: size ‖ first 64 KiB ‖ middle 64 KiB ‖ last 64 KiB |
| P6 | `stat` only, no read |
| P7 | today's full `LocalImageDecoder.decode`, for scale |

Record throughput, absolute milliseconds, and whether mapped-page faults dominate (P1 with cold versus
prewarmed pages).

**A hypothesis to confirm or refute, not assume:** on Apple Silicon, SHA-256 executes on the ARMv8
SHA-2 instructions and MD5 has no such path, so P2 may be *slower* than P1. If so, "use a faster
hash" is the wrong lever and the research file must say so rather than quietly keeping SHA-256 as if
by preference.

### Decision table — applied mechanically, no deliberation

| Observation | Action |
| --- | --- |
| P6 ≪ P1 (expected: three or more orders of magnitude) | Phase 1 proceeds. **Stat identity gating the read is the primary fix regardless of every other row.** |
| P5 < 0.2 × P1 at 8 MiB | Phase 2 adopts `SampledDigest` as the display-cache identity |
| P5 ≥ 0.2 × P1 at 8 MiB | Skip Phase 2; keep full SHA-256 on the decode path; record why |
| P2 < 0.7 × P1 at 8 MiB | Additionally switch the *display-cache* digest to MD5, recording the hardware finding |
| P2 ≥ 0.7 × P1 | Keep SHA-256; record that the faster-hash hypothesis was refuted |
| P3 ≪ P1 | Do **not** adopt CRC32. Thirty-two bits birthday-collide near 65k entries, which a long-lived cache reaches; record the rejection so it is not re-proposed |
| every row | `ImageAssetPolicy` and `AssetDirectoryStore` keep full SHA-256 unconditionally — they name files on disk (REQ-067) and are a collision-sensitive problem of a different kind |

**Then, without stopping:** write `docs/research/DISC-03-image-identity-cost.md` (evidence-only
authority, first-researched and last-verified dates, machine, OS build, method, full table, branch
applied, refresh triggers), delete the POC, rewrite Phases 1–3 below to match the chosen branch,
commit the rewrite, and continue into implementation.

## Phase 1 — stat identity gates the read

New in `Markdown Editor/LocalImageDecoder.swift`:

```swift
/// Cheap file identity: everything obtainable from stat(2) without reading a byte.
///
/// A content digest is a stronger identity, but computing one requires reading the whole file — so it
/// cannot be a *precondition* of a cache lookup without defeating the cache. Stat identity gates the
/// read; a digest remains the stored identity for correctness.
nonisolated struct ImageFileIdentity: Hashable, Sendable {
    let path: String
    let fileSize: Int64
    let modificationTime: TimeInterval
    let inode: UInt64
    let locationGeneration: UInt64
}

static func identity(destination: String, documentURL: URL?, locationGeneration: UInt64)
    -> Result<ImageFileIdentity, LocalImageResolveFailure>
```

`identity` performs only: remote-URL rejection, path resolution, containment, `fileExists`, the
extension allowlist, `attributesOfItem` (type, size, mtime, `systemFileNumber`), and the 256 MiB gate.
**No `Data(contentsOf:)`, no hash, no `CGImageSource`.** Every rejection decidable from metadata is
decided here, with its existing typed failure unchanged, so ARC-023's "reject before bulk read" gets
stronger rather than weaker.

`decode` keeps its current body but takes an already-computed `ImageFileIdentity` and skips the work
`identity` performed.

`LocalImageByteCache.Key` becomes `ImageFileIdentity + displayEdge`; `contentDigest` moves to a stored
field on `Entry`.

Ordering across the actor boundary — the cache is `@MainActor`, the resolve loop is a detached task.
Snapshot before dispatching, in `ParseCoordinator.scheduleParse`:

```swift
let cachedIdentities = session.imageCache.currentIdentities()   // Set<ImageFileIdentity>, Sendable
```

and inside the loop add a `case .success(let id) where cachedIdentities.contains(id)` arm that records
a hit and reads nothing.

**Why inode + size + mtime suffices here, stated in the code and not only in this plan:** defeating it
requires a writer that deliberately preserves all three, which is not a threat model a *display* cache
owes a defence against. REQ-067's on-disk naming is untouched and still hashes every byte.

## Phase 2 — sampled digest (only if Phase 0 selects it)

```swift
/// Content identity for a *display* cache: size plus three 64 KiB windows.
///
/// A display cache asks "is this the same picture I already decoded", not "did an adversary craft a
/// collision". Reading 192 KiB instead of 200 MB is a larger win than any choice of algorithm — and
/// the algorithm choice was measured (DISC-03), not assumed.
nonisolated struct SampledDigest: Hashable, Sendable {
    let fileSize: Int64
    let hex: String
}
```

## Phase 3 — decode for the size actually drawn

```swift
/// Longest edge in *pixels*. The reading measure is in points and Retina draws two pixels per point,
/// so decoding to the point value produced a visibly soft image at every size above ~256 pt.
static let maxDisplayEdge: CGFloat = MarkdownTypography.maximumReadingMeasure * 2   // 1440
```

`LocalImageCache.image(for:)` constructs the `NSImage` at **point** size rather than pixel size:

```swift
let scale = NSScreen.main?.backingScaleFactor ?? 2
NSImage(cgImage: cg, size: NSSize(width: CGFloat(cg.width) / scale, height: CGFloat(cg.height) / scale))
```

This makes `makeAttachment`'s downscale branch live code rather than dead code.

**Cache budget consequence, stated rather than discovered later:** at 1440 px worst case an entry
costs ~8.3 MB, so the 64 MiB bound holds roughly eight large images instead of the current ~32.
Measure against the `imageHeavy` corpus; if it thrashes, raise the bound to 128 MiB **in this change,
with the measurement recorded**, and update `ENGINEERING.md` §11. Silent thrashing is not an
acceptable outcome of a performance increment.

## Phase 4 — budget the metric that already exists

`imageResolution` carries an unasserted 100 ms budget. Tighten to **16 ms** and assert it on the
`imageHeavy` corpus (20 images of roughly 2 MB). A hundred milliseconds of image work per
reconciliation is a ceiling, not a budget.

## Proof

- `repeatedReconciliationDoesNotRereadUnchangedImages` — asserts `WorkLedger.fileBytesRead == 0` on the
  second reconciliation over unchanged images. **Rehearsed failing** against today's code, which reads
  the whole corpus every pass. This is the increment's headline proof.
- `touchingAnImageInvalidatesItsCacheEntry` — same path, changed mtime, re-decoded.
- `replacingAnImageWithSameSizeAndMtimeIsDetectedByInode` — the residual identity case.
- `imagesDecodeAtBackingScaleForTheReadingMeasure` — for a source wider than 1440 px, assert the
  decoded `CGImage` width is at least `min(sourceWidth, 1440)` and the resulting `NSImage.size` is in
  points.
- `oversizedImagesAreStillRejectedFromMetadataAlone` — the existing over-limit sparse-file proof, now
  run against `identity` rather than `decode`, so ARC-023 is proved on the new gate.
- `assetNamingStillHashesEveryByte` — REQ-067's naming path still computes a full-file SHA-256. This
  exists so no future reader mistakes the display-cache relaxation for a relaxation of the naming
  guarantee.
- `imageResolutionP95Under16ms` on the `imageHeavy` corpus.

## Instrumentation and performance evidence

Re-record `docs/research/performance-baseline.md`; quote `bytes read/edit` before and after (expected:
tens of megabytes → zero on a steady-state document) and `imageResolution` p95. Record the decoded
cache entry count and whether the bound was raised.

## Failure / rollback

Independent of the edit path; revert is one commit. The risk is a **stale image**: an identity that
misses a real content change would leave a decoded image on screen after the file changed. Mitigations,
in order: inode participates in the key, so an atomic replace is caught; mtime participates, so an
in-place rewrite is caught; and `locationGeneration` participates, so Save As or a move invalidates
everything. `touchingAnImageInvalidatesItsCacheEntry` and
`replacingAnImageWithSameSizeAndMtimeIsDetectedByInode` are the proofs, and both must be rehearsed
failing.

If Phase 0 refutes every digest option, Phases 1, 3 and 4 still land — the primary fix does not depend
on the digest question at all.

## Deletion / conformance gate

- No call site reaches `LocalImageDecoder.decode` without first obtaining an `ImageFileIdentity`;
  `decode`'s signature enforces it, so this is a compiler guarantee rather than a convention.
- The unreachable downscale branch in `makeAttachment` is either live or deleted — not left as dead
  code with a comment.
- The 512 px constant no longer exists anywhere in the tree.
- `Scripts/check-documentation-authority.sh`, `Scripts/check-instrumentation-coverage.sh` and
  `Scripts/check-proof-results.sh` pass.
