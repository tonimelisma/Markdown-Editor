# REQUIREMENTS

The single source of truth for **WHAT** the app does. Requirements are **populated per
increment** during the discovery phase (the *Specify* step of [CLAUDE.md §3](../CLAUDE.md)).

## Conventions

- **ID:** `REQ-###`, assigned sequentially, never reused.
- **EARS notation** — UPPER-CASE keywords: `WHEN` (event), `WHILE` (state), `IF…THEN`
  (unwanted), `WHERE` (optional); otherwise a ubiquitous "The system shall …". One "shall"
  per requirement.
- **Status:** `Planned` · `Active` · `Done` · `Correction` · `Deferred`. `Correction` means
  delivered behavior is known to conflict with an approved replacement and remains truthful
  until that replacement is built.
- **Traceability:** code carries `// REQ-###`, tests carry `// Verifies: REQ-###`
  ([CLAUDE.md §4](../CLAUDE.md)). Each row lists its code + verification anchors. `—` = not built.
- **Verification kinds (no manual or UI tests, ever):** `test` = automated unit/integration test
  that does not require UI automation · `inherent` = satisfied by construction — either a
  standard framework component provides the behavior (e.g. `DocumentGroup` gives autosave/tabs)
  or code inspection proves it (e.g. "makes no network calls"). Nothing is verified by hand.
- **Forward:** every requirement has ≥1 verification (a `test`, or a justified `inherent`).
  **Backward:** every `REQ-###` in code exists here. A `Done` row has its verification recorded.

---

## INC-01 · Editor foundation (plain text) — ✅ Done

### A · Documents & files

| ID | Requirement (EARS) | Inc | Status | Implemented in | Verified by |
|----|--------------------|-----|--------|----------------|-------------|
| REQ-001 | The system shall read and write documents as UTF-8 plain-text Markdown files with a `.md` or `.markdown` extension (`net.daringfireball.markdown`). | INC-01 | Done | `Markdown_EditorDocument` (`UTType.markdown`, `readable`/`writableContentTypes`) + `Info.plist` | test `readableAndWritableTypesAreMarkdown` |
| REQ-002 | WHEN the user chooses File ▸ New, the system shall create an empty untitled Markdown document. | INC-01 | Done | `Markdown_EditorDocument.init(text:)` | test `newDocumentIsEmpty` |
| REQ-003 | WHEN the user opens a `.md`/`.markdown` file, the system shall load its UTF-8 contents into an editor window. | INC-01 | Done | `Markdown_EditorDocument.init(data:)` / `init(configuration:)` | tests `roundTripsUTF8ContentUnchanged`, `readsEmptyFile` |
| REQ-004 | IF a file is not valid UTF-8, THEN the system shall report a read error and shall not open a corrupted document. | INC-01 | Done | `Markdown_EditorDocument.init(data:)` | test `invalidUTF8ThrowsReadError` |
| REQ-005 | WHEN the user edits a document, the system shall autosave changes without an explicit Save. | INC-01 | Done | `DocumentGroup` / `FileDocument` autosave | inherent (framework-provided) |
| REQ-006 | The system shall preserve macOS document Versions so the user can browse and revert. | INC-01 | Done | `FileDocument` Versions | inherent (framework-provided) |
| REQ-007 | The system shall save without altering bytes the user did not edit, preserving the file's existing line endings and encoding (INV-2). | INC-01 | Done | `Markdown_EditorDocument.init(data:)` / `data()` | tests `roundTripsUTF8ContentUnchanged`, `preservesCRLFLineEndings`, `preservesUTF8BOM` |

### B · Editing (plain text)

| ID | Requirement (EARS) | Inc | Status | Implemented in | Verified by |
|----|--------------------|-----|--------|----------------|-------------|
| REQ-010 | The system shall provide plain-text editing of the document contents. | INC-01 | Done | `MarkdownTextView` (TextKit 1 `NSTextView`) | inherent (framework-provided) |
| REQ-011 | The system shall support unlimited undo and redo of edits. | INC-01 | Done | `MarkdownTextView` (`allowsUndo`) | inherent (framework-provided) |
| REQ-012 | The system shall integrate the macOS spell-checker. | INC-01 | Done | `MarkdownTextView` (`NSTextView`) | inherent (framework-provided) |

### C · Standard macOS behaviors

