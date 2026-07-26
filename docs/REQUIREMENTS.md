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
| REQ-001 | The system shall read and write documents as UTF-8 plain-text Markdown files with a `.md` or `.markdown` extension (`net.daringfireball.markdown`). | INC-01 | Done | `MarkdownContentType` + `MarkdownDocument` (`readableTypes`/`writableTypes`) + `Info.plist` | test `markdownUTTypeIdentifier`, `readableWritableTypesAreMarkdown` |
| REQ-002 | WHEN the user chooses File ▸ New, the system shall create an empty untitled Markdown document. | INC-01 | Done | `MarkdownDocument.init` / `MarkdownDocumentData.init(text:)` | test `newDocumentIsEmpty` |
| REQ-003 | WHEN the user opens a `.md`/`.markdown` file, the system shall load its UTF-8 contents into an editor window. | INC-01 | Done | `MarkdownDocument.read(from:ofType:)` / `MarkdownDocumentData.init(data:)` | tests `roundTripsUTF8ContentUnchanged`, `readsEmptyFile`, `readAndDataRoundTripByteFixtures` |
| REQ-004 | IF a file is not valid UTF-8, THEN the system shall report a read error and shall not open a corrupted document. | INC-01 | Done | `MarkdownDocumentData.init(data:)` | test `invalidUTF8ThrowsReadError` |
| REQ-005 | WHEN the user edits a document, the system shall autosave changes without an explicit Save. | INC-01 | Done | `MarkdownDocument.autosavesInPlace` | inherent (framework-provided); test `autosavesInPlace` |
| REQ-006 | The system shall preserve macOS document Versions so the user can browse and revert. | INC-01 | Done | `NSDocument` Versions | inherent (framework-provided) |
| REQ-007 | The system shall save without altering bytes the user did not edit, preserving the file's existing line endings and encoding (INV-2). | INC-01 | Done | `MarkdownDocumentData.init(data:)` / `data()` | tests `roundTripsUTF8ContentUnchanged`, `preservesCRLFLineEndings`, `preservesUTF8BOM` |

### B · Editing (plain text)

| ID | Requirement (EARS) | Inc | Status | Implemented in | Verified by |
|----|--------------------|-----|--------|----------------|-------------|
| REQ-010 | The system shall provide plain-text editing of the document contents. | INC-01 | Done | `MarkdownTextView` (TextKit 1 `NSTextView`) | inherent (framework-provided) |
| REQ-011 | The system shall support unlimited undo and redo of edits. | INC-01 / COR-05 | Done | `HistoryPatch`, `MarkdownDocument.commitSourceMutation` / `applyHistoryPatch` | `SourceIntegrityCharacterizationTests` multi-step undo/redo |
| REQ-012 | The system shall integrate the macOS spell-checker. | INC-01 | Done | `MarkdownTextView` (`NSTextView`) | inherent (framework-provided) |

### C · Standard macOS behaviors

| ID | Requirement (EARS) | Inc | Status | Implemented in | Verified by |
|----|--------------------|-----|--------|----------------|-------------|
| REQ-020 | The system shall support document tabs (multiple documents in one window). | INC-01 | Done | `NSDocument` / `NSDocumentController` | inherent (framework-provided) |
| REQ-021 | The system shall list recently opened documents under File ▸ Open Recent. | INC-01 | Done | `NSDocumentController` | inherent (framework-provided) |
| REQ-022 | The system shall adopt the system Light/Dark appearance automatically. | INC-01 | Done | system appearance (no overrides) | inherent (framework-provided) |

### D · Non-functional

| ID | Requirement (EARS) | Inc | Status | Implemented in | Verified by |
|----|--------------------|-----|--------|----------------|-------------|
| REQ-030 | The system shall perform all editing offline, with no network access (INV-4). | INC-01 | Done | no networking APIs used | inherent (inspection) |
| REQ-031 | The system shall collect no telemetry and require no account. | INC-01 | Done | no analytics/account code | inherent (inspection) |
| REQ-032 | The system shall be operable via VoiceOver and full keyboard control (INV-6). | INC-01 / COR-07 | Correction | stock controls plus current custom rich attachments; replacement accessible task action per PLAN-0010 | framework behavior covers stock controls; custom task keyboard/accessibility action evidence missing |

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
| REQ-045 | WHILE editing a large document, the system shall keep typing latency imperceptible (highlighting debounced and computed off the main thread). | INC-02 | Done | `MarkdownTextView.Coordinator` (120 ms debounce, version gate; no document-size styling suspension) + `TextStatsComputer` (off-main, cancellation-aware scan) | test `computesCountsOffMainActor`; inherent (native insertion is the synchronous edit path; styling remains version-gated and cancellable for every document size) |
| REQ-046 | The system shall support standard find and replace within the document. | INC-02 | Done | `MarkdownTextView` (`usesFindBar`) | inherent (framework-provided) |

