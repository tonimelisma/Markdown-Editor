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
  or code inspection proves it (e.g. "makes no network calls") · `visual-review` = one
  screenshot of the application's own window, captured non-interactively at the end of a build
  increment and reviewed by the agent and the user (`CLAUDE.md` §4). It never drives or asserts
  on UI and is never a standalone proof — a row citing it always also cites `test` or `inherent`
  for the same requirement; it exists for human oversight of rendering, not as a pass/fail
  gate. Nothing is verified by hand.
- **Forward:** every `Done` requirement records at least one automated test or justified
  construction/framework proof, and `Scripts/check-documentation-authority.sh` resolves each
  cited backticked identifier to a real test symbol or script. **Backward:** every `REQ-###`
  appearing in code/tests exists here.
- **Exemptions (REQ-118):** three absence gates have no requirement to cite them and are exempt with stated reasons: `noUITestTargetInProject` (proves no XCUITest target exists, CLAUDE.md §4 forbids UI tests), `productionForcesNoTextKitLayout` (proves production never forces TextKit layout), `productionTestHooksAreInventoried` (proves no undeclared production test hook exists). `Scripts/check-proof-results.sh` reads this list as its `EXEMPT` source of truth rather than a hard-coded set, so documentation-authority and proof-results compose. A test that is not cited and not exempt fails REQ-118.
- **Observed passing:** a `Done` requirement's cited proof must be **observed to pass** in the
  run that closes the increment; a suite that does not complete leaves every requirement citing it
  unproven, not proven. `Scripts/check-proof-results.sh` correlates `Done` rows with actual test
  results (REQ-117) and ensures no test can fail unnoticed because nothing cites it (REQ-118).
- **Liveness:** a requirement promising a capability carries at least one proof that the
  capability succeeds, not only proofs that it refuses. See `CLAUDE.md` §4.
- **`Correction` is mandatory, not optional.** Once a defect against a `Done` row is reproduced,
  the row moves to `Correction` in the same change that records the reproduction. A `Done` row
  whose increment ROADMAP still lists as active fails the documentation-authority gate.

---

## Documents and native editing

### A · Documents & files

| ID | Requirement (EARS) | Inc | Status | Implemented in | Verified by |
| ---- | -------------------- | ----- | -------- | ---------------- | ------------- |
| REQ-001 | The system shall read and write documents as UTF-8 plain-text Markdown files with a `.md` or `.markdown` extension (`net.daringfireball.markdown`). | INC-01 | Done | `MarkdownContentType` + `MarkdownDocument` (`readableTypes`/`writableTypes`) + `Info.plist` | test `markdownUTTypeIdentifier`, `readableWritableTypesAreMarkdown` |
| REQ-002 | WHEN the user chooses File ▸ New, the system shall create an empty untitled Markdown document. | INC-01 | Correction | — | COR-62 audit: no falsifying manifest observed; re-verify before promotion to Done |
| REQ-003 | WHEN the user opens a `.md`/`.markdown` file, the system shall load its UTF-8 contents into an editor window. | INC-01 | Correction | — | COR-62 audit: no falsifying manifest observed; re-verify before promotion to Done |
| REQ-004 | IF a file is not valid UTF-8, THEN the system shall report a read error and shall not open a corrupted document. | INC-01 | Correction | — | COR-62 audit: no falsifying manifest observed; re-verify before promotion to Done |
| REQ-005 | WHEN the user edits a document, the system shall autosave changes without an explicit Save. | INC-01 | Correction | — | COR-62 audit: no falsifying manifest observed; re-verify before promotion to Done |
| REQ-006 | The system shall preserve macOS document Versions so the user can browse and revert. | INC-01 | Correction | — | COR-62 audit: no falsifying manifest observed; re-verify before promotion to Done |
| REQ-007 | The system shall save without altering bytes the user did not edit, preserving the file's existing line endings and encoding. | INC-01 / COR-38 | Done | `MarkdownDocumentData.init(data:)` / `data()`; `ProjectionAtom` `.normalizedCodeBlock` per-line atomic; `MarkdownLiteralEncoder` per-line `originalSource` overload | tests `roundTripsUTF8ContentUnchanged`, `preservesCRLFLineEndings`, `preservesUTF8BOM`, `CRLFCodeBlockTests.mixedLineEndingsPreserveUntouchedTerminators` (per-line mixed LF/CRLF preserved), `editingOneLinePreservesOtherTerminators` |

### B · Editing (plain text)

| ID | Requirement (EARS) | Inc | Status | Implemented in | Verified by |
| ---- | -------------------- | ----- | -------- | ---------------- | ------------- |
| REQ-010 | The system shall provide plain-text editing of the document contents. | INC-01 | Correction | — | COR-62 audit: no falsifying manifest observed; re-verify before promotion to Done |
| REQ-011 | The system shall support unlimited undo and redo of edits. | INC-01 / COR-05 | Correction | — | COR-62 audit: no falsifying manifest observed; re-verify before promotion to Done |
| REQ-012 | The system shall integrate the macOS spell-checker. | INC-01 | Correction | — | COR-62 audit: no falsifying manifest observed; re-verify before promotion to Done |

### C · Standard macOS behaviors

| ID | Requirement (EARS) | Inc | Status | Implemented in | Verified by |
| ---- | -------------------- | ----- | -------- | ---------------- | ------------- |
| REQ-020 | The system shall support document tabs (multiple documents in one window). | INC-01 | Correction | — | COR-62 audit: no falsifying manifest observed; re-verify before promotion to Done |
| REQ-021 | The system shall list recently opened documents under File ▸ Open Recent. | INC-01 | Correction | — | COR-62 audit: no falsifying manifest observed; re-verify before promotion to Done |
| REQ-022 | The system shall adopt the system Light/Dark appearance automatically. | INC-01 | Correction | — | COR-62 audit: no falsifying manifest observed; re-verify before promotion to Done |

### D · Non-functional

