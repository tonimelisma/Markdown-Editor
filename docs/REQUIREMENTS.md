# REQUIREMENTS

The authoritative current behavior contract: what the app does, what is under correction, and
how delivered behavior is verified. Current architecture is in
[ENGINEERING.md](ENGINEERING.md).

## Conventions

- **ID:** `REQ-###`, assigned sequentially, never reused.
- **EARS notation** — UPPER-CASE keywords: `WHEN` (event), `WHILE` (state), `IF…THEN`
  (unwanted), `WHERE` (optional); otherwise a ubiquitous "The system shall …". One "shall"
  per requirement.
- **Status:** `Planned` · `Active` · `Done` · `Correction` · `Deferred`. `Correction` means the
  current implementation is known not to satisfy the current requirement completely.
- **Traceability:** each row names current production types/routes and verification. Local
  `// REQ-###` and `// Verifies: REQ-###` comments provide useful cross-references where present;
  every such comment must resolve to a row. `—` means not built.
- **Verification kinds (no manual or UI tests, ever):** `test` = automated unit/integration test
  that does not require UI automation · `inherent` = satisfied by construction — either a
  standard framework component provides the behavior (e.g. `NSDocument` provides Versions)
  or code inspection proves it (e.g. "makes no network calls"). Nothing is verified by hand.
- **Forward:** every `Done` requirement records at least one automated test or justified
  construction/framework proof. **Backward:** every `REQ-###` appearing in code/tests exists here.

---

## Documents and native editing

### A · Documents & files

| ID | Requirement (EARS) | Inc | Status | Implemented in | Verified by |
|----|--------------------|-----|--------|----------------|-------------|
| REQ-001 | The system shall read and write documents as UTF-8 plain-text Markdown files with a `.md` or `.markdown` extension (`net.daringfireball.markdown`). | INC-01 | Done | `MarkdownContentType` + `MarkdownDocument` (`readableTypes`/`writableTypes`) + `Info.plist` | test `markdownUTTypeIdentifier`, `readableWritableTypesAreMarkdown` |
| REQ-002 | WHEN the user chooses File ▸ New, the system shall create an empty untitled Markdown document. | INC-01 | Done | `MarkdownDocument.init` / `MarkdownDocumentData.init(text:)` | test `newDocumentIsEmpty` |
| REQ-003 | WHEN the user opens a `.md`/`.markdown` file, the system shall load its UTF-8 contents into an editor window. | INC-01 | Done | `MarkdownDocument.read(from:ofType:)` / `MarkdownDocumentData.init(data:)` | tests `roundTripsUTF8ContentUnchanged`, `readsEmptyFile`, `readAndDataRoundTripByteFixtures` |
| REQ-004 | IF a file is not valid UTF-8, THEN the system shall report a read error and shall not open a corrupted document. | INC-01 | Done | `MarkdownDocumentData.init(data:)` | test `invalidUTF8ThrowsReadError` |
| REQ-005 | WHEN the user edits a document, the system shall autosave changes without an explicit Save. | INC-01 | Done | `MarkdownDocument.autosavesInPlace` | inherent (framework-provided); test `autosavesInPlace` |
| REQ-006 | The system shall preserve macOS document Versions so the user can browse and revert. | INC-01 | Done | `NSDocument` Versions | inherent (framework-provided) |
| REQ-007 | The system shall save without altering bytes the user did not edit, preserving the file's existing line endings and encoding. | INC-01 | Done | `MarkdownDocumentData.init(data:)` / `data()` | tests `roundTripsUTF8ContentUnchanged`, `preservesCRLFLineEndings`, `preservesUTF8BOM` |

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
| REQ-030 | The system shall perform all editing offline, with no network access. | INC-01 | Done | no networking APIs used | inherent (inspection) |
| REQ-031 | The system shall collect no telemetry and require no account. | INC-01 | Done | no analytics/account code | inherent (inspection) |
| REQ-032 | The system shall be operable via VoiceOver and full keyboard control. | INC-01 / COR-07 | Done | stock controls; `TaskCheckboxAttachmentCell` role/label/value + `accessibilityPerformPress`; WYSIWYG Space/Return/mouse toggle | `taskToggleSharedAcrossInteractionPaths`; framework inherent for stock controls |

---

## Live-styled Source

### E · Live-styled source