*Reconciled:* REQ-010/011/012 (plain-text editing, undo/redo, spell-check) re-pointed from
`TextEditor` to the TextKit 1 `NSTextView` wrapper (`MarkdownTextView`).

---

## COR-01 · Markdown dialect conformance correction — ✅ Done

This correction removed the conflicting house-extension claims before new image syntax is added.
The regex engine remains a lexical styling aid, not a conforming parser.
SPIKE-02 subsequently proved that the cross-version label was not one executable dialect. The
user approved coherent formal GFM 0.29 on 2026-07-25; REQ-047 is revised accordingly. COR-01's
existing lexical token set remains compatible and does not claim parser conformance.

| ID | Requirement (EARS) | Inc | Status | Implemented in | Verified by |
|----|--------------------|-----|--------|----------------|-------------|
| REQ-047 | The system shall present formal GFM 0.29-gfm, including its bundled CommonMark core and five formal extensions, as the only supported MVP source dialect. | COR-01 | Done | `TokenStyle`, `MarkdownHighlighter`, `MarkdownTheme` | test `supportedDialectContainsOnlyCommonMarkAndFormalGFMStyles`; full parser conformance belongs to REQ-054 |
| REQ-048 | WHEN source contains valid formal-GFM double-tilde strikethrough, the system shall apply the strikethrough source style without interpreting that syntax as subscript. | COR-03 | Done | `MarkdownHighlighter.strikethroughRanges` (double-tilde only) | table test `stylesFormalGFMTildeStrikethroughFixtures` |
| REQ-049 | WHEN source contains an unsupported writing extension or single-tilde span, the system shall preserve its text unchanged without presenting it as supported footnote, highlight, superscript, subscript, or strikethrough semantics. | COR-03 | Done | `MarkdownHighlighter` (no Tier-2 styles; single tilde unstyled) | tests `preservesUnknownExtensionsWithoutSemanticStyles`, `stylesFormalGFMTildeStrikethroughFixtures` |
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

## COR-04 · NSDocument migration — 🟠 Correction required

### B · Document ownership and lifecycle

| ID | Requirement (EARS) | Inc | Status | Implemented in | Verified by |
|----|--------------------|-----|--------|----------------|-------------|
| REQ-013 | The system shall use one `NSDocument` instance as the owner of canonical Markdown source, file location, source version, and undo history for each open document. | COR-04 | Done | `MarkdownDocument` | tests `documentOwnsUndoManager`, `exactUTF16ReplaceAdvancesVersion` |
| REQ-014 | The system shall retain standard macOS New, Open, Save, Save As, autosave-in-place, Versions, tabs, and Recents behavior after the document-model migration. | COR-04 | Done | `MarkdownDocumentController`, `Markdown_EditorApp`, `MarkdownDocument.makeWindowControllers` | inherent framework behavior; test `autosavesInPlace` |
| REQ-015 | WHEN reading or writing a document, the system shall preserve the existing UTF-8, empty-file, BOM, CRLF, Unicode, invalid-UTF-8, zero-edit byte-fidelity, and ordinary-file/no-metadata contract. | COR-04 | Done | `MarkdownDocumentData`, `MarkdownDocument.read`/`data(ofType:)` | tests in `MarkdownDocumentDataTests`, `readAndDataRoundTripByteFixtures` |
| REQ-016 | WHEN either editor adapter submits an expected source version and exact UTF-16 replacement, the document shall either advance its source version once and register document-owned undo/redo or return a typed stale/invalid/conflict refusal without mutation. | COR-04 / COR-05 | Done | `SourceMutation`, `HistoryPatch`, `MarkdownDocument.commitSourceMutation` | `SourceIntegrityCharacterizationTests`, existing document/COR-02 suites |
| REQ-017 | WHEN a dependent operation requires an untitled document to be saved, the document shall expose operation-scoped Save success, cancellation, or failure without discovering document ownership through a view. | COR-04 | Done | `MarkdownDocument.saveDocument`, `DocumentActionInterface` | tests `injectedSaveSuccessCancelFailure`, `saveGoesThroughInterfaceNotViewLookup` |
| REQ-018 | The system shall keep mutable document/AppKit state on the main actor and send only immutable `Sendable` source and byte snapshots to background work. | COR-04 / COR-05 | Done | `SourceSnapshot`, `DocumentIOText` (`Synchronization.Mutex`) | `concurrentBackgroundDataReadsCompleteImmutableSnapshot`; Swift 6 complete-concurrency build |
| REQ-019 | WHEN Save As, rename, or move changes the document URL, the document shall advance its location generation and notify COR-02 through an editor-neutral selection/Save/URL/source-commit interface without replacing COR-02 storage, exact-copy, or failure semantics. | COR-04 | Done | `MarkdownDocument.fileURL`, `DocumentActionInterface`, `ImagePlacementController` | tests `locationGenerationAdvancesOnURLChangeButNotUntitledSave`, `untitledSaveURLDoesNotBumpGenerationForActiveTransaction`, existing COR-02 suite |