| ID | Requirement (EARS) | Inc | Status | Implemented in | Verified by |
| ---- | -------------------- | ----- | -------- | ---------------- | ------------- |
| REQ-030 | The system shall perform all editing offline, with no network access. | INC-01 | Correction | — | COR-62 audit: no falsifying manifest observed; re-verify before promotion to Done |
| REQ-031 | The system shall collect no telemetry and require no account. | INC-01 | Correction | — | COR-62 audit: no falsifying manifest observed; re-verify before promotion to Done |
| REQ-032 | The system shall be operable via VoiceOver and full keyboard control. | INC-01 / COR-07 | Done | stock controls; `TaskCheckboxAttachmentCell` role/label/value + `accessibilityPerformPress`; WYSIWYG Space/Return/mouse toggle | `taskToggleSharedAcrossInteractionPaths`; framework inherent for stock controls |

---

## Live-styled Source

### E · Live-styled source

| ID | Requirement (EARS) | Inc | Status | Implemented in | Verified by |
| ---- | -------------------- | ----- | -------- | ---------------- | ------------- |
| REQ-040 | WHILE in the source editor, the system shall apply live syntax styling as the user types, using display attributes that never modify the file bytes. | INC-02 | Correction | — | COR-62 audit: no falsifying manifest observed; re-verify before promotion to Done |
| REQ-041 | The system shall lexically style common Markdown/GFM source constructs: headings, bold, italic, inline code, fenced code blocks, links, images, ordered/unordered lists, task lists, blockquotes, tables, strikethrough, and thematic breaks. | INC-02 | Correction | — | COR-62 audit: no falsifying manifest observed; re-verify before promotion to Done |
| REQ-042 | WHERE a future named dialect profile is approved, the system shall support that profile's explicitly defined source styles without changing the formal-GFM default. | Future dialect profiles | Deferred | — | — |
| REQ-043 | The system shall visually distinguish fenced code blocks (monospace + subtle tint). | INC-02 | Correction | — | COR-62 audit: no falsifying manifest observed; re-verify before promotion to Done |
| REQ-044 | The system shall display a live word and character count for the document. | INC-02 | Correction | — | COR-62 audit: no falsifying manifest observed; re-verify before promotion to Done |
| REQ-045 | WHILE editing a large document, the system shall keep typing latency imperceptible (highlighting debounced and computed off the main thread). | INC-02 | Correction | — | COR-62 audit: no falsifying manifest observed; re-verify before promotion to Done |
| REQ-046 | The system shall support standard find and replace within the document. | INC-02 | Correction | — | COR-62 audit: no falsifying manifest observed; re-verify before promotion to Done |

## Markdown dialect

| ID | Requirement (EARS) | Inc | Status | Implemented in | Verified by |
| ---- | -------------------- | ----- | -------- | ---------------- | ------------- |
| REQ-047 | The system shall present formal GFM 0.29-gfm, including its bundled CommonMark core and five formal extensions, as the only supported MVP source dialect. | COR-01 | Correction | — | COR-62 audit: no falsifying manifest observed; re-verify before promotion to Done |
| REQ-048 | WHEN source contains valid formal-GFM double-tilde strikethrough, the system shall apply the strikethrough source style without interpreting that syntax as subscript. | COR-03 | Correction | — | COR-62 audit: no falsifying manifest observed; re-verify before promotion to Done |
| REQ-049 | WHEN source contains an unsupported writing extension or single-tilde span, the system shall preserve its text unchanged without presenting it as supported footnote, highlight, superscript, subscript, or strikethrough semantics. | COR-03 | Correction | — | COR-62 audit: no falsifying manifest observed; re-verify before promotion to Done |
| REQ-050 | WHEN source contains a focused valid CommonMark image destination fixture, the system shall style its source range without changing the source text. | COR-01 | Correction | — | COR-62 audit: no falsifying manifest observed; re-verify before promotion to Done |
| REQ-051 | WHILE applying lexical styling, the system shall keep every attributed range within the source bounds and leave the source string unchanged. | COR-01 | Done | `MarkdownHighlighter.tokens(for:)`, `SourceEditor.Coordinator.apply` | tests `attributeStylingLeavesStringUnchanged`, `rangesWithinBounds` |

## Image placement

### F · Input and representations

| ID | Requirement (EARS) | Inc | Status | Implemented in | Verified by |
| ---- | -------------------- | ----- | -------- | ---------------- | ------------- |
| REQ-060 | WHEN the user pastes or drops a supported image into a saved document, the system shall add it at the source selection captured immutably before asynchronous work begins. | COR-09 | Correction | — | COR-62 audit: no falsifying manifest observed; re-verify before promotion to Done |
| REQ-061 | WHEN a regular file is detected as PNG, JPEG, GIF, HEIC, or HEIF, the system shall copy its bytes unchanged without transcoding it. | COR-02 | Correction | — | COR-62 audit: no falsifying manifest observed; re-verify before promotion to Done |
| REQ-062 | WHEN a pasteboard item provides bitmap data but no supported file or file promise, the system shall encode the bitmap as PNG. | INC-03 | Correction | — | COR-62 audit: no falsifying manifest observed; re-verify before promotion to Done |
| REQ-063 | IF an item is corrupt, its detected representation is unsupported, or its claimed extension disagrees with an unsafe/unsupported representation, THEN the system shall reject the entire user action with a clear error. | COR-02 | Correction | — | COR-62 audit: no falsifying manifest observed; re-verify before promotion to Done |
| REQ-064 | WHEN paste or drag content contains meaningful non-image text, the system shall preserve native plain-text paste or drag behavior rather than consume it as an image action. | INC-03 | Correction | — | COR-62 audit: no falsifying manifest observed; re-verify before promotion to Done |

### G · Placement, naming, and source

| ID | Requirement (EARS) | Inc | Status | Implemented in | Verified by |
| ---- | -------------------- | ----- | -------- | ---------------- | ------------- |
| REQ-065 | WHEN adding an image, the system shall use a visible sibling `assets/` directory as a shared non-owned destination, creating it only when needed. | COR-02 | Correction | — | COR-62 audit: no falsifying manifest observed; re-verify before promotion to Done |
| REQ-066 | The system shall generate a lowercase ASCII filename that is safe across common macOS, Linux, and Windows filesystems and uses the detected representation’s canonical extension. | INC-03 | Correction | — | COR-62 audit: no falsifying manifest observed; re-verify before promotion to Done |
| REQ-067 | WHEN a destination filename already exists, the system shall reuse it only for byte-identical content and otherwise select a deterministic SHA-256-suffixed non-overwriting name using case-insensitive collision checks. | COR-02 | Correction | — | COR-62 audit: no falsifying manifest observed; re-verify before promotion to Done |
| REQ-068 | WHEN placement succeeds, the system shall insert standard relative Markdown `![](assets/name.ext)` without a title, dimensions, HTML, base64, percent-encoded filename, or private metadata. | INC-03 | Correction | — | COR-62 audit: no falsifying manifest observed; re-verify before promotion to Done |
| REQ-069 | WHEN one action contains multiple images, the system shall preserve provider order and insert their references separated by one line break as one undoable source replacement. | COR-02 / COR-08 | Correction | — | COR-62 audit: no falsifying manifest observed; re-verify before promotion to Done |