| ID | Requirement (EARS) | Inc | Status | Implemented in | Verified by |
|----|--------------------|-----|--------|----------------|-------------|
| REQ-040 | WHILE in the source editor, the system shall apply live syntax styling as the user types, using display attributes that never modify the file bytes. | INC-02 | Done | `MarkdownTextView.Coordinator.apply` | tests `attributeStylingLeavesStringUnchanged`, `rangesWithinBounds` |
| REQ-041 | The system shall lexically style common Markdown/GFM source constructs: headings, bold, italic, inline code, fenced code blocks, links, images, ordered/unordered lists, task lists, blockquotes, tables, strikethrough, and thematic breaks. | INC-02 | Done | `MarkdownHighlighter` + `MarkdownTheme` | tests `stylesHeadingWithLevel`, `stylesInlineElements`, `stylesFencedCodeBlock`, `returnsAttributesPerStyle` |
| REQ-042 | WHERE a future named dialect profile is approved, the system shall support that profile's explicitly defined source styles without changing the formal-GFM default. | Future dialect profiles | Deferred | — | — |
| REQ-043 | The system shall visually distinguish fenced code blocks (monospace + subtle tint). | INC-02 | Done | `MarkdownHighlighter` + `MarkdownTheme` | test `stylesFencedCodeBlock` |
| REQ-044 | The system shall display a live word and character count for the document. | INC-02 | Done | `TextStats`, `TextStatsComputer`, `ContentView` | tests `countsWordsAndCharacters`, `computesCountsOffMainActor` |
| REQ-045 | WHILE editing a large document, the system shall keep typing latency imperceptible (highlighting debounced and computed off the main thread). | INC-02 | Done | `MarkdownTextView.Coordinator` (120 ms debounce, version gate; no document-size styling suspension) + `TextStatsComputer` (off-main, cancellation-aware scan) | test `computesCountsOffMainActor`; inherent (native insertion is the synchronous edit path; styling remains version-gated and cancellable for every document size) |
| REQ-046 | The system shall support standard find and replace within the document. | INC-02 | Done | `MarkdownTextView` (`usesFindBar`) | inherent (framework-provided) |

## Markdown dialect

| ID | Requirement (EARS) | Inc | Status | Implemented in | Verified by |
|----|--------------------|-----|--------|----------------|-------------|
| REQ-047 | The system shall present formal GFM 0.29-gfm, including its bundled CommonMark core and five formal extensions, as the only supported MVP source dialect. | COR-01 | Done | `TokenStyle`, `MarkdownHighlighter`, `MarkdownTheme` | test `supportedDialectContainsOnlyCommonMarkAndFormalGFMStyles`; full parser conformance belongs to REQ-054 |
| REQ-048 | WHEN source contains valid formal-GFM double-tilde strikethrough, the system shall apply the strikethrough source style without interpreting that syntax as subscript. | COR-03 | Done | `MarkdownHighlighter.strikethroughRanges` (double-tilde only) | table test `stylesFormalGFMTildeStrikethroughFixtures` |
| REQ-049 | WHEN source contains an unsupported writing extension or single-tilde span, the system shall preserve its text unchanged without presenting it as supported footnote, highlight, superscript, subscript, or strikethrough semantics. | COR-03 | Done | `MarkdownHighlighter` (no Tier-2 styles; single tilde unstyled) | tests `preservesUnknownExtensionsWithoutSemanticStyles`, `stylesFormalGFMTildeStrikethroughFixtures` |
| REQ-050 | WHEN source contains a focused valid CommonMark image destination fixture, the system shall style its source range without changing the source text. | COR-01 | Done | `MarkdownHighlighter` (image destination pattern) | table test `stylesCommonMarkImageDestinationFixtures` |
| REQ-051 | WHILE applying lexical styling, the system shall keep every attributed range within the source bounds and leave the source string unchanged. | COR-01 | Done | `MarkdownHighlighter.tokens(for:)`, `MarkdownTextView.Coordinator.apply` | tests `attributeStylingLeavesStringUnchanged`, `rangesWithinBounds` |

## Image placement

### F · Input and representations