## INC-04 · Source and WYSIWYG editing — 🟠 Correction required

### E · Dialect, projection, and commands

| ID | Requirement (EARS) | Inc | Status | Implemented in | Verified by |
|----|--------------------|-----|--------|----------------|-------------|
| REQ-052 | The system shall provide persistent editable Source and WYSIWYG modes over the same canonical source, make WYSIWYG the default, and expose a visible mode toggle that never changes source by itself. | INC-04 / COR-07 | Correction | current conditional `ContentView`; replacement `EditorHostController` per PLAN-0010 | current source-identity toggle test passes; persistent editor identity/state evidence missing |
| REQ-053 | WHILE Source mode is active, the system shall show and edit literal Markdown characters using the existing lexical styling path. | INC-04 | Done | `MarkdownTextView`, `MarkdownHighlighter` | existing Source highlighter/transaction tests |
| REQ-054 | WHILE WYSIWYG is active, the system shall parse the complete formal GFM 0.29 dialect through the pinned direct cmark-gfm configuration and render every supported semantic construct. | INC-04 / COR-06 | Correction | `MarkdownParser`; current projection replaced by `ProjectionCompiler` per PLAN-0010 | parser conformance passes; projection omits visible ordered/unordered list markers and lacks complete semantic evidence |
| REQ-055 | WHEN source is unsupported, malformed, or raw HTML, WYSIWYG shall show it literally as unformatted, non-executing, editable text and preserve it unchanged unless the user edits that text. | INC-04 / COR-06 | Correction | current `MarkdownProjectionModel`; replacement literal segments per PLAN-0010 | one fallback example passes; exact editable fallback mapping/oracle evidence missing |
| REQ-056 | WYSIWYG attributed storage shall omit parsed Markdown control characters rather than hiding or making them transparent, while retaining literal punctuation that is content. | INC-04 / COR-06 | Correction | current `MarkdownProjectionModel`, `RichTextBuilder`; replacement typed segments per PLAN-0010 | shallow delimiter test passes; proportional source mapping invalidates the complete claim |
| REQ-057 | WHEN a WYSIWYG or toolbar action changes Markdown, the system shall preserve existing source spelling where safely patchable and otherwise regenerate only the smallest semantic unit—inline node, block, or table—never the whole document. | INC-04 / COR-06 | Correction | current `SemanticEditEngine`; replacement syntax-family planners per PLAN-0010 | two spelling examples pass; nested/alternate-spelling/locality matrix missing |
| REQ-058 | The system shall provide the same formatting toolbar in both modes for paragraph/Heading 1–6, bold, italic, strikethrough, inline code, link, ordered/unordered/task list, block quote, and code block; unsafe or ambiguous commands shall be disabled or refused without changing source. | INC-04 / COR-06 | Correction | `EditorToolbar`; current `SemanticEditEngine` replaced by typed planners per PLAN-0010 | toolbar exists; complete command × mode × spelling × refusal matrix missing |
| REQ-059 | WHEN clipboard content offers rich and plain representations, the MVP shall paste its plain-text representation rather than infer Markdown formatting. | INC-04 | Done | `PastePolicy`, `MarkdownTextView`, `WYSIWYGTextView` | test `testPastePolicyPrefersPlainText` |

### F · Rich interaction, images, and tables

