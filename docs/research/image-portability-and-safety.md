# Image portability and safety evidence

- **Authority:** Evidence only; `../VISION.md`, `../ENGINEERING.md`, and requirements are
  authoritative.
- **First researched:** 2026-07-22
- **Last verified:** 2026-07-25
- **Refresh when:** supported formats, asset layout, sandboxing, filesystem primitives, paste/drag
  APIs, or Save behavior changes

## Questions

- How should ordinary Markdown reference local images with minimum lock-in?
- How can paste, drag/drop, and Add Image share one safe transaction?
- How are PNG, JPEG, GIF, HEIC, and HEIF preserved and displayed?

## Compatibility findings

CommonMark image syntax accepts an ordinary relative destination. A visible sibling `assets/`
directory is broadly understandable and does not imply application ownership. The application
therefore writes standard references such as `![](assets/photo.heic)` without HTML, dimensions,
base64, titles, or hidden metadata.

HEIC/HEIF is standard on Apple platforms but less portable across renderers. That compatibility
fact does not justify destructive conversion. File-backed PNG, JPEG, GIF, HEIC, and HEIF retain
their exact bytes. Bitmap-only paste has no original file representation and is encoded as PNG.

Sources:

- [CommonMark images](https://spec.commonmark.org/0.31.2/#images)
- [Apple HEIF/HEVC media](https://support.apple.com/116944)
- [W3C image alternative text guidance](https://www.w3.org/WAI/curricula/content-author-modules/images/)

## Native input findings

AppKit paste and drag callbacks should only classify stable values, capture immutable intent, and
start the transaction. File reads, representation inspection, hashing, PNG encoding, promise
receipt, and destination I/O remain off-main.

`NSFilePromiseReceiver` can represent multiple callback results. A correct bridge invokes each
receiver once, records expected names, collects every callback on the supplied queue, resumes once,
and cleans its private staging directory on all terminal paths.

Sources:

- [Apple `NSFilePromiseReceiver`](https://developer.apple.com/documentation/appkit/nsfilepromisereceiver)
- [Apple promised-file receipt](https://developer.apple.com/documentation/appkit/nsfilepromisereceiver/receivepromisedfiles(atdestination:options:operationqueue:reader:))
- [Apple `NSPasteboardItem`](https://developer.apple.com/documentation/appkit/nspasteboarditem)

## Filesystem findings

Path validation followed by a later path mutation leaves a time-of-check/time-of-use race.
Descriptor-relative Darwin operations provide the correctness boundary:

- open trusted directories without following links and resolve beneath them;
- use `fstat` to establish regular-file identity;
- stage while streaming SHA-256;
- publish without replacement using an exclusive primitive;
- retry collisions against actual directory entries; and
- unlink rollback entries only when device/inode identity still matches.

`NSFileCoordinator` coordinates cooperating processes but is not an exclusive-create primitive.
Case-insensitive collision comparison is required for portable names even on case-sensitive
volumes.

Primary local references were macOS manual pages for `openat`, `renameatx_np`, `linkat`,
`copyfile`, and `fstat`; Foundation coordination:
[Apple `NSFileCoordinator`](https://developer.apple.com/documentation/foundation/nsfilecoordinator).

## Transaction findings

The safe transaction is:

1. capture immutable source-domain selection and document/location generation;
2. complete operation-scoped Save for an untitled document;
3. receive, inspect, hash, and stage the entire ordered batch;
4. reject the whole action for unsupported or corrupt input;
5. select deterministic portable names using actual directory entries and content identity;
6. publish every destination inside the sibling `assets/` directory without replacement;
7. commit one ordered Markdown mutation; and
8. roll back only identity-pinned files owned exclusively by the action.

Move warnings are source-derived from canonical `assets/<portable-name>.<format>` references.
They require no hidden provenance and survive reopening.

## Decode evidence

Read-only `CGImageSource` probes decoded generated PNG/JPEG/GIF/HEIC plus public HEIC and two HEIF
variants while source hashes remained unchanged:

| Fixture | Result |
| --- | --- |
| generated PNG/JPEG/GIF | decoded; bytes unchanged |
| generated `public.heic` | decoded; bytes unchanged |
| public 1280×854 HEIC | decoded; bytes unchanged |
| public HEVC-in-HEIF | decoded; bytes unchanged |
| public JPEG-in-HEIF | decoded; bytes unchanged |

No image-destination, intermediate JPEG/PNG, transcoding, or metadata rewrite path is required.
`CGImage` provides an immutable display value that can cross from off-main decode to the main
actor. Cache cost must remain bounded by decoded bytes and file-content identity.

Sources:

- [Apple `CGImageSource`](https://developer.apple.com/documentation/imageio/cgimagesource)
- [Apple system UTTypes](https://developer.apple.com/documentation/uniformtypeidentifiers/system-declared-uniform-type-identifiers)
- [Pinned libheif fixtures](https://github.com/strukturag/libheif/tree/1a3583bcce77de6d3f8701c0758e3954863681ba/examples)

## Durable conclusions

- Preserve file-backed HEIC/HEIF exactly; never generate JPEG from it.
- Use one transaction for paste, drag/drop, and Add Image; there is no Import command.
- Treat `assets/` as shared external storage, not an app-owned database.
- Containment, exclusive publication, and identity-pinned rollback are mechanical invariants.