### H · Transaction, lifecycle, safety, and accessibility

| ID | Requirement (EARS) | Inc | Status | Implemented in | Verified by |
| ---- | -------------------- | ----- | -------- | ---------------- | ------------- |
| REQ-070 | WHEN adding one or more images, the system shall insert no source reference until every required destination file exists at its final contained path. | COR-02 | Correction | — | COR-62 audit: no falsifying manifest observed; re-verify before promotion to Done |
| REQ-071 | IF placement fails before source insertion, THEN the system shall remove only temporary and newly-created files proven to belong exclusively to that action, leaving all source, reused, and pre-existing files untouched. | COR-02 | Correction | — | COR-62 audit: no falsifying manifest observed; re-verify before promotion to Done |
| REQ-072 | IF asynchronous placement overlaps a subsequent edit at the tracked insertion range, THEN the system shall cancel source insertion rather than guess a new location. | COR-02 | Correction | — | COR-62 audit: no falsifying manifest observed; re-verify before promotion to Done |
| REQ-073 | WHEN inserting one image reference, the system shall use an empty image description and select it for immediate authoring without inventing alternative text from the filename. | INC-03 | Correction | — | COR-62 audit: no falsifying manifest observed; re-verify before promotion to Done |
| REQ-074 | WHEN image-reference insertion is undone or a reference is deleted, the system shall leave every asset file in place. | COR-02 | Correction | — | COR-62 audit: no falsifying manifest observed; re-verify before promotion to Done |
| REQ-075 | WHEN an untitled document receives an image action, the system shall complete the normal Save flow before creating `assets/`, canceling the action if Save is canceled. | COR-02 | Correction | — | COR-62 audit: no falsifying manifest observed; re-verify before promotion to Done |
| REQ-076 | WHEN Save As, rename, or move changes the document parent and a canonical local `assets/…` image reference (app-generated or manually authored) that resolved under the previous parent no longer resolves under the new parent, the system shall warn without silently copying, moving, or deleting companion files. | COR-02 / COR-21 | Correction | — | COR-62 audit: no falsifying manifest observed; re-verify before promotion to Done |
| REQ-077 | The system shall perform image inspection, hashing, promise receipt, and file I/O off the main actor while rejecting symlinks, aliases, packages, non-regular sources, symlinked destinations, and paths outside the resolved sibling `assets/` directory. | COR-02 | Correction | — | COR-62 audit: no falsifying manifest observed; re-verify before promotion to Done |

---

## Document ownership and lifecycle

| ID | Requirement (EARS) | Inc | Status | Implemented in | Verified by |
| ---- | -------------------- | ----- | -------- | ---------------- | ------------- |
| REQ-013 | The system shall use one `NSDocument` instance as the owner of canonical Markdown source, file location, source version, and undo history for each open document. | COR-04 | Correction | — | COR-62 audit: no falsifying manifest observed; re-verify before promotion to Done |
| REQ-014 | The system shall provide standard macOS New, Open, Save, Save As, autosave-in-place, Versions, tabs, and Recents behavior. | COR-04 | Correction | — | COR-62 audit: no falsifying manifest observed; re-verify before promotion to Done |
| REQ-015 | WHEN reading or writing a document, the system shall preserve the existing UTF-8, empty-file, BOM, CRLF, Unicode, invalid-UTF-8, zero-edit byte-fidelity, and ordinary-file/no-metadata contract through the default serialized `NSDocument` I/O model. | COR-09 | Correction | — | COR-62 audit: no falsifying manifest observed; re-verify before promotion to Done |
| REQ-016 | WHEN either editor adapter submits an expected source version and exact UTF-16 replacement, the document shall either advance its source version once and register document-owned undo/redo or return a typed stale/invalid/conflict refusal without mutation. | COR-04 / COR-05 | Done | `SourceMutation`, `HistoryPatch`, `MarkdownDocument.commitSourceMutation` | `SourceIntegrityCharacterizationTests`, existing document/COR-02 suites |
| REQ-017 | WHEN a dependent operation requires an untitled document to be saved, the document shall expose operation-scoped Save success, cancellation, or failure without discovering document ownership through a view. | COR-04 | Correction | — | COR-62 audit: no falsifying manifest observed; re-verify before promotion to Done |
| REQ-018 | The system shall keep mutable document/AppKit state on the main actor and send only immutable `Sendable` value snapshots to background work. | COR-09 | Done | `SourceSnapshot`; main-actor `MarkdownDocument`; `EditorSemanticWorker`; off-main parse/image snapshots | clean Swift 6 complete-concurrency build; `dataOfTypeSnapshotsCanonicalMainActorText`; `semanticWorkerRunsOffMainThread`; `workRunsOffMainQueue` |
| REQ-019 | WHEN Save As, rename, or move changes the document URL, the document shall advance its location generation and notify image placement through the editor-neutral selection/Save/URL/source-commit interface without changing exact-copy or failure semantics. | COR-04 | Correction | — | COR-62 audit: no falsifying manifest observed; re-verify before promotion to Done |

## Source and WYSIWYG editing

### E · Dialect, projection, and commands