| ID | Requirement (EARS) | Inc | Status | Implemented in | Verified by |
|----|--------------------|-----|--------|----------------|-------------|
| REQ-020 | The system shall support document tabs (multiple documents in one window). | INC-01 | Done | `DocumentGroup` | inherent (framework-provided) |
| REQ-021 | The system shall list recently opened documents under File ▸ Open Recent. | INC-01 | Done | `DocumentGroup` | inherent (framework-provided) |
| REQ-022 | The system shall adopt the system Light/Dark appearance automatically. | INC-01 | Done | system appearance (no overrides) | inherent (framework-provided) |

### D · Non-functional

| ID | Requirement (EARS) | Inc | Status | Implemented in | Verified by |
|----|--------------------|-----|--------|----------------|-------------|
| REQ-030 | The system shall perform all editing offline, with no network access (INV-4). | INC-01 | Done | no networking APIs used | inherent (inspection) |
| REQ-031 | The system shall collect no telemetry and require no account. | INC-01 | Done | no analytics/account code | inherent (inspection) |
| REQ-032 | The system shall be operable via VoiceOver and full keyboard control (INV-6). | INC-01 | Done | stock SwiftUI controls | inherent (framework-provided) |

---

## INC-02 · Markdown engine + live-styled source — ✅ Done

### E · Live-styled source

| ID | Requirement (EARS) | Inc | Status | Implemented in | Verified by |
|----|--------------------|-----|--------|----------------|-------------|
| REQ-040 | WHILE in the source editor, the system shall apply live syntax styling as the user types, using display attributes that never modify the file bytes (INV-2). | INC-02 | Done | `MarkdownTextView.Coordinator.apply` | tests `attributeStylingLeavesStringUnchanged`, `rangesWithinBounds` |
| REQ-041 | The system shall lexically style common Markdown/GFM source constructs: headings, bold, italic, inline code, fenced code blocks, links, images, ordered/unordered lists, task lists, blockquotes, tables, strikethrough, and thematic breaks. | INC-02 | Done | `MarkdownHighlighter` + `MarkdownTheme` | tests `stylesHeadingWithLevel`, `stylesInlineElements`, `stylesFencedCodeBlock`, `returnsAttributesPerStyle` |
| REQ-042 | The system shall style the previously selected light Tier-2 tokens: footnotes, `==highlight==`, superscript, and subscript. | INC-02 | Deferred | removed in COR-01 (`TokenStyle` no longer includes these cases); see REQ-047–REQ-049 | test `preservesUnknownExtensionsWithoutSemanticStyles` |
| REQ-043 | The system shall visually distinguish fenced code blocks (monospace + subtle tint). | INC-02 | Done | `MarkdownHighlighter` + `MarkdownTheme` | test `stylesFencedCodeBlock` |
| REQ-044 | The system shall display a live word and character count for the document. | INC-02 | Done | `TextStats`, `TextStatsComputer`, `ContentView` | tests `countsWordsAndCharacters`, `computesCountsOffMainActor` |
| REQ-045 | WHILE editing a large document, the system shall keep typing latency imperceptible (highlighting debounced and computed off the main thread). | INC-02 | Done | `MarkdownTextView.Coordinator` (120 ms debounce, version gate, 100,000 UTF-16-unit styling cap) + `TextStatsComputer` (off-main, cancellation-aware scan) | test `computesCountsOffMainActor`; inherent (native insertion is the synchronous edit path; over-cap styling is suspended) |
| REQ-046 | The system shall support standard find and replace within the document. | INC-02 | Done | `MarkdownTextView` (`usesFindBar`) | inherent (framework-provided) |

*Reconciled:* REQ-010/011/012 (plain-text editing, undo/redo, spell-check) re-pointed from
`TextEditor` to the TextKit 1 `NSTextView` wrapper (`MarkdownTextView`).

---

## COR-01 · Markdown dialect conformance correction — ✅ Done

This correction removed the conflicting house-extension claims before new image syntax is added.
The regex engine remains a lexical styling aid, not a conforming parser.

