# Requirements

What the app does today: one EARS sentence per requirement, current behavior only. Future work
lives in GitHub issues (the backlog is [#110](https://github.com/tonimelisma/Markdown-Editor/issues/110)), not here. Architecture is in
[architecture.md](architecture.md).

## Conventions

- **ID:** `REQ-###`, assigned sequentially, never reused or renumbered. A retired requirement is
  deleted with its ID.
- **EARS:** `When` (event), `While` (state), `If … then` (unwanted), `Where` (optional), otherwise a
  ubiquitous "The system shall …".
- **Status:** `[verified]` when at least one test or check carries `Validates: REQ-###`, observed
  passing; otherwise `unverified:` with the reason no automated test proves it. `script/process-check`
  enforces both directions: every tag names a declared requirement, and every requirement is one
  or the other.
- **Traceability is owned by the code.** The `Validates:` comment lives next to the proof and moves
  with it. The `Proof:` line under each requirement names tests for a reader and may drift; fix it
  when you notice. It deliberately names no production types: a hand-maintained second copy of the
  code rots silently, which is how the falsification manifests failed
  ([ADR 0001](adr/0001-the-verification-apparatus-was-removed.md)).
- **Verification kinds (no manual or UI tests, ever):** `test` = automated unit/component test
  needing no UI automation · `inherent` = satisfied by construction, either because a standard
  framework provides the behavior (`NSDocument` provides Versions) or because inspection proves
  an absence (makes no network calls) · `visual-review` = one passive screenshot of the app's own
  window, for human oversight of rendering. `visual-review` is never a standalone proof, and
  neither is an agent-drive run (`CLAUDE.md` §4), which drives the app for an agent to look at.
- **Liveness:** a requirement promising a capability carries at least one proof that the
  capability succeeds, not only proofs that it refuses. See `CLAUDE.md` §3.
- **Increment:** the `Increment:` note names the roadmap increment (INC-, COR-, DISC-) that
  introduced or last corrected it.

## Documents and native editing

### A · Documents & files

- **REQ-001** The system shall read and write documents as UTF-8 plain-text Markdown files with a `.md` or `.markdown` extension (`net.daringfireball.markdown`). [verified]
  Proof: test `markdownUTTypeIdentifier`, `readableWritableTypesAreMarkdown`. Increment: INC-01.
- **REQ-002** When the user chooses File ▸ New, the system shall create an empty untitled Markdown document. [verified]
  Proof: test `newDocumentStartsEmptyAndUntitled`; test `newRouteCreatesEmptyDocument`. Increment: INC-01 / COR-74.
- **REQ-003** When the user opens a `.md`/`.markdown` file, the system shall load its UTF-8 contents into an editor window. [verified]
  Proof: test `readContractInstallsOnlyValidUTF8`; test `documentControllerOpenAndSaveRoundTrip`. Increment: INC-01 / COR-74.
- **REQ-004** If a file is not valid UTF-8, then the system shall report a read error and shall not open a corrupted document. [verified]
  Proof: test `readContractInstallsOnlyValidUTF8`; test `readRejectsInvalidUTF8`. Increment: INC-01 / COR-74.
- **REQ-005** When the user edits a document, the system shall autosave changes without an explicit Save. [verified]
  Proof: test `autosavesInPlace`; test `editIsDirtyAndSaveFailureIsScopedToTheDocument`. Increment: INC-01 / COR-74.
- **REQ-006** The system shall preserve macOS document Versions so the user can browse and revert. [verified]
  Proof: test `standardDocumentLifecycleUsesAppKitOwners`; test `requiredDocumentFileSelectorsAreDeclared`. Increment: INC-01 / COR-74.
- **REQ-007** The system shall save without altering bytes the user did not edit, preserving the file's existing line endings and encoding. [verified]
  Proof: tests `roundTripsUTF8ContentUnchanged`, `preservesCRLFLineEndings`, `preservesUTF8BOM`, `CRLFCodeBlockTests.mixedLineEndingsPreserveUntouchedTerminators` (per-line mixed LF/CRLF preserved), `editingOneLinePreservesOtherTerminators`. Increment: INC-01 / COR-38.
- **REQ-145** When the document's file is changed by another process while the document has no unsaved changes, the system shall adopt the file's contents and shall restore the source caret clamped into the new text. [verified]
  Proof: test `externalWriteToCleanDocumentReloadsAndKeepsSelection`, `preservedSelectionIsClampedIntoTheNewText` (ExternalChangeTests). Increment: COR-87.
- **REQ-146** When the document's file is changed by another process while the document has unsaved changes, the system shall retain the in-memory content, shall not write over the external change, and shall record the disagreement until a save or revert resolves it. [verified]
  Proof: test `externalWriteToDirtyDocumentKeepsLocalEditsAndMarksConflict`, `revertingResolvesTheConflict` (ExternalChangeTests). Increment: COR-87.
- **REQ-147** If the document's file is deleted by another process, then the system shall retain the in-memory content and shall mark it as unsaved work. [verified]
  Proof: test `externalDeleteRetainsContentAndCannotLoseTheBuffer`, `deletionRetainsContentFromEitherLocalState` (ExternalChangeTests). Increment: COR-87.
- **REQ-148** When the document's file is moved by another process, the system shall follow the new location and shall resolve relative asset references against the new parent directory. [verified]
  Proof: test `externalMoveReResolvesRelativeAssetReferences` (ExternalChangeTests). Increment: COR-87.
- **REQ-149** The system shall declare an outcome for every combination of external file event and local edit state, and no outcome shall discard unsaved content. [verified]
  Proof: test `everyExternalChangeClassHasDeclaredBehavior` (ExternalChangeTests); `externalChangeDiagnosticsCarryNoPath`. Increment: COR-87.

### B · Editing (plain text)

- **REQ-010** The system shall provide plain-text editing of the document contents. [verified]
  Proof: test `nativeReplacementPreservesUnicodeAndDocumentUndoRoute`; test `nativePasteUsesPlainTextAndDiscreteUndo`; test `programmaticSourceStylingCannotCreateAnEdit`. Increment: INC-01 / COR-75.
- **REQ-011** The system shall support unlimited undo and redo of edits. [verified]
  Proof: test `nativeReplacementPreservesUnicodeAndDocumentUndoRoute`; test `undoRedoRestoresTextAndAdvancesVersion`; test `everyActionNameIsUniqueAndPresentable`, `everySemanticCommandNameIsInTheVocabulary` (UndoActionNameTests). Increment: INC-01 / COR-05 / COR-75.
- **REQ-012** The system shall integrate the macOS spell-checker. [verified]
  Proof: test `productionSourceEditorUsesNativeSpellAndFindServices`. Increment: INC-01 / COR-75.

### C · Standard macOS behaviors

- **REQ-020** The system shall support document tabs (multiple documents in one window). [verified]
  Proof: test `standardDocumentLifecycleUsesAppKitOwners`. Increment: INC-01 / COR-74.
- **REQ-021** The system shall list recently opened documents under File ▸ Open Recent. [verified]
  Proof: test `recentsUseTheStandardDocumentControllerRoute`. Increment: INC-01 / COR-74.
- **REQ-022** The system shall adopt the system Light/Dark appearance automatically. [verified]
  Proof: test `semanticAppearanceDoesNotMutateSource`; test `TypographyTokenTests`. Increment: INC-01 / COR-75.

### D · Non-functional

- **REQ-030** The system shall perform all editing offline, and shall make no network access other than REQ-033's update check. [verified]
  Proof: test `productionBoundaryRejectsNetworkAccountAndAnalyticsCapabilities`, `onlyTheUpdaterImportsSparkle`. Increment: INC-01 / COR-75 / 2026-11-26.
- **REQ-031** The system shall collect no telemetry and require no account. [verified]
  Proof: test `productionBoundaryRejectsNetworkAccountAndAnalyticsCapabilities`; test `diagnosticPayloadsCannotCarryFreeText`. Increment: INC-01 / COR-75.
- **REQ-032** The system shall be operable via VoiceOver and full keyboard control. [verified]
  Proof: test `everyCommandIsKeyboardReachable` (matrix over `EditorCommand.allCases`), `noTwoCommandsShareAShortcut`, plus the REQ-129 role matrix. VoiceOver itself is not driven — `CLAUDE.md` §4 forbids screen automation; roles/values are proved on directly constructed elements. Increment: INC-01 / COR-07 / COR-81.
- **REQ-033** Where the build carries the update key, the system shall check its release feed over HTTPS, install only a newer build whose EdDSA signature matches its update key, send no system profile, and install it when the application quits. [verified]
  Proof: test `onlyAKeyedBuildOutsideVerificationUpdatesItself`, `theDebugBundleNeverUpdatesItselfAndSendsNoProfile` (no profile); release feed by `Scripts/test-release-scripts.sh`. An installed copy was seen updating itself to published releases: the owner reported it on 2026-11-27, after v1.0.3–v1.0.6. Increment: 2026-11-26.
- **REQ-034** If the process is a Debug build, a test host, or a smoke or benchmark run, then the system shall neither check for nor install updates. [verified]
  Proof: test `onlyAKeyedBuildOutsideVerificationUpdatesItself`, `theDebugBundleNeverUpdatesItselfAndSendsNoProfile`, `theTestHostDoesNotUpdateItself`. Increment: 2026-11-26. Former status: Active.

## Live-styled Source

### E · Live-styled source

- **REQ-040** While in the source editor, the system shall apply live syntax styling as the user types, using display attributes that never modify the file bytes. [verified]
  Proof: `SourceEditorParityTests`; `IncrementalSourceHighlighterTests`. Increment: COR-72.
- **REQ-041** The system shall lexically style common Markdown/GFM source constructs: headings, bold, italic, inline code, fenced code blocks, links, images, ordered/unordered lists, task lists, blockquotes, tables, strikethrough, and thematic breaks. [verified]
  Proof: test `IncrementalSourceHighlighterTests` (fence propagation, cross-line strikethrough carry, same-line duplicate suppression, `unclosedBracketDoesNotPairAcrossALineBoundary`, `crossLineStrikethroughOverlappingInlineCodeIsSuppressed`); `incrementalHighlightingMatchesAFullRelexAfterEveryEditKind` asserts zero divergence over the 96-document generated corpus x 8 edit kinds (COR-84 repaired 30). Increment: COR-72.
- **REQ-043** The system shall visually distinguish fenced code blocks (monospace + subtle tint). [verified]
  Proof: `MarkdownHighlighterTests`; `IncrementalSourceHighlighterTests`. Increment: COR-72.
- **REQ-044** The system shall display a live word and character count for the document. [verified]
  Proof: test `liveCountOwnerEnumeratesUnicodeAndRevisionRoute`; test `staleCountWorkReturnsNothing`. Increment: INC-02 / COR-75.
- **REQ-045** While editing a large document, the system shall keep typing latency imperceptible (highlighting debounced and computed off the main thread). [verified]
  Proof: test `IncrementalSourceHighlighterTests` (fence propagation, cross-line strikethrough carry, same-line duplicate suppression, `unclosedBracketDoesNotPairAcrossALineBoundary`, `crossLineStrikethroughOverlappingInlineCodeIsSuppressed`); `incrementalHighlightingMatchesAFullRelexAfterEveryEditKind` asserts zero divergence over the 96-document generated corpus x 8 edit kinds (COR-84 repaired 30). Increment: COR-72.
- **REQ-046** The system shall support standard find and replace within the document. [verified]
  Proof: test `productionSourceEditorUsesNativeSpellAndFindServices`. Increment: INC-02 / COR-75.

## Markdown dialect

- **REQ-047** The system shall present formal GFM 0.29-gfm, including its bundled CommonMark core and five formal extensions, as the only supported MVP source dialect. [verified]
  Proof: `FormalGFMContractTests` (`manifestMatchesClosedProductionDialect`); `MarkdownParserTests` (`testPinnedRevisionAndExactExtensions`). Increment: COR-01 / COR-76.
- **REQ-048** When source contains valid formal-GFM double-tilde strikethrough, the system shall apply the strikethrough source style without interpreting that syntax as subscript. [verified]
  Proof: `FormalGFMContractTests` (`unsupportedWritingExtensionsRemainLiteral`); `MarkdownHighlighterTests` (`stylesFormalGFMTildeStrikethroughFixtures`). Increment: COR-03 / COR-76.
- **REQ-049** When source contains an unsupported writing extension or single-tilde span, the system shall preserve its text unchanged without presenting it as supported footnote, highlight, superscript, subscript, or strikethrough semantics. [verified]
  Proof: `FormalGFMContractTests` (`everyFormalFixtureUsesAllProductionBoundaries`, `unsupportedWritingExtensionsRemainLiteral`). Increment: COR-03 / COR-76.
- **REQ-050** When source contains a focused valid CommonMark image destination fixture, the system shall style its source range without changing the source text. [verified]
  Proof: `FormalGFMContractTests` (`imageAndDelimiterRoundTripsAreExact`); `MarkdownHighlighterTests` (`stylesCommonMarkImageDestinationFixtures`). Increment: COR-01 / COR-76.
- **REQ-051** While applying lexical styling, the system shall keep every attributed range within the source bounds and leave the source string unchanged. [verified]
  Proof: tests `attributeStylingLeavesStringUnchanged`, `rangesWithinBounds`. Increment: COR-01.

## Image placement

### F · Input and representations

- **REQ-060** When the user pastes or drops a supported image into a saved document, the system shall add it at the source selection captured immutably before asynchronous work begins. [verified]
  Proof: test `rejectsSimultaneousBegin`, `ignoresLateResultFromOldUUID`, `reachesCommittedTerminal`; test `addImageResolvesCapturedIntentToSourceRange`; test `imageIntentResolvesProjectionBeforePlacement`. Increment: COR-09.
- **REQ-061** When a regular file is detected as PNG, JPEG, GIF, HEIC, or HEIF, the system shall copy its bytes unchanged without transcoding it. [verified]
  Proof: test `copiesSupportedFileRepresentationsByteForByte`, `copiesJPEGAndGIFByteForByte`, `stagesRegularPNGAndRejectsCorrupt`, `bitmapClaimAlreadyPNGIsCopiedUnchanged`. Increment: COR-02.
- **REQ-062** When a pasteboard item provides bitmap data but no supported file or file promise, the system shall encode the bitmap as PNG. [verified]
  Proof: test `bitmapOnlyClaimIsEncodedAsPNG`, `bitmapClaimAlreadyPNGIsCopiedUnchanged`, `corruptBitmapClaimIsRejected`. Increment: INC-03.
- **REQ-063** If an item is corrupt, its detected representation is unsupported, or its claimed extension disagrees with an unsafe/unsupported representation, then the system shall reject the entire user action with a clear error. [verified]
  Proof: test `oneCorruptItemRejectsTheWholeBatch`, `detectsTypeFromContent`, `rejectsProviderError`, `stagesRegularPNGAndRejectsCorrupt`. Increment: COR-02.
- **REQ-064** When paste or drag content contains meaningful non-image text, the system shall preserve native plain-text paste or drag behavior rather than consume it as an image action. [verified]
  Proof: test `mixedTextAndImageFallsThroughToTextPaste`, `testPastePolicyPrefersPlainText`. Increment: INC-03.

### G · Placement, naming, and source

- **REQ-065** When adding an image, the system shall use a visible sibling `assets/` directory as a shared non-owned destination, creating it only when needed. [verified]
  Proof: test `assetsDirectoryIsCreatedOnlyWhenAnImageIsPlaced`, `rejectsSymlinkedAssetsDirectory`. Increment: COR-02.
- **REQ-066** The system shall generate a lowercase ASCII filename that is safe across common macOS, Linux, and Windows filesystems and uses the detected representation’s canonical extension. [verified]
  Proof: test `generatesPortableAssetNames` (parameterized). Increment: INC-03.
- **REQ-067** When a destination filename already exists, the system shall reuse it only for byte-identical content and otherwise select a deterministic SHA-256-suffixed non-overwriting name using case-insensitive collision checks. [verified]
  Proof: test `differentlyCasedExistingAssetIsNeverOverwritten`, `hashSuffixesDifferentCollision`, `reusesIdenticalAsset`, `reusesIdenticalAssetOnDisk`. Increment: COR-02.
- **REQ-068** When placement succeeds, the system shall insert standard relative Markdown `![](assets/name.ext)` without a title, dimensions, HTML, base64, percent-encoded filename, or private metadata. [verified]
  Proof: test `generatesPortableCommonMarkImageReferences`, `destinationSpellingsAgreeWithThePinnedParser`. Increment: INC-03.
- **REQ-069** When one action contains multiple images, the system shall preserve provider order and insert their references separated by one line break as one undoable source replacement. [verified]
  Proof: test `commitsOrderedBatchAsOneUndoableReplacement`. Increment: COR-02 / COR-08.

### H · Transaction, lifecycle, safety, and accessibility

- **REQ-070** When adding one or more images, the system shall insert no source reference until every required destination file exists at its final contained path. [verified]
  Proof: test `everyPublishedFileExistsAtItsFinalPathBeforeMarkdownIsProduced`, `copiesSupportedFileRepresentationsByteForByte`. Increment: COR-02.
- **REQ-071** If placement fails before source insertion, then the system shall remove only temporary and newly-created files proven to belong exclusively to that action, leaving all source, reused, and pre-existing files untouched. [verified]
  Proof: test `rollbackRemovesOnlyPinnedCreatedFiles`, `rollsBackEarlierPublishesWhenLaterItemFails`. Increment: COR-02.
- **REQ-072** If asynchronous placement overlaps a subsequent edit at the tracked insertion range, then the system shall cancel source insertion rather than guess a new location. [verified]
  Proof: test `boundaryTable` (parameterized, 8 boundary cases). Increment: COR-02.
- **REQ-073** When inserting one image reference, the system shall use an empty image description and select it for immediate authoring without inventing alternative text from the filename. [verified]
  Proof: test `selectsEmptyDescriptionForSingleImage`. Increment: INC-03.
- **REQ-074** When image-reference insertion is undone or a reference is deleted, the system shall leave every asset file in place. [verified]
  Proof: test `sourceUndoRetainsPlacedAssets`. Increment: COR-02.
- **REQ-075** When an untitled document receives an image action, the system shall complete the normal Save flow before creating `assets/`, canceling the action if Save is canceled. [verified]
  Proof: test `untitledCancelLeavesIdle`, `untitledSaveFailureIsRecordedAsPlacementFailure`, `untitledSaveURLDoesNotBumpGenerationForActiveTransaction`. Increment: COR-02.
- **REQ-076** When Save As, rename, or move changes the document parent and a canonical local `assets/…` image reference (app-generated or manually authored) that resolved under the previous parent no longer resolves under the new parent, the system shall warn without silently copying, moving, or deleting companion files. [verified]
  Proof: `detectsBrokenAfterParentChangeIncludingManual`; `findsCanonicalReferencesAndExcludesCode`; `canonicalAssetReferencesDoNotRepublishTheDocument`. Increment: COR-02 / COR-21.
- **REQ-077** The system shall perform image inspection, hashing, promise receipt, and file I/O off the main actor while rejecting symlinks, aliases, packages, non-regular sources, symlinked destinations, and paths outside the resolved sibling `assets/` directory. [verified]
  Proof: test `workRunsOffMainQueue`, `rejectsSymlinkSource`, `rejectsDirectoryAndPackageSource`, `rejectsAliasSource`, `rejectsSymlinkedAssetsDirectory`. Increment: COR-02.

## Document ownership and lifecycle

- **REQ-013** The system shall use one `NSDocument` instance as the owner of canonical Markdown source, file location, source version, and undo history for each open document. [verified]
  Proof: test `newDocumentStartsEmptyAndUntitled`; test `lifecycleOwnerHasNoDuplicateDocumentSubsystem`. Increment: COR-04 / COR-74.
- **REQ-014** The system shall provide standard macOS New, Open, Save, Duplicate, Rename, Move To, Revert Document (Last Saved Version, or the Versions browser), Save As, autosave-in-place, Versions, tabs, and Recents behavior. [verified]
  Proof: test `requiredDocumentFileSelectorsAreDeclared`; test `theFileMenuOffersTheAutosavingDocumentCommands`; test `newRouteCreatesEmptyDocument`; test `standardDocumentLifecycleUsesAppKitOwners`; test `recentsUseTheStandardDocumentControllerRoute`. Increment: COR-04 / COR-74.
- **REQ-015** When reading or writing a document, the system shall preserve the existing UTF-8, empty-file, BOM, CRLF, Unicode, invalid-UTF-8, zero-edit byte-fidelity, and ordinary-file/no-metadata contract through `NSDocument`'s serialized reads and its asynchronous writes of the text as each save began. [verified]
  Proof: test `readAndDataRoundTripByteFixtures`; test `readContractInstallsOnlyValidUTF8`; test `documentControllerOpenAndSaveRoundTrip`; test `aBackgroundWriteWritesTheTextAsTheSaveBegan`. Increment: COR-09 / COR-74.
- **REQ-016** When either editor adapter submits an expected source version and exact UTF-16 replacement, the document shall either advance its source version once and register document-owned undo/redo or return a typed stale/invalid/conflict refusal without mutation. [verified]
  Proof: `SourceIntegrityCharacterizationTests`, `EditorTransactionKernelTests`, existing document/COR-02 suites. Increment: COR-04 / COR-05.
- **REQ-017** When a dependent operation requires an untitled document to be saved, the document shall expose operation-scoped Save success, cancellation, or failure without discovering document ownership through a view. [verified]
  Proof: test `injectedSaveSuccessCancelFailure`; test `editIsDirtyAndSaveFailureIsScopedToTheDocument`. Increment: COR-04 / COR-74.
- **REQ-018** The system shall keep mutable document/AppKit state on the main actor and send only immutable `Sendable` value snapshots to background work. [verified]
  Proof: clean Swift 6 complete-concurrency build; `dataOfTypeSnapshotsCanonicalMainActorText`; `semanticWorkerRunsOffMainThread`; `workRunsOffMainQueue`. Increment: COR-09.
- **REQ-019** When Save As, rename, or move changes the document URL, the document shall advance its location generation and notify image placement through the editor-neutral selection/Save/URL/source-commit interface without changing exact-copy or failure semantics. [verified]
  Proof: test `locationGenerationAdvancesOnURLChangeButNotUntitledSave`; test `untitledSaveURLDoesNotBumpGenerationForActiveTransaction`. Increment: COR-04 / COR-74.

## Source and WYSIWYG editing

### E · Dialect, projection, and commands

- **REQ-052** The system shall provide persistent editable Source and WYSIWYG modes over the same canonical source, make WYSIWYG the default, expose a visible mode toggle that never changes source by itself, and keep one session-owned typed state per mode. [verified]
  Proof: test `bothEditorsRetainIdentityAcrossModeToggles`, `sessionOwnsTypedModeState`, `sessionExposesNoAppKitPresentation`, `testModeToggleDoesNotChangeSource`. Increment: COR-09.
- **REQ-053** While Source mode is active, the system shall show and edit literal Markdown characters using the existing lexical styling path. [verified]
  Proof: `FormalGFMContractTests` (`everyFormalFixtureUsesAllProductionBoundaries`); `MarkdownHighlighterTests`. Increment: INC-04 / COR-76.
- **REQ-054** While WYSIWYG is active, the system shall parse the complete formal GFM 0.29 dialect through the pinned direct cmark-gfm configuration and render every supported semantic construct. [verified]
  Proof: `MarkdownParserTests` (`testFormalGFMSpecSuiteHTMLConformance`, `testFormalGFMExtensionSuiteHTMLConformance`); `FormalGFMContractTests` (`everyFormalFixtureUsesAllProductionBoundaries`). Increment: INC-04 / COR-06 / COR-76.
- **REQ-055** When source is unsupported, malformed, or raw HTML, WYSIWYG shall show it literally as unformatted, non-executing, editable text and preserve it unchanged unless the user edits that text. [verified]
  Proof: `FormalGFMContractTests` (`everyFormalFixtureUsesAllProductionBoundaries`, `unsupportedWritingExtensionsRemainLiteral`). Increment: INC-04 / COR-06 / COR-76.
- **REQ-056** WYSIWYG attributed storage shall omit parsed Markdown control characters rather than hiding or making them transparent, while retaining literal punctuation that is content. [verified]
  Proof: `FormalGFMContractTests` (`imageAndDelimiterRoundTripsAreExact`); `ProjectionCharacterizationTests` (`emphasisMapsVisibleTextToExactSourceSlice`). Increment: INC-04 / COR-06 / COR-76.
- **REQ-057** When a WYSIWYG or toolbar action changes Markdown, the system shall preserve existing source spelling where safely patchable and otherwise regenerate only the smallest proven semantic unit—never the whole document. [verified]
  Proof: `taskTogglePatchesOnlyExactMarker`; `ProjectionAndSemanticEditTests`; `AcceptedEditTransactionTests`; `SourceTransactionTests`. Increment: COR-09 / COR-40.
- **REQ-058** The system shall provide the same formatting commands in both modes for paragraph/Heading 1–6, bold, italic, strikethrough, inline code, link, ordered/unordered/task list, block quote, and code block through an adaptive native window toolbar and matching menu routes; unsafe or ambiguous commands shall be disabled or refused without changing source. [verified]
  Proof: `CommandLivenessMatrixTests` (every command x both modes; a new command with undeclared behavior fails the build); `WYSIWYGListCommandRegressionTests`; `EditorCommandControllerTests`; `EditorToolbarConstructionTests`; `EditorMenuCommandTests`; `LinkEditorSheetTests`. Increment: INC-06 / COR-25.
- **REQ-059** When clipboard content offers rich and plain representations, the MVP shall paste its plain-text representation rather than infer Markdown formatting. [verified]
  Proof: `NativeSourceContractTests` (`nativePasteUsesPlainTextAndDiscreteUndo`); `LocalImageAndPasteTests/testPastePolicyPrefersPlainText`. Increment: INC-04 / COR-75 / COR-76.
- **REQ-113** When a semantic formatting command reports enabled availability for the current selection, the system shall apply it rather than refuse. [verified]
  Proof: `everyEnabledCommandPerformsInSourceMode`; `everyEnabledCommandPerformsInWYSIWYGMode`; `CommandLivenessMatrixTests` (closed matrix); `WYSIWYGListCommandRegressionTests`. Increment: COR-26 / COR-33 / COR-38 / COR-40.
- **REQ-152** When the user types in WYSIWYG, Return shall end the paragraph or heading and start a new one, continue a list with its next item (an empty item ending the list), and add a line to a code block, and spaces typed at the end of a line shall be kept. [verified]
  Proof: `BlockBoundaryTypingTests` (`returnStartsANewParagraphInANewDocument`, `returnContinuesAListAndAnEmptyItemEndsIt`, `returnContinuesNumberedAndTaskLists`, `returnInACodeBlockIsALineOfCode`, `aSpaceAtTheEndOfALineIsKept`, `theTourNoteTypesAsWritten`). Increment: TOUR-01.
- **REQ-153** When the user presses Delete in WYSIWYG, the system shall delete the character before the caret, and at the start of a block shall remove an empty paragraph, turn a heading or list item into a paragraph, or join a paragraph to the one before it. [verified]
  Proof: `BlockBoundaryTypingTests` (`deleteRemovesTheCharacterBeforeTheCaret`, `deleteUndoesReturn`, `deleteAtAParagraphsStartJoinsItToThePreviousOne`, `deleteAtAHeadingsStartMakesItAParagraph`, `deleteAtAListItemsStartTakesItsMarkerAway`). Increment: TOUR-01.

### F · Rich interaction, images, and tables

- **REQ-078** When a supported task-list item is shown in WYSIWYG, its checkbox shall be directly operable and commit one exact task-marker source/presentation transaction. [verified]
  Proof: `taskPresentationHasCheckboxWithoutDuplicateBullet`; `taskTogglePatchesOnlyExactMarker`; `taskToggleSharedAcrossInteractionPaths`. Increment: COR-09 / COR-34.
- **REQ-079** When a supported link is shown in WYSIWYG, it shall be directly clickable while its label remains editable through an explicit edit action. [verified]
  Proof: test `testWYSIWYGLinkClickUsesSessionOpener`, `testLinkOpenerAcceptsNonHTTPSchemes`, `sheetEditsControllerStateAndCommitsThroughTheCommandRoute`, `cancelLeavesSourceAndRevisionUnchanged`. Increment: INC-04 / COR-07.
- **REQ-080** WYSIWYG shall render and permit exact single-cell content edits in existing GFM tables, including literal escaped pipes, while refusing cross-cell/structural edits and offering no table insertion or row/column controls. [verified]
  Proof: test `nativeTableTypingRoutesThroughTablePlanner`, `tableCellEscapesPipe`, `tableCellEditChangesOnlyIntendedCellContent`, `tableCellEditRefusesStructuralBreakers`, `refusesCrossCellSelection`, `tableCellHalfOpenBoundaryPrefersLaterColumn`, `tableSelectionExtendingIntoParagraphIsMixed` (14 anchored proofs). Increment: COR-09.
- **REQ-081** When a local PNG, JPEG, GIF, HEIC, or HEIF reference resolves, WYSIWYG shall reject an encoded file above 256 MiB before full read, mapping, hashing, or decode, then decode a bounded display representation off-main without changing source, original bytes, metadata, or format and without fetching remote images. [verified]
  Proof: `ImageDisplayServiceTests/oversizedEncodedFileIsRejectedBeforeRead`; `ImageDisplayServiceTests/supportedRepresentationsDecodeWithoutChangingOriginalBytes`; `PersistentEditorCharacterizationTests`. Increment: COR-21 / COR-73.
- **REQ-082** The system shall provide “Add Image…” in both modes through the existing COR-02 placement transaction and shall not introduce an Import command or a second image pipeline. [verified]
  Proof: test `testAddImageRoutesThroughPlacementClaims`, `addImageUsesWindowScopedRouterNotGlobalNotification`, `addImageDoesNotCrossDocumentWindows`, `addImageResolvesCapturedIntentToSourceRange`, `addImageIsDisabledWhileWYSIWYGHasNoCurrentPresentation`. Increment: INC-04 / COR-07.
- **REQ-083** When an edit, toolbar action, task toggle, link change, or image insertion is undone/redone after switching modes, the document-owned undo manager shall restore canonical source and the exact source-domain selection while leaving assets intact. [verified]
  Proof: test `testUndoAcrossModesRestoresSource`, `undoRedoRestoresSourceSelectionsAcrossModeChanges`, `programmaticOriginDoesNotCloseTyping`, `wysiwygTypingCoalescesThroughSession`. Increment: COR-09.
- **REQ-084** WYSIWYG shall preserve native TextKit selection, marked text/IME, spelling, Find, keyboard editing, plain-text paste, and meaningful accessibility roles, labels, values, and image descriptions. [verified]
  Proof: test `compositionCommitsOnceAndStaleRefuses`, `compositionInsertAppliesFinalTextSynchronously`, `nativeMarkedTextCallbackStaysTransient`, `nativeMarkedTextStaleCommitCancelsNativeStateAndUndoGroup`, `bothCompositionCommitRoutesUseTheSameTransaction`, `literalInsertionBesideNonBMPCharactersIsExact` (21 anchored proofs); `theEditMenuOffersFind` (the Edit menu takes ⌘F and the File menu ⌘W). Increment: COR-09.
- **REQ-085** The system shall compute parser, source-index, authoritative projection, and image-decode work off-main and apply complete results only when source revision, location generation, and operation identity still match. [verified]
  Proof: `ImageDisplayServiceTests`; `DiagnosticLogTests/parseOwnerCancellationInvalidatesGeneration`; `DiagnosticLogTests/parseOwnerRecordsImageDisplayCacheTelemetryOnTheProductionRoute`; `DiagnosticLogTests/parseOwnerRecordsStaleReconciliation`; `ReconciliationInvariantTests`. Increment: COR-09 / COR-73.
- **REQ-086** When the user switches modes, each persistent editor shall restore its session-owned typed selection, affinity, and scroll state without changing source. [verified]
  Proof: test `eachModeRestoresOwnSelectionAndScroll`, `sessionSelectionRestorationAppliedByPersistentHost`, `pendingSelectionWaitsForMatchingProjection`, `hostDoesNotRelabelOldNativeSelectionWithNewSnapshot`, `modeChangeStillRestoresPerModeChrome`; `switchingIntoSourceShowsTheTopEvenWhenAppKitParksTheDocumentView`, `aRecordedSourceScrollPositionSurvivesARoundTrip` (COR-93: scroll state is an offset from the top of the document, not a raw clip-view bounds origin). Increment: COR-09.
- **REQ-087** If parsing, mapping, semantic translation, local-image resolution, or asynchronous work fails, then the system shall keep Source available, leave canonical source unchanged, and expose literal fallback, temporary WYSIWYG unavailability, or typed atomic refusal rather than guessing. [verified]
  Proof: test `testStaleVersionRefused`, `invalidRichSelectionIsRefusedNotClamped`, `uneditableBoundariesRefuseInsteadOfMappingToZero`, `projectionMappingRefusesWithoutPresentation`, `crossBlockSelectionStillRefusesEveryBlockCommand` (15 anchored proofs). Increment: COR-09.

## Concurrency, evidence, and performance

- **REQ-088** The system shall compile the application and non-UI test targets in Debug and Release under Swift 6 complete concurrency checking without unsafe mutable-state isolation opt-outs or data-race warnings.
  Proof: serial Debug and Release XCTest runs. Increment: COR-18.
  unverified: the proof is the build, not a test. Every target and configuration sets Swift 6 and `SWIFT_STRICT_CONCURRENCY = complete`, so a data-race error fails the build; a data-race warning shows only in `Scripts/check.sh`'s warning count, which does not fail it.
- **REQ-089** The system shall provide privacy-safe mutation, presentation-transition, reconciliation, composition, update-origin, refusal, and image-cache instrumentation whose payload value type admits only numbers, booleans, and code-defined symbols, so that document/replacement/selected content, URLs, descriptions, filenames, and paths are unrepresentable rather than merely omitted. [verified]
  Proof: test `everyTraceEventMapsToSymbolicPayload`, `diagnosticPayloadHasNoStringCase`, `editorTraceOmitsSourceSelectionAndPathStrings`. Increment: COR-10.
- **REQ-090** While operating on the approved performance corpus, the system shall satisfy p95 complete native-input callback below 8 ms on every shape not declared a stress shape and within a recorded bound on the stress shapes, p95 complete mode transition below 16 ms, p95 off-main parse/index/semantic-projection below 100 ms at 100,000 UTF-16 units, nonzero executed samples, zero dropped accepted input, zero stale-result applications, zero parser/image-decode work on the main actor, and a decoded-image cache no larger than 64 MiB. [verified]
  Proof: `nativeInputCallbackP95Under8ms` (PersistentEditorCharacterizationTests) — Release, macOS 27.0 arm64, concrete `NSTextStorage`, typing into a prepended lead paragraph on every `PerformanceCorpus` case, 10 warmups / 40 samples: four non-stress shapes under 8 ms; `tableDense` 11.6 ms and `heavyLists` 17.1 ms bounded at 22 ms and 30 ms; `PerformanceBoundaryTests`; mode-transition and parse/index/projection suites; `ImageDisplayServiceTests/decodedCacheHasTheApprovedBound`. Increment: COR-18 / COR-20 / COR-21 / COR-32 / COR-45 / COR-71 / COR-73 / COR-92.
- **REQ-143** While a semantic formatting command executes, the system shall complete its main-actor work within 16 ms for a median command and within 32 ms for any command, on every approved performance corpus shape not declared a stress shape; shall stay within a recorded bound on the stress shapes; and shall reconcile the document at most once per command. [verified]
  Proof: test `semanticCommandStaysWithinItsMeasuredCeiling`, `theBudgetBindsEveryNonStressShape`, `semanticCommandIsSampledByTheProductionRoute`, `everyRecordedDurationNamesABudgetedMetric` (SemanticCommandBudgetTests); test `oneCommandPerformsOneAuthoritativeRebuild`, `oneCommandParsesItsCandidateTextOnce`, `aSessionsParsesUseItsOwnMemo`, `aMemoHitEqualsAFreshBuild`, `aParseMemoHitEqualsAFreshParse` (AuthoritativeRebuildCountTests). Increment: COR-86 / COR-89.
- **REQ-144** The system shall read no launch argument or environment variable outside its declared launch surface, and no such switch shall modify document content unless the process was launched for smoke verification. [verified]
  Proof: test `noUndeclaredEnvironmentVariableIsRead`, `documentMutatingSwitchesRequireTheSmokeArgument`, `declaredArgumentsAreUniqueAndFlagShaped` (LaunchSurfaceTests). Increment: COR-90.
- **REQ-091** While WYSIWYG is editable, every accepted native text replacement shall advance canonical source and the matching presented content/map synchronously before another input is accepted. [verified]
  Proof: `AcceptedEditTransactionTests`; `LocalTransitionDomainTests`; `PersistentEditorCharacterizationTests/compositionInsertAppliesFinalTextSynchronously`; `PerformanceBoundaryTests`; `TextStorageApplierTests`. Increment: COR-09 / COR-71.
- **REQ-092** When the user types Markdown punctuation in WYSIWYG, the system shall show it as literal visible content and encode the minimum safe formal-GFM source spelling without treating typing as a formatting command. [verified]
  Proof: `AcceptedEditTransactionTests/consecutiveLiteralPunctuationKeepsExactSourceAndVisibleText`; punctuation/context matrix; `LocalTransitionDomainTests`. Increment: COR-09 / COR-71.
- **REQ-093** While canonical source lacks a matching valid WYSIWYG presentation snapshot, the system shall keep Source available and make WYSIWYG unavailable for editing rather than expose stale rich content. [verified]
  Proof: test `projectionMappingRefusesWithoutPresentation` (WYSIWYG unavailable), `repeatedLoadsNeverReuseRevisionOrOldPresentation` (no stale rich content), `sourceStaysEditableWhileWYSIWYGHasNoPresentation` (Source stays available). Increment: COR-09.
- **REQ-094** If SwiftUI reconciles the persistent editor host, then the system shall neither publish a session change nor capture live native selection, affinity, or scroll state during that reconciliation, and reconciling an unchanged mode shall mutate no session state. [verified]
  Proof: test `hostReconciliationPublishesNothing`, `unchangedModeReconciliationMutatesNoSessionState`, `programmaticSelectionDoesNotWriteSessionState`, `nativeSelectionStillUpdatesSessionState`, `idleDocumentSettlesAfterBoundedHostUpdates`. Increment: COR-10.
- **REQ-095** The system shall record diagnostics for one application run into one JSON Lines file under the user's Logs directory, beginning with a record identifying schema version, run identity, build, host kind (production or unit test), and process, and shall bound retained runs and per-file size. [verified]
  Proof: `runHeaderIdentifiesHostKindAndBuild`; `everyRecordIsOneParsableJSONLine`; `finishWritesTerminatingRecord`; `fileSizeCapIsBoundedAndRecorded`; `retentionRemovesOldestRuns`; `watchdogRecordsRemainOrderedAndCannotAppendAfterFinish`; `diagnosticsDirectoryHonoursEnvironmentOverride`; `everyTraceEventMapsToSymbolicPayload`. Increment: COR-10 / COR-19.
- **REQ-096** If session state is published or live native state is captured during editor-host reconciliation, the editor-host update rate exceeds its sustained threshold, or the main actor does not respond within one second while the main thread is neither serving an app-modal session nor waiting in one of AppKit's own run-loop modes or on AppKit's own synchronous work for the app, such as loading the print panel (such a wait counts once it lasts ten seconds), then the system shall durably record a fault diagnostic identifying the condition while an unrecovered main-actor stall remains in progress, and shall collapse repeated non-fault events into a counted summary. [verified]
  Proof: `repeatedEventsCollapseWithCount`; `processFaultReporterWritesWhileMainActorIsBlocked`; `detachedSessionsReleaseAllSamplerRegistrations`; `samplerInvalidationIsIdempotentAndEmitsOneSummary`; `watchdogReportsStallWhileStillBlocked`; `watchdogReportsNoStallWhileAppKitWorksForTheApp`; `aCancelledProbeReportsNoStall`; `watchdogReportsAppKitWorkThatOutlastsItsBound`; `printBeginsItsPanelWhileAppKitWorksForTheApp`; `reentrantPublicationRecordsFault`; `liveStateCaptureDuringReconciliationRecordsFault`; `hostUpdateStormRecordsFault`. Increment: COR-19.
- **REQ-097** The system shall write diagnostics to a directory named by the `MARKDOWN_EDITOR_DIAGNOSTICS_DIR` environment variable when it is set, so verification runs cannot read, prune, or pollute the user's production diagnostics. [verified]
  Proof: test `diagnosticsDirectoryHonoursEnvironmentOverride`, `aRunUnderTheOverrideNeverPrunesTheProductionDirectory`. Increment: COR-11.
- **REQ-098** When process-level smoke verification runs, the system shall open a fixture document, settle within a bounded number of editor-host view updates, record no `error` or `fault` diagnostic, and write a terminating record. [verified]
  Proof: process smoke (ARC-Q12) observed in `Scripts/check.sh`, and on the signed Release bundle before every release (`Scripts/release.sh`); verifier discrimination proved by `Scripts/test-verify-smoke-log.sh` (nine rejected fixtures), also run by the gate. Increment: COR-11.
- **REQ-099** The system shall define no instrumentation event that is never recorded, so that the event vocabulary is an accurate description of what a run can report. [verified]
  Proof: `CommandLivenessMatrixTests` closed-vocabulary matrix; `DiagnosticLogTests` production-route records. Increment: COR-12 / COR-58 / COR-68.
- **REQ-100** The system shall record the outcome of every document load, save, autosave, and revert, including failures, without recording file names, paths, or contents. [verified]
  Proof: tests `documentLoadFailureIsRecorded`, `documentLoadFailureForUnreadableURLIsRecorded`, `documentLoadThroughURLRecordsNoFailure`, `revertOfNeverBeforeLoadedDocumentIsClassifiedAsRevert`, `documentSaveFailureIsRecorded`, `documentSaveCancelledBeforeDestinationIsRecorded`, `documentIOTraceOmitsPaths`; smoke test asserts exactly one `documentLoaded`. Known gap documented in architecture.md §9: Save-panel cancellation on an untitled document through the plain Cmd+S/File-menu path (not this app's own `saveDocument()` bridge) is not recorded. Increment: COR-13.
- **REQ-101** The system shall record image-placement phase transitions, claim counts, byte counts, and typed failures for every paste, drag-and-drop, and Add Image operation, without recording file names, paths, providers, or image data. [verified]
  Proof: test `imagePlacementFailureIsRecorded`, `imagePlacementTraceOmitsFilenames`, `rollbackIsRecorded`, `failureRecordsTerminalTransitionBackToIdle`, `busyRejectionIsRecordedWithoutDisturbingActivePlacement`, `staleAddImageClaimsAreRecordedWithoutStartingPlacement`. Increment: COR-14.
- **REQ-102** When the system presents a failure or warning to the user, it shall record a matching diagnostic at `error` or `warn` level. [verified]
  Proof: test `everyAlertSiteRecordsDiagnostic` (closed matrix over every alert site), `imagePlacementFailureIsRecorded`. Increment: COR-14.
- **REQ-103** The system shall record periodic bounded summary statistics for complete native-input callback, complete mode transition, parse/projection, image resolution, and authoritative application durations during ordinary use, each summary counting every sample of its window, its largest exactly and its percentiles from a uniform sample of the whole window, judging a p95 against its budget only from at least 20 samples and carrying fewer into the next window, without recording per-keystroke events, retaining closed sessions, or leaving timers alive after detach. [verified]
  Proof: `samplerComputesPercentilesFromKnownDistribution`; `aSummaryCountsEverySampleOfItsWindowAndKeepsTheLargest`; `thePercentilesWeighTheWholeWindow`; `aFewSamplesCarryIntoTheNextWindowBeforeTheirP95IsJudged`; `theLastFlushWritesAFewSamplesWithoutJudgingThem`; `samplerInvalidationIsIdempotentAndEmitsOneSummary`; `detachedSessionsReleaseAllSamplerRegistrations`; Release callback evidence; `TextStorageApplierTests`. Increment: COR-19 / COR-20.
- **REQ-104** When a build increment's closing sequence runs, process-level verification shall capture one screenshot of the application's own window over a fixture exercising broad Markdown and typography semantics, require the matching structured log to prove one document, one applied reconciliation, a later host update, bounded direct-plus-collapsed updates, performance samples, no fault, and clean termination, and expose the screenshot for mandatory human/agent visual review without capturing other on-screen content. [verified]
  Proof: `VisualReviewFixtureTests`; final smoke-screenshot run and visual review of `/private/tmp/md-editor-smoke-final.png`. Increment: COR-18.
- **REQ-114** If a referenced local image fails to resolve for display, then the system shall record its typed failure class without recording file names, paths, or image data. [verified]
  Proof: `DiagnosticLogTests` production-route image failure diagnostics; `ImageDisplayServiceTests`. Increment: COR-29 / COR-73.
- **REQ-115** When process-level verification runs, it shall additionally exercise at least one accepted text insertion and one accepted semantic command and assert on the resulting structured records. [verified]
  Proof: `Scripts/test-verify-smoke-log.sh`; `Scripts/smoke-test.sh` smoke log with `presentationInstalled` and `editRouted`. Increment: COR-29.
- **REQ-116** The system shall record a bounded periodic summary of WYSIWYG layout duration alongside its existing performance metrics. [verified]
  Proof: `PerformanceBudgetTests` (every metric budgeted; budgets match the approved values); `Scripts/verify-smoke-log.py` metric allowlist. Increment: COR-29.
- **REQ-142** When process-level verification runs, the system shall reject a run that leaks memory, recording the leak count rather than silently passing. [verified]
  Proof: `Scripts/test-leak-report-parser.sh` (six fixtures: clean, leaky, empty, absent, no-count, ambiguous); observed `leak-smoke: PASS (0 leaks)` with the smoke run's own structured assertions passing. Stage 0 tool decision in `docs/research/2026-08-22-cor-83-leak-tooling.md`. Run explicitly, not in `check.sh` — see that research file. Increment: COR-83.
- **REQ-151** When launched for smoke verification with a declared screenshot scene, the system shall present that screen through its ordinary window-scoped command routes, refuse a screen it has no current presentation for, and modify no document content. [verified]
  Proof: `ScreenshotSceneTests` (`galleryScriptAndSceneEnumAgree`, `sceneSelectionRequiresTheSmokeArgument`, `sourceSceneSelectsSourceModeWithoutChangingTheDocument`, `wysiwygSceneSelectsTheReadingSurface`, `linkSceneOpensTheSheetPrefilledFromTheSelectedLink`, `linkSceneRefusesWithoutACurrentPresentation`); observed `Scripts/screenshots.sh` run, each scene's structured log verified before its image was committed. Increment: GAL-01.

## Native reading surface and rewrite contracts

- **REQ-105** While WYSIWYG presents supported Markdown, the system shall apply the approved editorial typography tokens—15-point system body, approximately 1.35× line height, maximum 720-point centered measure, minimum 28-point horizontal and 20-point vertical insets, approximately 0.7-em paragraph spacing, and the approved heading hierarchy—without changing source. [verified]
  Proof: `approvedTypographyTokensAreStable`; `typographyUsesAdaptiveSystemValues`; `headingSpacingIsLargerBeforeThanAfter`; `semanticBlocksAndTypographyDoNotChangeRenderedSource`; `readingColumnUsesMinimumInsetsAndMaximumMeasure`; `typographyTokensAndAppKitStayInTheirOwners`. Increment: INC-05.
- **REQ-106** When cmark identifies a soft break, hard break, or paragraph boundary, the system shall present respectively a space within the paragraph, a forced line break, or a paragraph-spacing boundary without inserting presentation-only characters into source. [verified]
  Proof: `softAndHardBreaksHaveDistinctPresentationText`; `hardBreakAdvancesOneLineWhileParagraphBoundaryAddsSpacing`; `fencedCodeBlockDoesNotSpaceItsOwnLinesApart`; `ParagraphGeometryTests` at narrow/default/wide widths. Increment: INC-05.
- **REQ-107** While WYSIWYG presents lists, tasks, blockquotes, code, tables, thematic breaks, images, or raw HTML, the system shall use the approved semantic block treatment including cumulative hanging indentation, checkbox-without-duplicate-bullet alignment, quote rule/inset, padded code block, content-sized table, full-measure separator, bounded aspect-preserving image, and non-executing literal HTML. [verified]
  Proof: `ParagraphGeometryTests.fencedCodeBlockDoesNotSpaceItsOwnLinesApart`; `nestedParagraphKeepsItsListItemContentIndent` and `quoteNestedInAListItemKeepsRuleAndIndent` (laid-out line-fragment origins at narrow/default/wide widths, rehearsed failing at x=0 against the defect); `fencedCodeCarriesNoInlineRunBackground`; `missingImagePlaceholderIsLabelledAndNotTruncated`; `taskPresentationHasCheckboxWithoutDuplicateBullet`; `blockQuoteUsesLeadingRuleAndContentInset`; `codeBlockIsPaddedAdaptiveContainer`; `codeInsideQuoteComposesBothContainers` (quote rule + code background composed at identical range, control non-nil, rehearsed failing with backgroundColor nil); `nestedBlockQuotesComposeTheirRules` (depth via composed count); `listParagraphStyleUsesCumulativeHangingIndentation`. Increment: INC-05 / COR-36 / COR-37.
- **REQ-108** When a semantic formatting command is available, the system shall expose one window-scoped validated command through matching native menu and adaptive toolbar presentations and shall present link editing as a window-attached sheet. [verified]
  Proof: `everyToolbarCommandItemCarriesAnImage`; `everyCommandSymbolResolvesOnThisPlatform`; `EditorCommandControllerTests`; `EditorToolbarConstructionTests`; `EditorMenuCommandTests`; `LinkEditorSheetTests`. Increment: INC-06.
- **REQ-129** While WYSIWYG presents a semantic Markdown construct, the system shall expose its role, value, hierarchy, frame, and available actions through directly constructed AppKit accessibility elements without exposing document content outside that construct. [verified]
  Proof: test `everyBlockKindHasADeclaredAccessibilityRole`, `headingsExposeTheirLevel`, `taskItemsExposeCheckboxRoleAndState`, `nestingAndQuoteDepthAreExposedAsLevels`, `descriptorsCarryNoDocumentContent`; mutating the matrix also reddens `taskToggleSharedAcrossInteractionPaths`, so the model is load-bearing in production. Increment: COR-81.
- **REQ-130** When the user prints a document, the system shall use the native macOS print workflow and paginate the current Markdown presentation without changing source or history. [verified]
  Proof: test `theFileMenuOffersTheAutosavingDocumentCommands` (File › Print…, ⌘P); test `printingReturnsANativeOperationOverTheEditorView`, `printingMutatesNeitherSourceNorHistory`, `longDocumentPaginatesAcrossMultiplePages` (forced TextKit layout, not attribute inspection), `printingWithoutAnEditorIsRefused`. Increment: COR-82.
- **REQ-131** The system shall provide native window restoration/cascading/tabbing and one window-scoped validated command surface whose menu, toolbar, and approved keyboard routes remain usable at the minimum window size. [verified]
  Proof: test `windowsUseStandardRestorationCascadingAndTabbing`, `toolbarRemainsUsableAtTheMinimumWindowSize`, `commandValidationStaysWindowScoped`, `menuAndToolbarExposeTheSameSemanticCommandSet`, `addImageDoesNotCrossDocumentWindows`, `everyCommandIsKeyboardReachable`. Increment: COR-82.
- **REQ-139** While presenting any declared semantic color role in Light or Dark appearance, the system shall meet WCAG 2.1 contrast — 4.5:1 for normal text, 3:1 for text at least 18pt (or 14pt bold) and for non-text UI components. [verified]
  Proof: test `everyColorRoleMeetsItsContrastBound` (every role, Light and Dark, alpha composited onto the surface it is drawn on), `codeTextMeetsContrastOnTheCodeBackground`, `increasedContrastNeverLowersAnyRolesRatio`. COR-85 repaired the two roles that were below bound; the pinned violation set is deleted, not emptied. Increment: COR-81.
- **REQ-140** The system shall not adopt a text-scaling API it cannot verify honors the platform's Accessibility Text Size preference for third-party content, and shall record the researched platform boundary. [verified]
  Proof: test `noTextScalingAPIIsAdopted` — production adopts no text-scaling API, so no unverifiable claim is made; `docs/research/2026-08-11-disc-08-macos-text-scaling.md`. Increment: DISC-08. Former status: Deferred.
- **REQ-141** The system shall introduce no motion or translucency without a paired Reduce Motion/Reduce Transparency accommodation, and shall express every color through the system's appearance-and-contrast-aware color catalog rather than a literal value. [verified]
  Proof: test `productionNamesNoColorOutsideTheCatalog`, `theColorLiteralDetectorCatchesEveryFormItClaimsTo` (detector self-test), `motionAndTranslucencyRequirePairedAccommodations`. Increment: COR-81.
- **REQ-109** When an ordinary WYSIWYG edit is accepted, the system shall apply one validated attributed presentation patch before returning from the native input callback and shall not rebuild or replace the complete attributed storage. [verified]
  Proof: `ordinaryInsertionUsesOneBoundedRangePatch` and `attachmentLookupIsSplicedRatherThanRebuilt` (spy `NSTextStorage`: one bounded edit, zero full replacements); `newerSnapshotWithChangedTextUsesOneBoundedPatch` (including immediate/forced application); `hiddenDelimiterCommandRefreshesAttributesWithoutReplacing`, `headingAndLinkCommandsRefreshOnlyTheirSelectedBlock`, and `taskToggleRefreshesOnlyItsSemanticBlock` (only changed semantic blocks receive attributes); `attributeRefreshScopeTracksInsertionsAndRemovalsByPosition` (inserted/removed/changed elements stay bounded by position, not array index); `tableCellEditUsesOneBoundedPatch`; `committedCompositionUsesBoundedPatch`; malformed/stale/surrounding-text refusal proofs; `changedSpanKeepsUnchangedSuffixAtBoundary`; `forcedCurrentSnapshotDoesNotRecoverWithoutStorageDrift`; recovery, accepted-edit, and watchdog-isolation suites. Increment: COR-20 / COR-23 / COR-34.
- **REQ-110** When an editor session detaches or deinitializes, the system shall stop and release its performance sampler and timer after one bounded flush, and terminal diagnostic durability shall complete without waiting for main-actor cleanup. [verified]
  Proof: `detachedSessionsReleaseAllSamplerRegistrations`; `samplerInvalidationIsIdempotentAndEmitsOneSummary`; `synchronousFinishDoesNotWaitForMainActorCleanup`. Increment: COR-19.
- **REQ-111** When parse demand advances while another parse runs or waits, the system shall retain at most the running revision and newest pending revision and shall discard every older pending revision before source-copy or cmark work. [verified]
  Proof: `keepsOnlyNewestPendingRevision`; `detachCancelsRunningAndPendingDemand`; reconciliation identity/cancellation paths. Increment: COR-21.
- **REQ-112** The system shall derive canonical referenced-asset information from the pinned cmark parse tree and concrete source index rather than a regex or line-oriented secondary Markdown scanner. [verified]
  Proof: `findsCanonicalReferencesAndExcludesCode`; `destinationSpellingsAgreeWithThePinnedParser`; `detectsBrokenAfterParentChangeIncludingManual`; `noSecondaryMarkdownScannerRouteExists`. Increment: COR-21.

## Measurement and performance evidence

- **REQ-123** The system shall count document parses, projection compiles, oracle validations, attributed builds, attributed characters written, storage full replacements, image decodes, bytes read, and main-thread blocked nanoseconds per unit of user intent, attributed to a closed scope set, and emitted as a diagnostic. [verified]
  Proof: Tests: `COR69IntentMeasurementTests`, `editorSessionRouteRetainsIntentThroughParse`, `asyncAndGCDWorkRetainTheExplicitIntent`, `recorderOverheadUsesAnIdenticalNoRecorderControl`, `lateWorkAfterFinishIsTypedOrphan`, `presentationLeaseDefersTerminalLedger`, `aWindowAtTheParsedScaleNeedsNoSecondParse` and `aWindowOpenedAfterAttachOnTheMainScreenNeedsNoSecondParse`; full Debug gate and. Increment: COR-44 / COR-69.
- **REQ-124** The system shall sample main-actor responsiveness histogram beside the one-second hang watchdog with a 16 ms p95 budget, counting no hop that waited out an app-modal alert or AppKit's own work for the app, as the watchdog reports none. [verified]
  Proof: Tests: `responsivenessProbeRecordsLatencyDistribution`, `aTwoHundredMillisecondMainActorBlockAppearsInTheLatencyDistribution`, `aHopThatWaitedOutAnAppModalAlertIsNotALatencySample`, `aHopThatWaitedOnAppKitsWorkIsNotALatencySample`; full Debug XCTest and. Increment: COR-44.
- **REQ-125** The system shall record frame-hitch statistics as milliseconds of hitch per observed second and longest frame, derived from the display link's real cadence. [verified]
  Proof: Tests: `COR69IntentMeasurementTests`, `frameObserverProductionRouteRetainsAcknowledgementDelay`, `queuedAcknowledgementCountsAsAFrameHitch`, and `queuedAcknowledgementsAfterStopAreIgnored`; full Debug gate and. Increment: COR-44 / COR-69.
- **REQ-126** The system shall sample memory footprint as phys_footprint and peak via task_info and emit it as a numeric-only diagnostic. [verified]
  Proof: Tests: `memoryFootprintRecordIsNumericOnly`, `memoryFootprintUsesKernelPeakField`; full Debug XCTest and. Increment: COR-44.
- **REQ-127** The system shall provide a closed PerformanceCorpus enumeration whose shapes assert their own structure. [verified]
  Proof: Tests: `corpusShapesProduceTheStructureTheyClaim`, `corpusTruncationPreservesUnitBoundaries`; full Debug XCTest and. Increment: COR-45.
- **REQ-128** The system shall provide a process-level benchmark harness that drives the shipping binary through typing, table typing, commands, mode toggles, scrolling, undo storms and soak, writing a committed baseline. [verified]
  Proof: Tests: `COR69BenchmarkProofTests`, `benchmarkScrollRouteReportsProgress`, `benchmarkRejectsNoProgressAndUnknownActions`, and `benchmarkManifestEnumeratesTheClosedMatrix`; Release benchmark observed 108 passing case results with an atomic provenance-bound baseline; full Debug gate and. Increment: COR-45 / COR-69.

## Conformance verification

- **REQ-132** When generated or imported conformance verification runs, the system shall enumerate every declared input dimension, use independent oracles and reproducible seeds/provenance, and retain each minimized discovered failure as a regression fixture. [verified]
  Proof: Generated: test `dimensionCoverageIsComplete`, `sourceIndexRoundTripsOnEveryGeneratedDocument`, `projectionOracleAcceptsEveryGeneratedDocument`, `incrementalHighlightingMatchesAFullRelexAfterEveryEditKind`, `tokenRangesAreContainedAndGraphemeAligned`, `generatedAssetNamesStayPortableForEveryFlavor`. Shrinking: `shrinkerReducesWhilePreservingTheFailingProperty`, `shrinkingIsDeterministic`, `shrinkingRespectsItsEvaluationBudget`. Imported: `corpusCarriesCompleteProvenance`, `everySpecExampleParsesAndSatisfiesTheProjectionOracle`, `everySpecExampleProducesContainedGraphemeAlignedTokens`, `incrementalLexingAgreesWithFullRelexAcrossTheSpecCorpus` (1,324 examples). Increment: COR-80.
