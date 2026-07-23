# RESEARCH-0004 — Markdown compatibility and local image placement

- **Date:** 2026-07-22
- **For:** COR-01 and INC-03
- **Type:** standards, ecosystem, native API, filesystem, security, and accessibility research
- **Status:** Complete; recommendations approved 2026-07-22

## Questions

1. What can this app truthfully call standard Markdown or GFM?
2. How should paste and drag-and-drop add local images with minimal friction?
3. Which image formats, paths, naming, collision, undo, Save As, and failure policies maximize
   compatibility without changing or losing user data?
4. What objective gates should reject an unsafe design before convenience is considered?

## Executive finding

The previous design mixed formal GFM with a product-specific group of writing extensions and
called the result a dialect without a single conformance target. Its `~text~` subscript rule
directly conflicts with formal GFM, where one or two tildes delimit strikethrough. The most
compatible MVP contract is CommonMark 0.31.2 plus formal GFM 0.29-gfm, with unfamiliar syntax
preserved and later extensions introduced only as named profiles.

For images, no standard assigns an attachment folder to a loose Markdown file. The lowest-fuss
interoperable design is a visible shared `assets/` sibling directory and ordinary relative
image destinations. File-backed PNG, JPEG, GIF, HEIC, and HEIF are copied exactly; bitmap-only
clipboard content is encoded as PNG. Standard Markdown syntax is portable, but HEIC/HEIF display
support is not universal, and the product must state that distinction honestly.

## 1. Standards boundary

### CommonMark

CommonMark image syntax has the same destination and optional-title grammar as links. A normal
destination cannot contain an unescaped space, and parentheses must be escaped or balanced;
angle-bracket destinations admit spaces. The image description is used as alternative text by
HTML renderers.

Generating only lowercase ASCII filenames under the literal `assets/` path avoids spaces,
Unicode normalization differences, percent-encoding ambiguity, and complicated destination
escaping:

```markdown
![](assets/field-notes.heic)
```

This syntax is standard. Whether a renderer can decode the referenced file is a separate media
capability.

### Formal GFM versus github.com

The published GFM spec adds autolinks, tables, task-list items, and strikethrough to CommonMark.
Its strikethrough extension recognizes one or two tildes. Footnotes and emoji rendering available
on github.com are not thereby part of formal GFM.

Consequently, a source highlighter cannot use `~text~` for subscript while also claiming formal
GFM. Regex styling is lexical and approximate; conformance belongs to generated source and a
structural parser, not to colored ranges.

### Why not a custom composite

RFC 7763 describes Markdown variants as an interoperability problem and provides a mechanism to
identify them. Pandoc demonstrates that footnotes, definition lists, superscript, subscript,
smart typography, mark, and heading attributes can form a coherent extended dialect—but adding
selected Pandoc-like features to GFM without naming and testing the composite creates a house
dialect.

The approved MVP therefore uses the named standards only. Later dialect profiles may be
evaluated against explicit use cases, collision rules, parser support, round-trip behavior, and
fallback rendering.

## 2. Asset-directory options

There is no CommonMark, GFM, macOS, or filesystem standard for companion images. Editor
precedents make the destination configurable:

- VS Code can place pasted/dropped files using `markdown.copyFiles.destination`, including
  patterns such as `images/${documentBaseName}/`.
- Typora supports copy-to-folder settings and recommends relative paths.
- Obsidian allows a configured attachment location and Markdown-style links.
- Zettlr can put copied images into an `assets` directory relative to the Markdown file.

| Option | Compatibility | Lifecycle clarity | Friction | Decision |
|---|---:|---:|---:|---|
| Shared sibling `assets/` | High | Honest shared ownership | Lowest | **Selected** |
| `<document-stem>.assets/` | High | Looks owned, but rename makes name stale | Low | Rejected |
| Directory bundle with `index.md` | Medium | Resources move together | Medium | Rejected |
| macOS document package | Low outside app | Atomic | Low in app | Rejected |
| Absolute references | Low | No copied lifecycle | Low | Rejected |
| Base64 in Markdown | Low/readability poor | Self-contained | Low | Rejected |

`assets/` is an **image-placement destination**, not a managed store. The app may create or reuse
it but cannot infer ownership of anything within it.

## 3. Image-format policy

Apple has supported HEIF/HEIC since macOS High Sierra and uses high-efficiency capture on iPhone,
iPad, and supported Mac screenshot workflows. Apple also describes JPEG as more broadly
compatible. Converting HEIC/HEIF could discard or alter HDR, depth, auxiliary images, animation,
orientation handling, color, metadata, or quality. The approved choice prioritizes source
fidelity: accept and copy HEIC/HEIF without conversion, while documenting that some Markdown
renderers will not display them.