| ID | Requirement (EARS) | Inc | Status | Implemented in | Verified by |
| ---- | -------------------- | ----- | -------- | ---------------- | ------------- |
| REQ-052 | The system shall provide persistent editable Source and WYSIWYG modes over the same canonical source, make WYSIWYG the default, expose a visible mode toggle that never changes source by itself, and keep one session-owned typed state per mode. | COR-09 | Correction | — | COR-62 audit: no falsifying manifest observed; re-verify before promotion to Done |
| REQ-053 | WHILE Source mode is active, the system shall show and edit literal Markdown characters using the existing lexical styling path. | INC-04 | Correction | — | COR-62 audit: no falsifying manifest observed; re-verify before promotion to Done |
| REQ-054 | WHILE WYSIWYG is active, the system shall parse the complete formal GFM 0.29 dialect through the pinned direct cmark-gfm configuration and render every supported semantic construct. | INC-04 / COR-06 | Correction | — | COR-62 audit: no falsifying manifest observed; re-verify before promotion to Done |
| REQ-055 | WHEN source is unsupported, malformed, or raw HTML, WYSIWYG shall show it literally as unformatted, non-executing, editable text and preserve it unchanged unless the user edits that text. | INC-04 / COR-06 | Correction | — | COR-62 audit: no falsifying manifest observed; re-verify before promotion to Done |
| REQ-056 | WYSIWYG attributed storage shall omit parsed Markdown control characters rather than hiding or making them transparent, while retaining literal punctuation that is content. | INC-04 / COR-06 | Correction | — | COR-62 audit: no falsifying manifest observed; re-verify before promotion to Done |
| REQ-057 | WHEN a WYSIWYG or toolbar action changes Markdown, the system shall preserve existing source spelling where safely patchable and otherwise regenerate only the smallest proven semantic unit—never the whole document. | COR-09 / COR-40 | Correction | — | COR-62 audit: no falsifying manifest observed; re-verify before promotion to Done |
| REQ-058 | The system shall provide the same formatting commands in both modes for paragraph/Heading 1–6, bold, italic, strikethrough, inline code, link, ordered/unordered/task list, block quote, and code block through an adaptive native window toolbar and matching menu routes; unsafe or ambiguous commands shall be disabled or refused without changing source. | INC-06 / COR-25 | Done | `EditorCommandController`; `SemanticPlannerGate.caretInsideContent`; `EditorToolbarController`; `EditorMenuCommands`; `LinkEditorSheet` | `CommandLivenessMatrixTests` (every command x both modes; a new command with undeclared behavior fails the build); `WYSIWYGListCommandRegressionTests`; `EditorCommandControllerTests`; `EditorToolbarConstructionTests`; `EditorMenuCommandTests`; `LinkEditorSheetTests` |
| REQ-059 | WHEN clipboard content offers rich and plain representations, the MVP shall paste its plain-text representation rather than infer Markdown formatting. | INC-04 | Correction | — | COR-62 audit: no falsifying manifest observed; re-verify before promotion to Done |
| REQ-113 | WHEN a semantic formatting command reports enabled availability for the current selection, the system shall apply it rather than refuse. | COR-26 / COR-33 / COR-38 / COR-40 | Correction | — | COR-62 audit: no falsifying manifest observed; re-verify before promotion to Done |

### F · Rich interaction, images, and tables

| ID | Requirement (EARS) | Inc | Status | Implemented in | Verified by |
| ---- | -------------------- | ----- | -------- | ---------------- | ------------- |
| REQ-078 | WHEN a supported task-list item is shown in WYSIWYG, its checkbox shall be directly operable and commit one exact task-marker source/presentation transaction. | COR-09 / COR-34 | Correction | — | COR-62 audit: no falsifying manifest observed; re-verify before promotion to Done |
| REQ-079 | WHEN a supported link is shown in WYSIWYG, it shall be directly clickable while its label remains editable through an explicit edit action. | INC-04 / COR-07 | Correction | — | COR-62 audit: no falsifying manifest observed; re-verify before promotion to Done |
| REQ-080 | WYSIWYG shall render and permit exact single-cell content edits in existing GFM tables, including literal escaped pipes, while refusing cross-cell/structural edits and offering no table insertion or row/column controls. | COR-09 | Correction | — | COR-62 audit: no falsifying manifest observed; re-verify before promotion to Done |
| REQ-081 | WHEN a local PNG, JPEG, GIF, HEIC, or HEIF reference resolves, WYSIWYG shall reject an encoded file above 256 MiB before full read, mapping, hashing, or decode, then decode a bounded display representation off-main without changing source, original bytes, metadata, or format and without fetching remote images. | COR-21 | Correction | — | COR-62 audit: no falsifying manifest observed; re-verify before promotion to Done |
| REQ-082 | The system shall provide “Add Image…” in both modes through the existing COR-02 placement transaction and shall not introduce an Import command or a second image pipeline. | INC-04 / COR-07 | Correction | — | COR-62 audit: no falsifying manifest observed; re-verify before promotion to Done |
| REQ-083 | WHEN an edit, toolbar action, task toggle, link change, or image insertion is undone/redone after switching modes, the document-owned undo manager shall restore canonical source and the exact source-domain selection while leaving assets intact. | COR-09 | Correction | — | COR-62 audit: no falsifying manifest observed; re-verify before promotion to Done |
| REQ-084 | WYSIWYG shall preserve native TextKit selection, marked text/IME, spelling, Find, keyboard editing, plain-text paste, and meaningful accessibility roles, labels, values, and image descriptions. | COR-09 | Correction | — | COR-62 audit: no falsifying manifest observed; re-verify before promotion to Done |
| REQ-085 | The system shall compute parser, source-index, authoritative projection, and image-decode work off-main and apply complete results only when source revision, location generation, and operation identity still match. | COR-09 | Correction | — | COR-62 audit: no falsifying manifest observed; re-verify before promotion to Done |
| REQ-086 | WHEN the user switches modes, each persistent editor shall restore its session-owned typed selection, affinity, and scroll state without changing source. | COR-09 | Correction | — | COR-62 audit: no falsifying manifest observed; re-verify before promotion to Done |
| REQ-087 | IF parsing, mapping, semantic translation, local-image resolution, or asynchronous work fails, THEN the system shall keep Source available, leave canonical source unchanged, and expose literal fallback, temporary WYSIWYG unavailability, or typed atomic refusal rather than guessing. | COR-09 | Correction | — | COR-62 audit: no falsifying manifest observed; re-verify before promotion to Done |

## Concurrency, evidence, and performance