| ID | Requirement (EARS) | Inc | Status | Implemented in | Verified by |
|----|--------------------|-----|--------|----------------|-------------|
| REQ-047 | The system shall present CommonMark 0.31.2 plus formal GFM 0.29-gfm as the only supported MVP source dialect. | COR-01 | Done | `TokenStyle`, `MarkdownHighlighter`, `MarkdownTheme` | test `supportedDialectContainsOnlyCommonMarkAndFormalGFMStyles` |
| REQ-048 | WHEN source contains a valid formal-GFM strikethrough delimiter using one or two tildes, the system shall apply the strikethrough source style without interpreting that syntax as subscript. | COR-01 | Done | `MarkdownHighlighter` (single- and double-tilde strikethrough rules) | table test `stylesFormalGFMTildeStrikethroughFixtures` |
| REQ-049 | WHEN source contains an unsupported writing extension, the system shall preserve its text unchanged without presenting it as supported footnote, highlight, superscript, or subscript semantics. | COR-01 | Done | `MarkdownHighlighter` + removed Tier-2 `TokenStyle` cases | test `preservesUnknownExtensionsWithoutSemanticStyles` |
| REQ-050 | WHEN source contains a focused valid CommonMark image destination fixture, the system shall style its source range without changing the source text. | COR-01 | Done | `MarkdownHighlighter` (image destination pattern) | table test `stylesCommonMarkImageDestinationFixtures` |
| REQ-051 | WHILE applying lexical styling, the system shall keep every attributed range within the source bounds and leave the source string unchanged. | COR-01 | Done | `MarkdownHighlighter.tokens(for:)`, `MarkdownTextView.Coordinator.apply` | tests `attributeStylingLeavesStringUnchanged`, `rangesWithinBounds` |

## INC-03 · Paste and drop images — ✅ Done (via COR-02)

“Add image” means paste or drag-and-drop into the source editor. There is no Import document
command. User-visible policy:
[PLAN-0003](plans/0003-inc03-image-assets.md) / [ADR-0011](decisions/0011-image-placement-and-portability.md).
Corrected implementation:
[PLAN-0005](plans/0005-cor02-image-placement-transaction-rewrite.md) /
[ADR-0012](decisions/0012-transactional-descriptor-relative-image-placement.md).

### F · Input and representations

| ID | Requirement (EARS) | Inc | Status | Implemented in | Verified by |
|----|--------------------|-----|--------|----------------|-------------|
| REQ-060 | WHEN the user pastes or drops a supported image into a saved document, the system shall add it at the current source selection. | COR-02 | Done | `ImagePlacementController`, `MarkdownSourceTextView` | tests `rejectsSimultaneousBegin`, `reachesCommittedTerminal`, `collectsExactCountAndResumesOnce` |
| REQ-061 | WHEN a regular file is detected as PNG, JPEG, GIF, HEIC, or HEIF, the system shall copy its bytes unchanged without transcoding it. | COR-02 | Done | `ImageBatchPreflight`, `AssetDirectoryStore`, `POSIXFileOps.streamCopyAndHash` | tests `copiesSupportedFileRepresentationsByteForByte`, `copiesJPEGAndGIFByteForByte`, `stagesRegularPNGAndRejectsCorrupt` |
| REQ-062 | WHEN a pasteboard item provides bitmap data but no supported file or file promise, the system shall encode the bitmap as PNG. | INC-03 | Done | `ImagePasteboardClassifier`, `ImageBatchPreflight`, `ImageAssetPolicy.encodePNG` | test `mixedTextAndImageFallsThroughToTextPaste`; inherent PNG encode path in preflight |
| REQ-063 | IF an item is corrupt, its detected representation is unsupported, or its claimed extension disagrees with an unsafe/unsupported representation, THEN the system shall reject the entire user action with a clear error. | COR-02 | Done | `ImageBatchPreflight`, `FilePromiseCallbackCollector` | tests `stagesRegularPNGAndRejectsCorrupt`, `rejectsProviderError` |
| REQ-064 | WHEN paste or drag content contains meaningful non-image text, the system shall preserve native plain-text paste or drag behavior rather than consume it as an image action. | INC-03 | Done | `ImagePasteboardClassifier.classifyPasteboard` | test `mixedTextAndImageFallsThroughToTextPaste` |

### G · Placement, naming, and source