| Input representation | INC-03 result | Reason |
|---|---|---|
| File PNG | exact copy | Broad rendering support |
| File JPEG | exact copy | Broad rendering support |
| File GIF | exact copy | Preserve animation and bytes |
| File HEIC/HEIF | exact copy; never transcode | First-class Mac input and source fidelity |
| Bitmap-only clipboard | encode PNG | No original file bytes exist |
| TIFF, WebP, BMP, RAW, PSD, PDF, SVG | reject with clear error | Conversion semantics and security need separate decisions |

The implementation must identify the actual container with Image I/O rather than trusting a
filename extension or pasteboard declaration. “Exact copy” preserves all source bytes—including
metadata that may contain location or device information. The app must not claim that copying
sanitizes metadata.

## 4. Filename and collision policy

Provider filenames are untrusted and often nonportable. Windows disallows reserved characters,
device names such as `CON` and `NUL`, and trailing spaces or periods. Apple filesystems may be
case-sensitive or case-insensitive and preserve case and Unicode normalization differently.

Approved algorithm:

1. Detect the actual supported representation and choose its canonical extension. Preserve the
   `.heic`/`.heif` distinction when detection supplies it.
2. Normalize the source stem to lowercase ASCII: keep `a-z` and `0-9`; replace every other run
   with `-`; trim hyphens; cap the stem length; use `image` if empty.
3. Avoid Windows device names and names ending in a dot or space.
4. Resolve candidate collisions case-insensitively.
5. If a regular existing candidate has identical bytes, reuse it.
6. Otherwise append the first 12 hexadecimal characters of the source SHA-256 before the
   extension. Extend the digest deterministically if that candidate also conflicts.
7. Never overwrite, percent-encode, or use a numeric “whatever is free now” suffix.

Hash-on-collision keeps ordinary names readable while making repeated placement deterministic
and concurrent races resolvable. File creation still uses exclusive/non-overwriting semantics;
the preflight check is not the write lock.

## 5. Native input model

### Saved document location

`FileDocumentConfiguration.fileURL` supplies the current URL and changes when the document is
saved or moved. An untitled document has no safe sibling destination. The app therefore asks the
user to save first and resumes the pending image action only after a real document URL exists.
Canceling Save cancels image placement.

### Paste classification

Pasteboards can advertise the same logical content in several representations. Items must be
inspected promptly because an `NSPasteboardItem` can become stale after pasteboard ownership
changes.

Approved precedence:

1. A supported regular image file URL → add the file.
2. A supported image file promise → receive then add.
3. Bitmap data with no file representation → encode PNG.
4. Mixed meaningful text/rich text plus image → preserve ordinary plain-text paste.
5. Image plus only a URL representation → treat as the image.

An explicit future “Paste Image” action may override an ambiguous payload. INC-03 does not add
an “Import” command.

### Drag-and-drop and promises

`NSTextView` exposes accepted drag types and drag-destination hooks. The wrapper intercepts only
supported image URLs and `NSFilePromiseReceiver` objects; every other drag continues through
native text-view behavior. File promises can be asynchronous and multi-file, so they are first
received into a private temporary staging directory. Provider order is retained.

### Coordinated I/O

`NSFileCoordinator` is appropriate for writes involving file providers. Image validation,
hashing, copy, and promise receipt run off the main actor. UI and text-storage mutations return
to the main actor. The design does not decode a full image merely to copy it.

## 6. Transaction and failure model

One paste or drop is one placement transaction:

1. Snapshot the ordered representations and source selection.
2. If needed, complete Save and obtain the current document URL.
3. Receive promises in private temporary storage.
4. Validate every item and reject the entire action if any item is unsupported or unsafe.
5. Resolve the real sibling `assets/`, reject symlinks/aliases/packages, and verify containment.
6. Choose deterministic names, reuse byte-identical regular files, and create other destinations
   without overwriting.
7. Revalidate the tracked insertion range. If document edits overlapped it, cancel instead of
   guessing where the references belong.
8. Only after all destinations exist, replace the tracked source selection once, preserving item
   order and separating multiple references with one line break.
9. Register that replacement as one undo operation.

Before reference insertion, failure cleanup may remove only temporary files and new destinations
proven to belong to that transaction. It never removes reused or pre-existing files. After
insertion, undo changes source only. The deliberately chosen worst case is an unreferenced copied
file, never a new dangling reference or lost source.

## 7. Accessibility and alternative text