| ID | Requirement (EARS) | Inc | Status | Implemented in | Verified by |
| ---- | -------------------- | ----- | -------- | ---------------- | ------------- |
| REQ-088 | The system shall compile the application and non-UI test targets in Debug and Release under Swift 6 complete concurrency checking without unsafe mutable-state isolation opt-outs or data-race warnings. | COR-18 | Done | `Scripts/check-concurrency-settings.sh`; Debug and Release xcodebuild test proofs | `Scripts/test-check-concurrency-settings.sh`; serial Debug and Release XCTest runs; falsifying mutation observed red |
| REQ-089 | The system shall provide privacy-safe mutation, presentation-transition, reconciliation, composition, update-origin, refusal, and image-cache instrumentation whose payload value type admits only numbers, booleans, and code-defined symbols, so that document/replacement/selected content, URLs, descriptions, filenames, and paths are unrepresentable rather than merely omitted. | COR-10 | Correction | — | COR-62 audit: no falsifying manifest observed; re-verify before promotion to Done |
| REQ-090 | WHILE operating on the approved performance corpus, the system shall satisfy p95 complete native-input callback below 8 ms at 100,000 UTF-16 units, p95 complete mode transition below 16 ms, p95 off-main parse/index/semantic-projection below 100 ms at 100,000 UTF-16 units, nonzero executed samples, zero dropped accepted input, zero stale-result applications, zero parser/image-decode work on the main actor, and a decoded-image cache no larger than 64 MiB. | COR-18 / COR-20 / COR-21 / COR-32 / COR-45 | Correction | `PerformanceSampler` complete callback boundary; `PresentationPatch` block-scoped application; `LatestParseScheduler`; `LocalImageDecoder` metadata gate; `LocalImageByteCache` | Focused Release run, macOS 27.0 (Build 26A5388g) / arm64, re-recorded 2026-08-02 after COR-32 restored the suite: 100,000 UTF-16 corpus `a8bdb967…2855e`, 10 warmups / 40 samples: complete native-input callback median 4.481 ms, **p95 4.871 ms** (<8); complete mode transition median 0.042 ms, p95 0.075 ms (<16); parse/index/projection corpus `75fbf8c9…83bb7b7`, 5 warmups / 20 samples, median 13.725 ms, p95 13.959 ms (<100). The earlier run (median 3.995 ms, p95 6.112 ms; mode p95 0.047 ms) is superseded, not contradicted. Non-gating 1M characterization: median 20.251 ms, p95 25.237 ms (prior run). Measurement condition: the callback gate must be run focused — executed concurrently with the full 320-test suite the same corpus measured p95 9.052 ms, which reflects contention for the main actor, not the edit path. `nativeInputCallbackSampleEnclosesStorageApplication`; `TextStorageApplierTests`; scheduler/resource suites; `Scripts/check-performance-suite.sh` (bounded wall-clock guard so a regression to "never completes" fails loudly) |
| REQ-091 | WHILE WYSIWYG is editable, every accepted native text replacement shall advance canonical source and the matching presented content/map synchronously before another input is accepted. | COR-09 | Correction | — | COR-62 audit: no falsifying manifest observed; re-verify before promotion to Done |
| REQ-092 | WHEN the user types Markdown punctuation in WYSIWYG, the system shall show it as literal visible content and encode the minimum safe formal-GFM source spelling without treating typing as a formatting command. | COR-09 | Correction | — | COR-62 audit: no falsifying manifest observed; re-verify before promotion to Done |
| REQ-093 | WHILE canonical source lacks a matching valid WYSIWYG presentation snapshot, the system shall keep Source available and make WYSIWYG unavailable for editing rather than expose stale rich content. | COR-09 | Correction | — | COR-62 audit: no falsifying manifest observed; re-verify before promotion to Done |
| REQ-094 | IF SwiftUI reconciles the persistent editor host, THEN the system shall neither publish a session change nor capture live native selection, affinity, or scroll state during that reconciliation, and reconciling an unchanged mode shall mutate no session state. | COR-10 | Correction | — | COR-62 audit: no falsifying manifest observed; re-verify before promotion to Done |
| REQ-095 | The system shall record diagnostics for one application run into one JSON Lines file under the user's Logs directory, beginning with a record identifying schema version, run identity, build, host kind (production or unit test), and process, and shall bound retained runs and per-file size. | COR-10 / COR-19 | Done | `DiagnosticLog` (`DiagnosticRunHeader`/`DiagnosticFileSink`/`pruneRuns`/`maximumRetainedRuns`/`maximumFileBytes`/`makeProcessFaultReporter`) | `runHeaderIdentifiesHostKindAndBuild`; `everyRecordIsOneParsableJSONLine`; `finishWritesTerminatingRecord`; `fileSizeCapIsBoundedAndRecorded`; `retentionRemovesOldestRuns`; `watchdogRecordsRemainOrderedAndCannotAppendAfterFinish`; `diagnosticsDirectoryHonoursEnvironmentOverride`; `everyTraceEventMapsToSymbolicPayload`; falsifying mutation observed red |
| REQ-096 | IF session state is published or live native state is captured during editor-host reconciliation, the editor-host update rate exceeds its sustained threshold, or the main actor does not respond within one second, THEN the system shall durably record a fault diagnostic identifying the condition while an unrecovered main-actor stall remains in progress, and shall collapse repeated non-fault events into a counted summary. | COR-19 | Done | `DiagnosticLog` (`record`/`collapse`/`repeatCollapseThreshold`/`makeProcessFaultReporter`); `HostUpdateMeter`; `EditorHost`; `ReconciliationInvariantTests` | `repeatedEventsCollapseWithCount`; `processFaultReporterWritesWhileMainActorIsBlocked`; `detachedSessionsReleaseAllSamplerRegistrations`; `samplerInvalidationIsIdempotentAndEmitsOneSummary`; `watchdogReportsStallWhileStillBlocked`; `reentrantPublicationRecordsFault`; `liveStateCaptureDuringReconciliationRecordsFault`; `hostUpdateStormRecordsFault`; falsifying mutation observed red |
| REQ-097 | The system shall write diagnostics to a directory named by the `MARKDOWN_EDITOR_DIAGNOSTICS_DIR` environment variable when it is set, so verification runs cannot read, prune, or pollute the user's production diagnostics. | COR-11 | Correction | — | COR-62 audit: no falsifying manifest observed; re-verify before promotion to Done |
| REQ-098 | WHEN process-level smoke verification runs, the system shall open a fixture document, settle within a bounded number of editor-host view updates, record no `error` or `fault` diagnostic, and write a terminating record. | COR-11 | Correction | — | COR-62 audit: no falsifying manifest observed; re-verify before promotion to Done |
| REQ-099 | The system shall define no instrumentation event that is never recorded, so that the event vocabulary is an accurate description of what a run can report. | COR-12 / COR-58 | Done | `Scripts/check-instrumentation-coverage.sh` observed-emission gate | `Scripts/test-check-instrumentation-coverage.sh`; final smoke and test-run logs; falsifying mutation observed red |
| REQ-100 | The system shall record the outcome of every document load, save, autosave, and revert, including failures, without recording file names, paths, or contents. | COR-13 | Done | `MarkdownDocument`: `read(from:ofType:)` (URL- and Data-based overrides); `revert(toContentsOf:ofType:)`; `installLoadedText`; `save(to:ofType:for:completionHandler:)`; `saveDocument()` cancellation fallback; `DocumentIOFailure` | tests `documentLoadFailureIsRecorded`, `documentLoadFailureForUnreadableURLIsRecorded`, `documentLoadThroughURLRecordsNoFailure`, `revertOfNeverBeforeLoadedDocumentIsClassifiedAsRevert`, `documentSaveFailureIsRecorded`, `documentSaveCancelledBeforeDestinationIsRecorded`, `documentIOTraceOmitsPaths`; smoke test asserts exactly one `documentLoaded`. Known gap documented in ENGINEERING §9: Save-panel cancellation on an untitled document through the plain Cmd+S/File-menu path (not this app's own `saveDocument()` bridge) is not recorded. |
| REQ-101 | The system shall record image-placement phase transitions, claim counts, byte counts, and typed failures for every paste, drag-and-drop, and Add Image operation, without recording file names, paths, providers, or image data. | COR-14 | Correction | — | COR-62 audit: no falsifying manifest observed; re-verify before promotion to Done |
| REQ-102 | WHEN the system presents a failure or warning to the user, it shall record a matching diagnostic at `error` or `warn` level. | COR-14 | Correction | — | COR-62 audit: no falsifying manifest observed; re-verify before promotion to Done |
| REQ-103 | The system shall record periodic bounded summary statistics for complete native-input callback, complete mode transition, parse/projection, image resolution, and authoritative application durations during ordinary use, without recording per-keystroke events, retaining closed sessions, or leaving timers alive after detach. | COR-19 / COR-20 | Done | `PerformanceSampler`; `EditorSession`; `EditorHost`; `WYSIWYGEditor`; split parse/image/application boundaries | `samplerComputesPercentilesFromKnownDistribution`; `samplerInvalidationIsIdempotentAndEmitsOneSummary`; `detachedSessionsReleaseAllSamplerRegistrations`; Release callback evidence; `TextStorageApplierTests` |
| REQ-104 | WHEN a build increment's closing sequence runs, process-level verification shall capture one screenshot of the application's own window over a fixture exercising broad Markdown and typography semantics, require the matching structured log to prove one document, one applied reconciliation, a later host update, bounded direct-plus-collapsed updates, performance samples, no fault, and clean termination, and expose the screenshot for mandatory human/agent visual review without capturing other on-screen content. | COR-18 | Done | `Scripts/smoke-screenshot.sh`; `Scripts/verify-smoke-log.py` | `VisualReviewFixtureTests`; final smoke-screenshot run and visual review of `/private/tmp/md-editor-smoke-final.png`; falsifying mutation observed red |
| REQ-114 | IF a referenced local image fails to resolve for display, THEN the system shall record its typed failure class without recording file names, paths, or image data. | COR-29 | Correction | — | COR-62 audit: no falsifying manifest observed; re-verify before promotion to Done |
| REQ-115 | WHEN process-level verification runs, it shall additionally exercise at least one accepted text insertion and one accepted semantic command and assert on the resulting structured records. | COR-29 | Correction | — | COR-62 audit: no falsifying manifest observed; re-verify before promotion to Done |
| REQ-116 | The system shall record a bounded periodic summary of WYSIWYG layout duration alongside its existing performance metrics. | COR-29 | Done | `PerformanceSampler.Metric.layoutApplication`; `WYSIWYGEditor.recordLayoutDuration`; `PerformanceSampler.budgetNanos` | `PerformanceBudgetTests` (every metric budgeted; budgets match the approved values); `Scripts/verify-smoke-log.py` metric allowlist |
| REQ-142 | WHEN process-level verification runs, the system shall reject a run that leaks memory, recording the leak count rather than silently passing. | COR-66 | Planned | — | — |
| REQ-117 | WHEN verification runs, the system shall prove that every test cited by a `Done` requirement executed and passed in that run. | COR-35 | Correction | — | COR-62 audit: no falsifying manifest observed; re-verify before promotion to Done |
| REQ-118 | The system shall map every automated test to at least one requirement or to a stated exemption, so that no test can fail unnoticed because nothing refers to it. | COR-35 | Correction | — | COR-62 audit: no falsifying manifest observed; re-verify before promotion to Done |

## Native reading surface and rewrite contracts

| ID | Requirement (EARS) | Inc | Status | Implemented in | Verified by |
| ---- | -------------------- | ----- | -------- | ---------------- | ------------- |
| REQ-105 | WHILE WYSIWYG presents supported Markdown, the system shall apply the approved editorial typography tokens—15-point system body, approximately 1.35× line height, maximum 720-point centered measure, minimum 28-point horizontal and 20-point vertical insets, approximately 0.7-em paragraph spacing, and the approved heading hierarchy—without changing source. | INC-05 | Done | `MarkdownTypography`; `AttributedPresentationBuilder`; `MarkdownWYSIWYGTextView` | `approvedTypographyTokensAreStable`; `typographyUsesAdaptiveSystemValues`; `headingSpacingIsLargerBeforeThanAfter`; `semanticBlocksAndTypographyDoNotChangeRenderedSource`; `readingColumnUsesMinimumInsetsAndMaximumMeasure`; `typographyTokensAndAppKitStayInTheirOwners` |
| REQ-106 | WHEN cmark identifies a soft break, hard break, or paragraph boundary, the system shall present respectively a space within the paragraph, a forced line break, or a paragraph-spacing boundary without inserting presentation-only characters into source. | INC-05 | Correction | — | COR-62 audit: no falsifying manifest observed; re-verify before promotion to Done |
| REQ-107 | WHILE WYSIWYG presents lists, tasks, blockquotes, code, tables, thematic breaks, images, or raw HTML, the system shall use the approved semantic block treatment including cumulative hanging indentation, checkbox-without-duplicate-bullet alignment, quote rule/inset, padded code block, content-sized table, full-measure separator, bounded aspect-preserving image, and non-executing literal HTML. | INC-05 / COR-36 / COR-37 | Done | `PresentationBlock`; `AttributedPresentationBuilder` (block `textBlocks` compose — `blockQuote` + `codeBlock` at `{0,10}` keep both rule and padded background, not wholesale replacement; quote depth accumulates via existing `backgroundColor == nil` count) | `ParagraphGeometryTests.fencedCodeBlockDoesNotSpaceItsOwnLinesApart`; `nestedParagraphKeepsItsListItemContentIndent` and `quoteNestedInAListItemKeepsRuleAndIndent` (laid-out line-fragment origins at narrow/default/wide widths, rehearsed failing at x=0 against the defect); `fencedCodeCarriesNoInlineRunBackground`; `missingImagePlaceholderIsLabelledAndNotTruncated`; `taskPresentationHasCheckboxWithoutDuplicateBullet`; `blockQuoteUsesLeadingRuleAndContentInset`; `codeBlockIsPaddedAdaptiveContainer`; `codeInsideQuoteComposesBothContainers` (quote rule + code background composed at identical range, control non-nil, rehearsed failing with backgroundColor nil); `nestedBlockQuotesComposeTheirRules` (depth via composed count); `listParagraphStyleUsesCumulativeHangingIndentation` |
| REQ-108 | WHEN a semantic formatting command is available, the system shall expose one window-scoped validated command through matching native menu and adaptive toolbar presentations and shall present link editing as a window-attached sheet. | INC-06 | Done | `EditorCommandController`; `EditorToolbarController`; `EditorMenuCommands`; `LinkEditorSheet`; `WindowAccessor` | `everyToolbarCommandItemCarriesAnImage`; `everyCommandSymbolResolvesOnThisPlatform`; `EditorCommandControllerTests`; `EditorToolbarConstructionTests`; `EditorMenuCommandTests`; `LinkEditorSheetTests` |
| REQ-139 | WHILE presenting any declared semantic color role in Light or Dark appearance, the system shall meet WCAG 2.1 contrast — 4.5:1 for normal text, 3:1 for text at least 18pt (or 14pt bold) and for non-text UI components. | COR-63 | Planned | — | — |
| REQ-140 | The system shall not adopt a text-scaling API it cannot verify honors the platform's Accessibility Text Size preference for third-party content, and shall record the researched platform boundary. | COR-64 | Planned | — | — |
| REQ-141 | The system shall introduce no motion or translucency without a paired Reduce Motion/Reduce Transparency accommodation, and shall express every color through the system's appearance-and-contrast-aware color catalog rather than a literal value. | COR-65 | Planned | — | — |
| REQ-109 | WHEN an ordinary WYSIWYG edit is accepted, the system shall apply one validated attributed presentation patch before returning from the native input callback and shall not rebuild or replace the complete attributed storage. | COR-20 / COR-23 / COR-34 | Done | `PresentationPatch`; `TextStorageApplier`; `AttributedPresentationBuilder.buildScoped`; `WYSIWYGEditor.Coordinator` | `ordinaryInsertionUsesOneBoundedRangePatch` and `attachmentLookupIsSplicedRatherThanRebuilt` (spy `NSTextStorage`: one bounded edit, zero full replacements); `newerSnapshotWithChangedTextUsesOneBoundedPatch` (including immediate/forced application); `hiddenDelimiterCommandRefreshesAttributesWithoutReplacing`, `headingAndLinkCommandsRefreshOnlyTheirSelectedBlock`, and `taskToggleRefreshesOnlyItsSemanticBlock` (only changed semantic blocks receive attributes); `attributeRefreshScopeTracksInsertionsAndRemovalsByPosition` (inserted/removed/changed elements stay bounded by position, not array index); `tableCellEditUsesOneBoundedPatch`; `committedCompositionUsesBoundedPatch`; malformed/stale/surrounding-text refusal proofs; `changedSpanKeepsUnchangedSuffixAtBoundary`; `forcedCurrentSnapshotDoesNotRecoverWithoutStorageDrift`; recovery, accepted-edit, and watchdog-isolation suites |
| REQ-110 | WHEN an editor session detaches or deinitializes, the system shall stop and release its performance sampler and timer after one bounded flush, and terminal diagnostic durability shall complete without waiting for main-actor cleanup. | COR-19 | Done | `EditorSession.detach`; `PerformanceSampler.invalidate`; `DiagnosticRunCoordinator`; `DiagnosticLog.finishSynchronously` | `detachedSessionsReleaseAllSamplerRegistrations`; `samplerInvalidationIsIdempotentAndEmitsOneSummary`; `synchronousFinishDoesNotWaitForMainActorCleanup` |
| REQ-111 | WHEN parse demand advances while another parse runs or waits, the system shall retain at most the running revision and newest pending revision and shall discard every older pending revision before source-copy or cmark work. | COR-21 | Done | `LatestParseScheduler`; `EditorSession.scheduleParse` | `keepsOnlyNewestPendingRevision`; `detachCancelsRunningAndPendingDemand`; reconciliation identity/cancellation paths |
| REQ-112 | The system shall derive canonical referenced-asset information from the pinned cmark parse tree and concrete source index rather than a regex or line-oriented secondary Markdown scanner. | COR-21 | Correction | — | COR-62 audit: no falsifying manifest observed; re-verify before promotion to Done |

## Measurement and performance evidence

| ID | Requirement (EARS) | Inc | Status | Implemented in | Verified by |
| ---- | -------------------- | ----- | -------- | ---------------- | ------------- |
| REQ-119 | Placeholder for future use. | — | Deferred | — | — |
| REQ-120 | Placeholder for future use. | — | Deferred | — | — |
| REQ-123 | The system shall count document parses, projection compiles, oracle validations, attributed builds, attributed characters written, storage full replacements, image decodes, bytes read, and main-thread blocked nanoseconds per unit of user intent, attributed to a closed scope set, and emitted as a diagnostic. | COR-44 | Done | `Markdown Editor/WorkLedger.swift`; production session routes | Tests: `acceptedEditRecordsItsWorkLedger`, `nestedWorkScopesAccumulateIntoTheEnclosingScope`, `ledgerRecordingOverheadIsBelowOnePercent`; full Debug XCTest and falsifying mutation observed red |
| REQ-124 | The system shall sample main-actor responsiveness histogram beside the one-second hang watchdog with a 16 ms p95 budget. | COR-44 | Done | `Markdown Editor/MainActorResponsivenessProbe.swift`; `PerformanceSampler` | Tests: `responsivenessProbeRecordsLatencyDistribution`, `aTwoHundredMillisecondMainActorBlockAppearsInTheLatencyDistribution`; full Debug XCTest and falsifying mutation observed red |
| REQ-125 | The system shall record frame-hitch statistics as milliseconds of hitch per observed second and longest frame, derived from the display link's real cadence. | COR-44 | Done | `Markdown Editor/FrameObserver.swift`; `PerformanceSampler` | Test: `frameBudgetFollowsTheDisplayLinkCadenceRatherThanAConstant`; full Debug XCTest and falsifying mutation observed red |
| REQ-126 | The system shall sample memory footprint as phys_footprint and peak via task_info and emit it as a numeric-only diagnostic. | COR-44 | Done | `Markdown Editor/MemoryFootprint.swift`; `PerformanceSampler` | Tests: `memoryFootprintRecordIsNumericOnly`, `memoryFootprintUsesKernelPeakField`; full Debug XCTest and falsifying mutation observed red |
| REQ-127 | The system shall provide a closed PerformanceCorpus enumeration whose shapes assert their own structure. | COR-45 | Done | `Markdown Editor/PerformanceCorpus.swift` | Tests: `corpusShapesProduceTheStructureTheyClaim`, `corpusTruncationPreservesUnitBoundaries`; full Debug XCTest and falsifying mutation observed red |
| REQ-128 | The system shall provide a process-level benchmark harness that drives the shipping binary through typing, table typing, commands, mode toggles, scrolling, undo storms and soak, writing a committed baseline. | COR-45 | Correction | — | The cited Release benchmark does not execute: `Scripts/benchmark.sh` stops at scenario 4 of 9 because `applyCommands` refuses all 40 of its commands, so no run has ever written the baseline this requirement promises. The baseline previously committed here was written by an earlier driver and is deleted rather than left standing as evidence. `benchmarkConfigurationPreservesEveryRequestedDimension` proves argument parsing, not the harness |

## Verification and process integrity

These requirements govern how the repository establishes that a claim is true. They exist because
six recorded times a proof obligation was discharged by a property of the source text rather than by
an observed execution; see `ROADMAP.md`, *the evidence floor*.

| ID | Requirement (EARS) | Inc | Status | Implemented in | Verified by |
| ---- | -------------------- | ----- | -------- | ---------------- | ------------- |
| REQ-133 | IF a push would place commits modifying Swift application or test sources onto the default branch, THEN the repository's push policy shall refuse that push. | COR-57 | Done | `Scripts/hooks/pre-push`; `Scripts/check-push-policy.sh` | `Scripts/test-check-push-policy.sh`; observed fixture run, including hook first-push and linked-worktree liveness; falsifying mutation replaces the Swift path matcher and is observed to turn the refusal proof green |
| REQ-134 | The repository's push policy shall refuse a push that is not accompanied by a gate receipt recording a passing gate run at the pushed head commit and tree. | COR-57 | Done | `Scripts/hooks/pre-push`; `Scripts/check-push-policy.sh`; `Scripts/write-gate-receipt.sh` | `Scripts/test-check-push-policy.sh`; observed fixture run, including stale/failed/missing receipt liveness; falsifying mutation removes head/tree equality and is observed to turn the stale-receipt proof green |
| REQ-135 | The system shall establish trace-vocabulary coverage from the diagnostic records emitted by an executed run, treating a case that is neither emitted nor listed in the reviewed exemption record as a failure. | COR-58 | Done | `Scripts/check-instrumentation-coverage.sh`; `docs/trace-coverage-exemptions.md` | `Scripts/test-check-instrumentation-coverage.sh`; observed process smoke plus DiagnosticLogTests union: 46 emitted, 0 exemptions; missing/empty/unknown logs and the COR-44 nil-receiver rehearsal failed |
| REQ-136 | The system shall derive delivered-increment status from the requirements a plan declares it delivers, admitting that status only when every such requirement is `Done` with its cited proofs observed passing in the same run. | COR-59 | Done | `Scripts/check-delivery-status.sh`; machine-readable `Delivers:` fields in `docs/plans/` and `docs/ROADMAP.md` | `Scripts/test-check-delivery-status.sh`; observed failure/liveness fixture matrix and fast/full gate wiring; falsifying mutation removes the active-row plan check and is observed to turn the active-without-plan fixture green |
| REQ-137 | The system shall admit a committed measurement only when it is machine-written and carries resolving host, operating-system, architecture, configuration, corpus-digest, sample-count and commit provenance. | COR-60 | Done | `Scripts/check-measurement-provenance.sh` (wired into `Scripts/fast-check.sh`) | `Scripts/test-check-measurement-provenance.sh`; observed failure fixtures for unexpanded shell constructs, missing provenance, placeholder fields, unknown commit and corpus mismatch, plus liveness |
| REQ-138 | The system shall require, for every `Done` requirement, a recorded mutation of production source that compiles and under which at least one of that requirement's cited proofs fails. | COR-61 / COR-62 | Planned | — | — |

---

*Deferred:* in-fence language syntax coloring, dialect profiles, rich-to-Markdown paste conversion,
table creation/structural controls, image sizing syntax, transcoding, metadata stripping, remote
images, automatic asset cleanup, and asset-aware Save Copy.

*Next free IDs: REQ-008 (A), REQ-023 (C), REQ-033 (D), REQ-143.*

*Reserved by approved, unimplemented plans — do not reassign:* REQ-129 (COR-51 accessibility
semantics), REQ-130 and REQ-131 (COR-53 macOS citizenship), REQ-132 (COR-54 fuzzing and real
corpora), REQ-139 (COR-63 contrast conformance), REQ-140 (COR-64 text-scaling boundary), REQ-141
(COR-65 reduced motion/transparency/increase contrast), REQ-142 (COR-66 leak-free process
verification). These numbers were advertised as free on 2026-08-10 because the plans reserving
REQ-129/130/131/132 had been deleted; the plans are restored and the numbers are not available.