| ID | Requirement (EARS) | Inc | Status | Implemented in | Verified by |
|----|--------------------|-----|--------|----------------|-------------|
| REQ-060 | WHEN the user pastes or drops a supported image into a saved document, the system shall add it at the source selection captured immutably before asynchronous work begins. | COR-09 | Done | `ImagePlacementTarget`, `ImagePlacementIntent`, `EditorActionRouter`, `ImagePlacementController` | `addImageResolvesCapturedIntentToSourceRange`; image placement lifecycle tests |
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
| REQ-069 | WHEN one action contains multiple images, the system shall preserve provider order and insert their references separated by one line break as one undoable source replacement. | COR-02 / COR-08 | Done | `ImagePlacementController` discrete `SourceMutation`; typed source intent | tests `commitsOrderedBatchAsOneUndoableReplacement`, `addImageResolvesCapturedIntentToSourceRange` |

### H · Transaction, lifecycle, safety, and accessibility

| ID | Requirement (EARS) | Inc | Status | Implemented in | Verified by |
|----|--------------------|-----|--------|----------------|-------------|
| REQ-070 | WHEN adding one or more images, the system shall insert no source reference until every required destination file exists at its final contained path. | COR-02 | Done | `ImagePlacementController.runPlacement`, `ImageBatchPreflight` | tests `copiesSupportedFileRepresentationsByteForByte`, `stagesRegularPNGAndRejectsCorrupt` |
| REQ-071 | IF placement fails before source insertion, THEN the system shall remove only temporary and newly-created files proven to belong exclusively to that action, leaving all source, reused, and pre-existing files untouched. | COR-02 | Done | `AssetDirectoryStore.rollback`, identity pins | test `rollbackRemovesOnlyPinnedCreatedFiles` |
| REQ-072 | IF asynchronous placement overlaps a subsequent edit at the tracked insertion range, THEN the system shall cancel source insertion rather than guess a new location. | COR-02 | Done | `InsertionRangeTracker` | table test `boundaryTable` |
| REQ-073 | WHEN inserting one image reference, the system shall use an empty image description and select it for immediate authoring without inventing alternative text from the filename. | INC-03 | Done | `MarkdownSourceTextView.insertImageMarkdown` | test `selectsEmptyDescriptionForSingleImage`; inherent (`setAccessibilityLabel` on source view) |
| REQ-074 | WHEN image-reference insertion is undone or a reference is deleted, the system shall leave every asset file in place. | COR-02 | Done | `MarkdownSourceTextView.insertImageMarkdown` (text-only undo) | test `sourceUndoRetainsPlacedAssets` |
| REQ-075 | WHEN an untitled document receives an image action, the system shall complete the normal Save flow before creating `assets/`, canceling the action if Save is canceled. | COR-02 | Done | `DocumentSaveBridge`, `ImagePlacementController.beginUntitledSave` | test `untitledCancelLeavesIdle`; operation-scoped Save integration |
| REQ-076 | WHEN Save As, rename, or move changes the document parent and a canonical local `assets/…` image reference (app-generated or manually authored) that resolved under the previous parent no longer resolves under the new parent, the system shall warn without silently copying, moving, or deleting companion files. | COR-02 | Done | `CanonicalAssetReferenceScanner`, `ImagePlacementController.updateDocumentURL` | tests `findsCanonicalReferencesAndExcludesCode`, `detectsBrokenAfterParentChangeIncludingManual` |
| REQ-077 | The system shall perform image inspection, hashing, promise receipt, and file I/O off the main actor while rejecting symlinks, aliases, packages, non-regular sources, symlinked destinations, and paths outside the resolved sibling `assets/` directory. | COR-02 | Done | `ImageIOExecutor`, `POSIXFileOps`, `AssetDirectoryStore`, `ImageBatchPreflight` | tests `workRunsOffMainQueue`, `rejectsSymlinkSource`, `rejectsSymlinkedAssetsDirectory` |

---

## Document ownership and lifecycle