W3C guidance distinguishes informative images, which need contextual alternative text, from
decorative images, which need an empty alternative. A filename is rarely meaningful alt text.
The app therefore emits `![](...)`; for one image it selects the empty description so the author
can immediately type it. Multiple images retain visible empty descriptions without interrupting
the transaction with repeated prompts.

## 8. Save As, rename, and move

A loose Markdown file and `assets/` directory are not atomic. Silently copying a shared
directory on Save As risks copying unrelated files; silently moving it risks breaking other
documents. The app performs ordinary document Save As only.

If the document’s parent changes and relative `assets/…` references generated by the app no
longer resolve, show a non-destructive warning. A future explicit **Save a Copy with Assets**
workflow may copy only referenced files after its ownership, collision, and rollback semantics
are approved.

## 9. Evaluation framework

### Hard gates

A candidate fails if it cannot prove:

- unchanged Markdown outside the explicit insertion;
- valid generated CommonMark/GFM source;
- no hidden state or proprietary source;
- deterministic case-insensitive collision behavior;
- no overwrite, mutation, movement, or deletion of sources or pre-existing files;
- no reference before successful storage;
- safe containment under hostile names and symlinks;
- accessible alternative-text behavior; and
- automated verification of success, failure, and concurrency seams.

### Comparative criteria

Passing candidates are ranked by cross-tool/filesystem compatibility, predictable lifecycle,
number of prompts/settings, implementation and maintenance cost, source readability, privacy
consequences, performance, and extensibility.

## 10. Verification implications

The build requires automated coverage for:

- portable slugs, reserved names, empty/long stems, Unicode, extensions, and case collisions;
- byte-identical reuse, different-byte hash suffixes, digest-prefix conflicts, and write races;
- exact-copy proof for every file-backed supported type;
- actual-type/extension mismatch and every unsupported type;
- CommonMark-safe generated references;
- paste precedence and mixed rich-text behavior;
- file URLs, promises, multiple-item order, and temporary cleanup;
- tracked-selection translation and overlapping-edit cancellation;
- existing/symlinked/unwritable `assets/`, permissions, disk-full, and partial-copy failures;
- no reference before all files exist;
- one source undo with assets retained;
- untitled Save success and cancellation;
- parent-directory change warning;
- unrelated document-byte preservation; and
- actor isolation and off-main I/O.

## Sources

### Markdown specifications and implementations

- [CommonMark 0.31.2: links](https://spec.commonmark.org/0.31.2/#links) and
  [images](https://spec.commonmark.org/0.31.2/#images)
- [GitHub Flavored Markdown 0.29: strikethrough](https://github.github.com/gfm/#strikethrough-extension-)
- [RFC 7763: Markdown variants](https://www.rfc-editor.org/rfc/rfc7763.html#section-2)
- [CommonMark executable specification tests](https://github.com/commonmark/commonmark-spec)
- [cmark-gfm](https://github.com/github/cmark-gfm)
- [Swift Markdown](https://github.com/swiftlang/swift-markdown)
- [Pandoc manual](https://pandoc.org/MANUAL.html)

### Editor precedents

- [Visual Studio Code: inserting images and links](https://code.visualstudio.com/docs/languages/markdown#_inserting-images-and-links-to-files)
- [Typora image handling](https://support.typora.io/Images/)
- [Obsidian attachment settings](https://obsidian.md/help/settings)
- [Zettlr assets setting](https://docs.zettlr.com/en/reference/settings/)

### Apple APIs and formats

- [Apple: using HEIF or HEVC media](https://support.apple.com/116944)
- [Apple: `DocumentGroup`](https://developer.apple.com/documentation/swiftui/documentgroup/)
- [Apple: `NSFilePromiseReceiver`](https://developer.apple.com/documentation/appkit/nsfilepromisereceiver)
- [Apple: `NSPasteboardItem`](https://developer.apple.com/documentation/appkit/nspasteboarditem)
- [Apple: `NSTextView`](https://developer.apple.com/documentation/appkit/nstextview)
- [Apple: `NSFileCoordinator`](https://developer.apple.com/documentation/foundation/nsfilecoordinator)
- [Apple: `CGImageSource`](https://developer.apple.com/documentation/imageio/cgimagesource)
- [Apple: `UTType.image`](https://developer.apple.com/documentation/uniformtypeidentifiers/uttype/image)

### Filesystems and accessibility

- [Microsoft: naming files, paths, and namespaces](https://learn.microsoft.com/en-us/windows/win32/fileio/naming-a-file)
- [Apple: files and directories](https://developer.apple.com/documentation/technologyoverviews/files-and-directories)
- [W3C: images and alternative text](https://www.w3.org/WAI/curricula/content-author-modules/images/)
