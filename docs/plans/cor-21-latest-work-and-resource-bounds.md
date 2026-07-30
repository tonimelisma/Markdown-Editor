# COR-21 — Latest-work scheduling and resource bounds

- **Status:** Approved; not implemented
- **Kind:** App-code correction; one worktree, branch, PR, and squash merge
- **Requirements:** REQ-081, REQ-085, REQ-090, REQ-111, REQ-112
- **Architecture:** Implements ARC-022, ARC-023, ARC-Q18, ARC-Q19; preserves ARC-006 and ARC-012
- **Depends on:** COR-18; may run after COR-19 independently of INC-05/COR-20

## Goal

Prevent obsolete parsing and unbounded referenced-image work from consuming resources, and delete
the line-oriented secondary Markdown scanner used for asset references.

## Baseline defects to reproduce

1. Hold `MarkdownParser.parseLock`, enqueue several revisions, cancel all but the latest, release
   the lock, and demonstrate that a cancelled waiter can still copy and parse its full source.
2. Reference a very large sparse regular file with a supported extension and demonstrate that
   `LocalImageDecoder` attempts `Data(contentsOf:)` and SHA-256 before rejecting dimensions/type.
3. Exercise fence/list indentation cases where `CanonicalAssetReferenceScanner` disagrees with
   cmark about whether an image reference is inside literal code.

Do not create a real 256 MiB committed fixture. Tests create sparse/temp files and use operation
spies.

## Files

### Modify

- `Markdown Editor/MarkdownParser.swift`
- `Markdown Editor/EditorSession.swift`
- `Markdown Editor/EditorSemanticWorker.swift`
- `Markdown Editor/LocalImageDecoder.swift`
- `Markdown Editor/LocalImageResolver.swift`
- `Markdown Editor/ImageAssetPolicy.swift`
- `Markdown Editor/MarkdownAST.swift`
- `Markdown Editor/MarkdownSourceIndex.swift`
- `Markdown Editor/AssetDirectoryStore.swift` only where reference queries currently use the
  scanner
- `Markdown EditorTests/ReconciliationInvariantTests.swift`
- `Markdown EditorTests/LocalImageAndPasteTests.swift`
- `Markdown EditorTests/ImagePlacementTests.swift`
- `Markdown EditorTests/MarkdownParserTests.swift`
- `docs/ENGINEERING.md`
- `docs/REQUIREMENTS.md`
- `docs/ROADMAP.md`
- `docs/research/image-portability-and-safety.md`

### Add

- `Markdown Editor/LatestParseScheduler.swift`
- `Markdown Editor/EncodedImageInspection.swift`
- `Markdown Editor/CanonicalAssetReferences.swift`
- `Markdown EditorTests/LatestParseSchedulerTests.swift`
- `Markdown EditorTests/EncodedImageResourceTests.swift`
- `Markdown EditorTests/CanonicalAssetReferenceTests.swift`

### Delete

- `Markdown Editor/CanonicalAssetReferenceScanner.swift`
- all tests that validate the secondary scanner's private fence grammar rather than cmark results
- direct `Data(contentsOf:)` before encoded-file limit enforcement
- this plan after implementation

## Implementation

### Latest parse scheduler

`LatestParseScheduler` owns demand, not canonical state:

- immutable request: source, `SourceRevision`, location generation, operation generation;
- at most one running request;
- at most one pending request, always the newest;
- replacing pending demand completes the displaced request as discarded-before-parse;
- completion is delivered to `EditorSession` on the main actor;
- session identity checks remain the only application authority.

`MarkdownParser.parse` accepts an optional cancellation predicate/token. Inside `parseLock` it
must check cancellation before copying UTF-8 and again before cmark setup. cmark itself remains
synchronous and non-cooperative once entered.

### Encoded image inspection

1. Resolve and standardize the contained local URL under existing policy.
2. Open with no-follow semantics consistent with the existing containment rules.
3. `fstat` and require a regular file.
4. Reject `st_size > 256 * 1024 * 1024` with typed `encodedFileTooLarge`.
5. Read only sufficient metadata through ImageIO without eager caching.
6. Validate UTI and pixel dimensions.
7. Hash accepted bytes off-main, preferably streaming; do not retain the full encoded file merely
   to hash it.
8. Decode the bounded thumbnail.
9. Preserve original bytes/metadata and existing cache identity behavior.

The error must remain local and privacy-safe: no path or filename in diagnostics.

### Canonical asset references

Derive references during canonical parse/tree conversion:

- include Markdown image destinations represented by supported semantic image nodes;
- preserve the concrete destination spelling/range for containment and matching;
- exclude fenced/indented code and literal raw HTML unless formal GFM parses an actual image node;
- handle escapes, entities, parentheses, angle destinations, Unicode, and CRLF through the pinned
  parser/source index;
- expose an immutable `CanonicalAssetReferences` value on the authoritative result.

Every consumer moves to this value. No consumer reparses raw Markdown.

## Automated proof

### Scheduling

- Controlled parser gate with revisions 1…100:
  - revision 1 may run;
  - only revision 100 may enter after it;
  - 2…99 are discarded before source-copy/parser spy;
  - only matching latest result applies.
- Cancellation after lock acquisition prevents UTF-8 copy/cmark entry.
- Detach cancels running/pending scheduling and applies nothing.
- Multiple documents remain correct under the process-wide cmark lock.

### Image resources

- Sparse file at 256 MiB + 1 byte:
  - typed rejection;
  - zero full-read calls;
  - zero hash/decode calls.
- Exactly-at-limit accepted-format fixture follows metadata/hash/decode route.
- Non-regular, symlink, alias/package, corrupt, unsupported, and oversize-dimension fixtures retain
  existing refusal behavior.
- Accepted PNG/JPEG/GIF/HEIC/HEIF original bytes and metadata remain unchanged.
- Decoded cache never exceeds 64 MiB.

### References

- Official/focused GFM image fixtures produce exact destinations/ranges.
- Images inside fenced and indented code are excluded.
- Fence length, indentation, escapes, nested parentheses, titles, CRLF, and Unicode agree with the
  pinned parser.
- Reference warnings and rollback decisions use the canonical result.
- A structural deletion test rejects any new scanner/regex route.

## Instrumentation and performance

- Aggregate scheduler counts: requested, discarded-before-parse, parsed, stale-after-parse.
- `.parseProjection` excludes image work.
- `.imageResolution` includes inspection/hash/decode/cache.
- Typed oversized-image failure uses symbols/numbers only.
- Release parse p95 uses only requests that actually entered parse and records discarded counts
  separately.

## Failure and rollback

- Cancellation remains an optimization; identity checks remain mandatory.
- If streaming hashing changes digest output, the implementation is wrong—preserve SHA-256 bytes
  exactly.
- If cmark does not expose sufficient concrete destination information, extend the existing tree
  conversion/source index; do not retain the secondary scanner as a compatibility layer.
- No partial image cache entry is published after failure.

## Conformance and completion gates

- `rg "CanonicalAssetReferenceScanner"` returns no current code/test/doc result.
- File-operation spies prove limit-before-bulk-read ordering.
- Scheduler tests deterministically prove only running + latest enter parse.
- ARC-Q18/Q19 pass.
- Full Debug/Release tests, documentation/instrumentation gates, smoke, screenshot review,
  separate-agent review, PR triage, and stale-work cleanup pass.
- Reconcile REQ-081/085/111/112 only from proof; delete this plan.