| ID | Requirement (EARS) | Inc | Status | Implemented in | Verified by |
|----|--------------------|-----|--------|----------------|-------------|
| REQ-013 | The system shall use one `NSDocument` instance as the owner of canonical Markdown source, file location, source version, and undo history for each open document. | COR-04 | Done | `MarkdownDocument` | tests `documentOwnsUndoManager`, `exactUTF16ReplaceAdvancesVersion` |
| REQ-014 | The system shall provide standard macOS New, Open, Save, Save As, autosave-in-place, Versions, tabs, and Recents behavior. | COR-04 | Done | `MarkdownDocumentController`, `Markdown_EditorApp`, `MarkdownDocument.makeWindowControllers` | inherent framework behavior; test `autosavesInPlace` |
| REQ-015 | WHEN reading or writing a document, the system shall preserve the existing UTF-8, empty-file, BOM, CRLF, Unicode, invalid-UTF-8, zero-edit byte-fidelity, and ordinary-file/no-metadata contract through the default serialized `NSDocument` I/O model. | COR-09 | Done | `MarkdownDocument.read` / `data(ofType:)` main-thread serialized path | `readAndDataRoundTripByteFixtures`; `serializedReadInstallsCanonicalTextOnMain`; `documentControllerOpenAndSaveRoundTrip` |
| REQ-016 | WHEN either editor adapter submits an expected source version and exact UTF-16 replacement, the document shall either advance its source version once and register document-owned undo/redo or return a typed stale/invalid/conflict refusal without mutation. | COR-04 / COR-05 | Done | `SourceMutation`, `HistoryPatch`, `MarkdownDocument.commitSourceMutation` | `SourceIntegrityCharacterizationTests`, existing document/COR-02 suites |
| REQ-017 | WHEN a dependent operation requires an untitled document to be saved, the document shall expose operation-scoped Save success, cancellation, or failure without discovering document ownership through a view. | COR-04 | Done | `MarkdownDocument.saveDocument`, `DocumentActionInterface` | tests `injectedSaveSuccessCancelFailure`, `saveGoesThroughInterfaceNotViewLookup` |
| REQ-018 | The system shall keep mutable document/AppKit state on the main actor and send only immutable `Sendable` value snapshots to background work. | COR-09 | Done | `SourceSnapshot`; main-actor `MarkdownDocument`; `EditorSemanticWorker`; off-main parse/image snapshots | clean Swift 6 complete-concurrency build; `dataOfTypeSnapshotsCanonicalMainActorText`; `semanticWorkerRunsOffMainThread`; `workRunsOffMainQueue` |
| REQ-019 | WHEN Save As, rename, or move changes the document URL, the document shall advance its location generation and notify image placement through the editor-neutral selection/Save/URL/source-commit interface without changing exact-copy or failure semantics. | COR-04 | Done | `MarkdownDocument.fileURL`, `DocumentActionInterface`, `ImagePlacementController` | tests `locationGenerationAdvancesOnURLChangeButNotUntitledSave`, `untitledSaveURLDoesNotBumpGenerationForActiveTransaction`, image-placement suite |

## Source and WYSIWYG editing

### E · Dialect, projection, and commands

| ID | Requirement (EARS) | Inc | Status | Implemented in | Verified by |
|----|--------------------|-----|--------|----------------|-------------|
| REQ-052 | The system shall provide persistent editable Source and WYSIWYG modes over the same canonical source, make WYSIWYG the default, expose a visible mode toggle that never changes source by itself, and keep one session-owned typed state per mode. | COR-09 | Done | `EditorSession.SourceModeState` / `WYSIWYGModeState`; `EditorHost` | `EditorStateOwnershipTests`; `bothEditorsRetainIdentityAcrossModeToggles` |
| REQ-053 | WHILE Source mode is active, the system shall show and edit literal Markdown characters using the existing lexical styling path. | INC-04 | Done | `MarkdownTextView`, `MarkdownHighlighter` | existing Source highlighter/transaction tests |
| REQ-054 | WHILE WYSIWYG is active, the system shall parse the complete formal GFM 0.29 dialect through the pinned direct cmark-gfm configuration and render every supported semantic construct. | INC-04 / COR-06 | Done | `MarkdownParser`, `ProjectionCompiler` | parser conformance; `listsRetainVisibleMarkersAndNesting`; oracle |
| REQ-055 | WHEN source is unsupported, malformed, or raw HTML, WYSIWYG shall show it literally as unformatted, non-executing, editable text and preserve it unchanged unless the user edits that text. | INC-04 / COR-06 | Done | `ProjectionCompiler` literalFallback segments | `testUnsupportedAndHTMLRemainLiteral`; oracle |
| REQ-056 | WYSIWYG attributed storage shall omit parsed Markdown control characters rather than hiding or making them transparent, while retaining literal punctuation that is content. | INC-04 / COR-06 | Done | `ProjectionSegment`, `ProjectionCoordinateMap`, `ProjectionCompiler` | `testProjectionOmitsParsedDelimiters`; `emphasisMapsVisibleTextToExactSourceSlice`; no proportional map |
| REQ-057 | WHEN a WYSIWYG or toolbar action changes Markdown, the system shall preserve existing source spelling where safely patchable and otherwise regenerate only the smallest proven semantic unit—never the whole document. | COR-09 | Done | `SemanticEditEngine.plan`, `PresentationTransitionPlanner`, planners | `AcceptedEditTransactionTests`; existing planner suites |
| REQ-058 | The system shall provide the same formatting toolbar in both modes for paragraph/Heading 1–6, bold, italic, strikethrough, inline code, link, ordered/unordered/task list, block quote, and code block; unsafe or ambiguous commands shall be disabled or refused without changing source. | COR-09 | Done | `EditorToolbar` typed `EditorSelection` | `toolbarUsesModeLocalOffsetZero`; toolbar command suites |
| REQ-059 | WHEN clipboard content offers rich and plain representations, the MVP shall paste its plain-text representation rather than infer Markdown formatting. | INC-04 | Done | `PastePolicy`, `MarkdownTextView`, `WYSIWYGTextView` | test `testPastePolicyPrefersPlainText` |