| ID | Requirement (EARS) | Inc | Status | Implemented in | Verified by |
|----|--------------------|-----|--------|----------------|-------------|
| REQ-078 | WHEN a supported task-list item is shown in WYSIWYG, its checkbox shall be directly operable and commit one task-marker source transaction. | INC-04 / COR-07 | Correction | current mouse hit-test; replacement accessible task action per PLAN-0010 | source marker test passes; mouse/keyboard/accessibility action equivalence missing |
| REQ-079 | WHEN a supported link is shown in WYSIWYG, it shall be directly clickable while its label remains editable through an explicit edit action. | INC-04 / COR-07 | Correction | current `WYSIWYGTextView`, opener, rich attributes; exact selection/edit integration per PLAN-0010 | all-scheme injected opener test passes; direct rich click plus exact label-edit component evidence missing |
| REQ-080 | WYSIWYG shall render and permit cell-content edits in existing GFM tables without offering table insertion or structural row/column controls in the MVP. | INC-04 / COR-06/07 | Correction | current table metadata; replacement exact table-cell planner/host per PLAN-0010 | absence of structural controls is inherent; exact rendered cell edit evidence missing |
| REQ-081 | WHEN a local PNG, JPEG, GIF, HEIC, or HEIF reference resolves, WYSIWYG shall decode a bounded display representation off-main without changing source, original bytes, metadata, or format and without fetching remote images. | INC-04 / COR-07 | Correction | current `LocalImageResolver`/cache; replacement direct `CGImage` pipeline per PLAN-0010 | PNG/JPEG/GIF/HEIC byte test passes; HEIF, detected-UTI, cache-cost/freshness evidence missing |
| REQ-082 | The system shall provide “Add Image…” in both modes through the existing COR-02 placement transaction and shall not introduce an Import command or a second image pipeline. | INC-04 / COR-07 | Correction | current global notification route; replacement `EditorActionRouter` per PLAN-0010 | route existence test passes; document-window isolation and exact WYSIWYG selection capture missing |
| REQ-083 | WHEN an edit, toolbar action, task toggle, link change, or image insertion is undone/redone after switching modes, the document-owned undo manager shall restore the canonical source while leaving asset files intact. | INC-04 / COR-05/07 | Done | `HistoryPatch`, `MarkdownDocument`, COR-02 asset tests; persistent host polish remains COR-07 | `undoRedoRestoresSourceSelectionsAcrossModeChanges`, multi-step history suite, existing COR-02 asset tests |
| REQ-084 | WYSIWYG shall preserve native TextKit selection, marked text/IME, spelling, Find, keyboard editing, plain-text paste, and meaningful accessibility roles, labels, values, and image descriptions. | INC-04 / COR-07 | Correction | current `WYSIWYGTextView`; replacement persistent host/input/accessibility per PLAN-0010 | plain paste passes; marked-text, persistent selection/Find, keyboard task, and accessibility evidence missing |
| REQ-085 | The system shall compute parser, source-index, projection-model, and image-decode work off-main and apply results only when their source/location version still matches. | INC-04 / COR-05/07 | Correction | current `EditorSession.scheduleParse`, `LocalImageResolver`; replacement strict-concurrency pipeline per PLAN-0010 | stale edit refusal passes; strict concurrency and executor/timing evidence missing |
| REQ-086 | WHEN the user switches modes, each persistent editor shall restore its own logical selection and scroll state without changing source. | INC-04 / COR-07 | Correction | current mode-local values without persistent views; replacement host per PLAN-0010 | source remains unchanged; persistent identity, selection/affinity, and scroll restoration missing |
| REQ-087 | IF parsing, mapping, semantic translation, local-image resolution, or asynchronous work fails, THEN the system shall keep Source mode available, leave canonical source unchanged, and expose a deterministic literal fallback or typed refusal rather than guessing. | INC-04 / COR-06/07 | Correction | current mapping/edit/image code; replacement typed segments/planners/decoder per PLAN-0010 | individual refusals pass; projection proportional mapping and selection clamping violate the no-guess contract |

## INC-04 correction program — ⚪ Approved / ready

### D/H · Concurrency, evidence, and performance

| ID | Requirement (EARS) | Inc | Status | Implemented in | Verified by |
|----|--------------------|-----|--------|----------------|-------------|
| REQ-088 | The system shall compile the application and non-UI test targets in Swift 6 language mode with complete concurrency checking and without unsafe mutable-state isolation opt-outs. | COR-05 | Done | project `SWIFT_VERSION=6` + `SWIFT_STRICT_CONCURRENCY=complete`; `DocumentIOText` | inherent (clean Swift 6 complete-concurrency build) |
| REQ-089 | The system shall provide privacy-safe mutation, projection, composition, asynchronous-work, and image-cache instrumentation sufficient to prove accepted/refused operations and timing without recording document content, selected content, URL strings, or complete local paths. | COR-05/06/07 | Partial | `EditorTrace` mutation/history/mode events (COR-05); projection/composition/image traces remain COR-06/07 | `editorTraceOmitsSourceSelectionAndPathStrings` |
| REQ-090 | WHILE operating on the approved performance corpus, the system shall satisfy p95 keystroke translation below 8 ms, p95 mode toggle below 16 ms, p95 off-main parse/index/projection below 100 ms at 100,000 UTF-16 units, zero stale-result applications, zero parser/image-decode work on the main actor, and a decoded-image cache no larger than 64 MiB. | COR-06/07 | Planned | — | reproducible optimized measurements in PLAN-0010 |

---

*Deferred:* in-fence language syntax coloring, dialect profiles, rich-to-Markdown paste conversion,
table creation/structural controls, image sizing syntax, transcoding, metadata stripping, remote
images, automatic asset cleanup, and asset-aware Save Copy.

*Next free IDs: REQ-008 (A), REQ-023 (C), REQ-033 (D), REQ-091 (F–H).*