| ID | Requirement (EARS) | Inc | Status | Implemented in | Verified by |
|----|--------------------|-----|--------|----------------|-------------|
| REQ-065 | WHEN adding an image, the system shall use a visible sibling `assets/` directory as a shared non-owned destination, creating it only when needed. | COR-02 | Done | `AssetDirectoryStore` | tests `copiesSupportedFileRepresentationsByteForByte`, `rejectsSymlinkedAssetsDirectory` |
| REQ-066 | The system shall generate a lowercase ASCII filename that is safe across common macOS, Linux, and Windows filesystems and uses the detected representation’s canonical extension. | INC-03 | Done | `ImageAssetPolicy.slug` | table test `generatesPortableAssetNames` |
| REQ-067 | WHEN a destination filename already exists, the system shall reuse it only for byte-identical content and otherwise select a deterministic SHA-256-suffixed non-overwriting name using case-insensitive collision checks. | COR-02 | Done | `AssetDirectoryStore.chooseAndPublish`, `ImageAssetPolicy.chooseFilename` | tests `reusesIdenticalAssetOnDisk`, `hashSuffixesDifferentCollision`, `reusesIdenticalAsset` |
| REQ-068 | WHEN placement succeeds, the system shall insert standard relative Markdown `![](assets/name.ext)` without a title, dimensions, HTML, base64, percent-encoded filename, or private metadata. | INC-03 | Done | `ImageAssetPolicy.markdownReference` | test `generatesPortableCommonMarkImageReferences` |
| REQ-069 | WHEN one action contains multiple images, the system shall preserve provider order and insert their references separated by one line break as one undoable source replacement. | COR-02 | Done | `ImagePlacementController`, `MarkdownSourceTextView.insertImageMarkdown` | tests `rejectsSimultaneousBegin`, `commitsOrderedBatchAsOneUndoableReplacement` |

### H · Transaction, lifecycle, safety, and accessibility

| ID | Requirement (EARS) | Inc | Status | Implemented in | Verified by |
|----|--------------------|-----|--------|----------------|-------------|
| REQ-070 | WHEN adding one or more images, the system shall insert no source reference until every required destination file exists at its final contained path. | COR-02 | Done | `ImagePlacementController.runPlacement`, `ImageBatchPreflight` | tests `copiesSupportedFileRepresentationsByteForByte`, `stagesRegularPNGAndRejectsCorrupt` |
| REQ-071 | IF placement fails before source insertion, THEN the system shall remove only temporary and newly-created files proven to belong exclusively to that action, leaving all source, reused, and pre-existing files untouched. | COR-02 | Done | `AssetDirectoryStore.rollback`, identity pins | test `rollbackRemovesOnlyPinnedCreatedFiles` |
| REQ-072 | IF asynchronous placement overlaps a subsequent edit at the tracked insertion range, THEN the system shall cancel source insertion rather than guess a new location. | COR-02 | Done | `InsertionRangeTracker` | table test `boundaryTable` |
| REQ-073 | WHEN inserting one image reference, the system shall use an empty image description and select it for immediate authoring without inventing alternative text from the filename. | INC-03 | Done | `MarkdownSourceTextView.insertImageMarkdown` | test `selectsEmptyDescriptionForSingleImage`; inherent (`setAccessibilityLabel` on source view) |
| REQ-074 | WHEN image-reference insertion is undone or a reference is deleted, the system shall leave every asset file in place. | COR-02 | Done | `MarkdownSourceTextView.insertImageMarkdown` (text-only undo) | test `sourceUndoRetainsPlacedAssets` |
| REQ-075 | WHEN an untitled document receives an image action, the system shall complete the normal Save flow before creating `assets/`, canceling the action if Save is canceled. | COR-02 | Done | `DocumentSaveBridge`, `ImagePlacementController.beginUntitledSave` | test `untitledCancelLeavesIdle`; inherent RESEARCH-0006 Save bridge |
| REQ-076 | WHEN Save As, rename, or move changes the document parent and a canonical local `assets/…` image reference (app-generated or manually authored) that resolved under the previous parent no longer resolves under the new parent, the system shall warn without silently copying, moving, or deleting companion files. | COR-02 | Done | `CanonicalAssetReferenceScanner`, `ImagePlacementController.updateDocumentURL` | tests `findsCanonicalReferencesAndExcludesCode`, `detectsBrokenAfterParentChangeIncludingManual` |
| REQ-077 | The system shall perform image inspection, hashing, promise receipt, and file I/O off the main actor while rejecting symlinks, aliases, packages, non-regular sources, symlinked destinations, and paths outside the resolved sibling `assets/` directory. | COR-02 | Done | `ImageIOExecutor`, `POSIXFileOps`, `AssetDirectoryStore`, `ImageBatchPreflight` | tests `workRunsOffMainQueue`, `rejectsSymlinkSource`, `rejectsSymlinkedAssetsDirectory` |

---

*Deferred:* WYSIWYG (INC-04), in-fence language syntax coloring, dialect profiles, image sizing,
transcoding, metadata stripping, remote images, automatic asset cleanup, and asset-aware Save Copy.

*Next free IDs: REQ-008 (A), REQ-013 (B), REQ-023 (C), REQ-033 (D), REQ-052 (E), REQ-078 (F–H).*