### F · Rich interaction, images, and tables

| ID | Requirement (EARS) | Inc | Status | Implemented in | Verified by |
|----|--------------------|-----|--------|----------------|-------------|
| REQ-078 | WHEN a supported task-list item is shown in WYSIWYG, its checkbox shall be directly operable and commit one exact task-marker source/presentation transaction. | COR-09 | Done | `WYSIWYGTextView.toggleTask`; `SemanticEditEngine` task planner | `taskToggleSharedAcrossInteractionPaths`; `taskTogglePatchesOnlyExactMarker` |
| REQ-079 | WHEN a supported link is shown in WYSIWYG, it shall be directly clickable while its label remains editable through an explicit edit action. | INC-04 / COR-07 | Done | `WYSIWYGTextView` link click → injected opener; `LinkEditPlanner` for label edits | `testLinkOpenerAcceptsNonHTTPSchemes`; link planner coverage |
| REQ-080 | WYSIWYG shall render and permit exact single-cell content edits in existing GFM tables, including literal escaped pipes, while refusing cross-cell/structural edits and offering no table insertion or row/column controls. | COR-09 | Done | `ProjectionSelectionClassifier`; `TableCellEditPlanner` | `ProjectionSelectionClassifierTests`; table cell suites |
| REQ-081 | WHEN a local PNG, JPEG, GIF, HEIC, or HEIF reference resolves, WYSIWYG shall decode a bounded display representation off-main without changing source, original bytes, metadata, or format and without fetching remote images. | INC-04 / COR-07 | Done | `LocalImageDecoder`/`LocalImageResolver`/`LocalImageByteCache` (CGImage, ≤64 MiB); no file-backed display re-encode | `heicAndHeifDecodeWithoutTouchingOriginals`; `unsupportedOrCorruptContentRejected`; `imageCacheRespectsBudgetAndRefreshesOnChange`; `testResolvesPNGJPEGGIFHEICWithoutTouchingOriginalBytes` |
| REQ-082 | The system shall provide “Add Image…” in both modes through the existing COR-02 placement transaction and shall not introduce an Import command or a second image pipeline. | INC-04 / COR-07 | Done | `EditorActionRouter`; `EditorSession.addImages` captures intent then routes claims | `addImageUsesWindowScopedRouterNotGlobalNotification`; `addImageDoesNotCrossDocumentWindows`; `testAddImageRoutesThroughPlacementClaims` |
| REQ-083 | WHEN an edit, toolbar action, task toggle, link change, or image insertion is undone/redone after switching modes, the document-owned undo manager shall restore canonical source and the exact source-domain selection while leaving assets intact. | COR-09 | Done | `EditorUpdateOrigin`; `PendingSelectionRestoration`; document history | `NativeUpdateOriginTests`; history suites |
| REQ-084 | WYSIWYG shall preserve native TextKit selection, marked text/IME, spelling, Find, keyboard editing, plain-text paste, and meaningful accessibility roles, labels, values, and image descriptions. | COR-09 | Done | `WYSIWYGTextView`; `CompositionState`; `EditorUpdateOrigin` | composition and paste characterization suites |
| REQ-085 | The system shall compute parser, source-index, authoritative projection, and image-decode work off-main and apply complete results only when source revision, location generation, and operation identity still match. | COR-09 | Done | `EditorSession.scheduleParse`; `EditorSemanticWorker`; reconciliation generation/identity gates | `parseIndexProjectionP95Under100msAt100k`; `semanticWorkerRunsOffMainThread`; `workRunsOffMainQueue`; reconciliation tests |
| REQ-086 | WHEN the user switches modes, each persistent editor shall restore its session-owned typed selection, affinity, and scroll state without changing source. | COR-09 | Done | `EditorSession` mode state; `EditorHost.applyMode` | `eachModeRestoresOwnSelectionAndScroll` |
| REQ-087 | IF parsing, mapping, semantic translation, local-image resolution, or asynchronous work fails, THEN the system shall keep Source available, leave canonical source unchanged, and expose literal fallback, temporary WYSIWYG unavailability, or typed atomic refusal rather than guessing. | COR-09 | Done | `WYSIWYGAvailability`; typed `EditRefusal`; oracle | `refusedEditChangesNeither`; projection refusal suites |

## Concurrency, evidence, and performance

| ID | Requirement (EARS) | Inc | Status | Implemented in | Verified by |
|----|--------------------|-----|--------|----------------|-------------|
| REQ-088 | The system shall compile the application and non-UI test targets in Swift 6 language mode with complete concurrency checking and without unsafe mutable-state isolation opt-outs or data-race warnings. | COR-09 | Done | Swift 6 complete concurrency project settings | clean Debug/Release non-UI builds |
| REQ-089 | The system shall provide privacy-safe mutation, presentation-transition, reconciliation, composition, update-origin, refusal, and image-cache instrumentation without recording document/replacement/selected content, URLs, descriptions, or complete paths. | COR-09 | Done | `EditorTraceEvent` presentation/reconciliation/origin fields | `editorTraceOmitsSourceSelectionAndPathStrings` |
| REQ-090 | WHILE operating on the approved performance corpus, the system shall satisfy p95 WYSIWYG keystroke translation below 8 ms at 100,000 UTF-16 units, p95 mode toggle below 16 ms, p95 off-main parse/index/projection below 100 ms at 100,000 UTF-16 units, zero dropped accepted input, zero stale-result applications, zero parser/image-decode work on the main actor, and a decoded-image cache no larger than 64 MiB. | COR-09 | Done | performance characterization + rapid-input + bounded-cache suites | `keystrokeTranslationP95Under8ms`; `modeToggleP95Under16ms`; `parseIndexProjectionP95Under100msAt100k`; `oneHundredImmediateKeystrokes`; `imageCacheRespectsBudgetAndRefreshesOnChange` |
| REQ-091 | WHILE WYSIWYG is editable, every accepted native text replacement shall advance canonical source and the matching presented content/map synchronously before another input is accepted. | COR-09 | Done | `EditorSession.perform` + `PresentationTransition` + WYSIWYG adapter | `AcceptedEditTransactionTests` |
| REQ-092 | WHEN the user types Markdown punctuation in WYSIWYG, the system shall show it as literal visible content and encode the minimum safe formal-GFM source spelling without treating typing as a formatting command. | COR-09 | Done | `MarkdownLiteralEncoder` | `MarkdownLiteralEncoderTests` |
| REQ-093 | WHILE canonical source lacks a matching valid WYSIWYG presentation snapshot, the system shall keep Source available and make WYSIWYG unavailable for editing rather than expose stale rich content. | COR-09 | Done | `WYSIWYGAvailability`; adapter `isEditable` gate | `AcceptedEditTransactionTests`; availability paths in `EditorSession` |

---

*Deferred:* in-fence language syntax coloring, dialect profiles, rich-to-Markdown paste conversion,
table creation/structural controls, image sizing syntax, transcoding, metadata stripping, remote
images, automatic asset cleanup, and asset-aware Save Copy.

*Next free IDs: REQ-008 (A), REQ-023 (C), REQ-033 (D), REQ-094 (editing).*
