# RESEARCH-0007 — Document model and WYSIWYG architecture

- **Date:** 2026-07-24; executed 2026-07-25
- **For:** SPIKE-02 → possible document-model migration → INC-04
- **Type:** repository analysis + online research + planned native-API/POC investigation
- **Status:** Complete; recommendations approved 2026-07-25
- **Outcome:** The source-backed TextKit 1 design is viable. The user selected an
  `NSDocument`-owned canonical source, coherent formal GFM 0.29 through direct pinned cmark-gfm,
  minimum-unit normalization, literal raw HTML, plain-text MVP paste, existing-table editing,
  “Add Image…”, and the same formatting toolbar in both modes.

> Research docs capture *investigation*, not decisions. A decision that comes out of research
> is recorded separately as an [ADR](../decisions/). Spike/POC code is throwaway (per
> [ADR-0005](../decisions/0005-discovery-and-build-are-separate-units.md)).

## Questions

SPIKE-02 answered:

1. Should the value-type `FileDocument` remain the document model once two editable surfaces,
   explicit semantic source edits, cross-mode undo, parser snapshots, direct file-location
   awareness, and image transactions all need stable shared state?
2. Can a genuine no-markup WYSIWYG editor be implemented on the already-selected TextKit 1
   `NSTextView` while keeping the Markdown string authoritative?
3. Which coherent structural parser/dialect supplies source positions precise enough for
   targeted edits?
4. What source representation may change after a WYSIWYG edit, and how narrowly can that change
   be bounded?
5. How should the landed COR-02 image transaction obtain an active source selection and commit
   Markdown without depending on the source view being visible?
6. What measurable performance, selection, undo, accessibility, and graceful-degradation
   behavior is achievable without UI automation?

## Approved product surface

The following is settled product direction, not an option for the spike to water down:

- The app has two editable modes over the same Markdown source.
- **Source mode** displays the literal Markdown characters with live source styling.
- **WYSIWYG mode** displays the parsed content with Markdown control characters absent—not merely
  made transparent—and permits direct rich-text editing.
- A visible mode control toggles between Source and WYSIWYG; WYSIWYG is the default.
- WYSIWYG provides a formatting toolbar. A selection can be made bold, italic, or otherwise
  formatted through native commands.
- Task-list checkboxes are interactive.
- Links are directly clickable.
- Formatting keyboard shortcuts are desirable but may be staged after the toolbar.
- If source has no supported Markdown semantics, WYSIWYG does not claim or invent formatting for
  it. The text remains visible and preserved.

Requirements and exact acceptance language still belong to the Specify step after SPIKE-02
resolves the engineering unknowns.

## Verified repository baseline

### Canonical source and document lifecycle

`Markdown_EditorDocument` is currently a `FileDocument` value with one stored `String`.
`ContentView` receives a binding to that value. `MarkdownTextView.Coordinator.textDidChange`
copies the source view's entire string back through the binding. File serialization is
`Data(text.utf8)`, which preserves valid unedited UTF-8, BOM, and line endings.

This satisfies today's single-editor implementation, but ADR-0006 already records the accepted
costs: awkward undo, no autosave-timing control, and a revisit trigger for undo fidelity,
large-file behavior, or external-change handling.

### Editor engine and concurrency

ADR-0008 selected TextKit 1 after a macOS 27 POC found TextKit 2's dynamic rendering attributes
unreliable and its viewport behavior problematic. The current source view is explicitly created
with `NSTextView(usingTextLayoutManager: false)`.

ADR-0010 is the app-wide editing/concurrency contract:

- AppKit objects stay on the main actor.
- Secondary computation uses immutable snapshots and `Sendable` values off-main.
- Results carry a monotonically increasing version and are discarded when stale.
- Native insertion remains the synchronous keystroke path.
- Source highlighting is debounced and computed off-main for every document size (no
  length-based suspension).

SPIKE-02 must use TextKit 1 as its baseline. It does not reopen ADR-0008 merely because INC-04
needs rich text.

### Parser status

The current `MarkdownHighlighter` is deliberately lexical. ADR-0009 prohibits treating its regex
tokens as semantic parse results. No package dependency or structural parser exists.

ADR-0003 requires a WYSIWYG parser to be evaluated against exactly CommonMark 0.31.2 and formal
GFM 0.29-gfm. Unknown extensions must survive unchanged.

### COR-02 integration boundary

The merged COR-02 implementation replaces the defective image pipeline with a transaction state
machine and safe storage system, but its final main-actor controller still:

- holds a weak `MarkdownSourceTextView`;
- reads `selectedRange()` from that view;
- installs `InsertionRangeTracker` state on that view;
- finds the owning document for Save through the view;
- reads source from `textView.string`; and
- commits through `insertImageMarkdown`.

That is coherent for source-only editing. It is not an editor-neutral boundary for INC-04.
SPIKE-02 must preserve COR-02's transaction and storage invariants while determining how selection,
tracking, Save, and source commit move behind a shared document edit interface.

## Online findings

### macOS 27 document APIs

Apple's new SwiftUI `Document` protocol is reference-based and integrates with `@Observable`.
It provides direct document-URL access, coordinated file access, asynchronous readers/writers,
explicit actor boundaries, progress support, and manual undo registration.

Apple's migration guidance says `FileDocument` and `ReferenceFileDocument` remain available but
are no longer supported for new document types on macOS 27. The project already targets macOS
27.0. The new API is still marked beta, so adoption needs a real toolchain probe rather than a
paper decision.

`NSDocument` remains the mature fallback. It directly owns file location, Save completion,
autosave, Versions, window controllers, and undo, but would move substantially more document and
window infrastructure into AppKit.

### Text editing

`NSTextView` supports rich text, attachments, marked-text input, key bindings, selection,
spelling, paste, links, and undo. Those platform capabilities support a TextKit 1 WYSIWYG
prototype; they do not solve Markdown source mapping or source-preserving edit translation.

### Structural parser candidates

`cmark-gfm` is GitHub's C reference implementation for its bundled CommonMark core plus formal
GFM. It exposes an AST and node source positions and is fuzz-tested. The executed probe established
that it passes its bundled suite but not the newer CommonMark 0.31.2 suite, so its conformance
claim must be version-specific.

`swift-markdown` wraps cmark-gfm and provides Swift value-tree APIs, but its current parser
configuration attaches table, strikethrough, and task-list extensions—not the complete formal-GFM
extension set—and enables smart parsing unless explicitly disabled. Its README also states that
its effective dialect may change. It cannot be adopted as the semantic authority without closing
those gaps.

`tree-sitter-markdown` explicitly warns that its output contains inaccuracies and is not
recommended where correctness matters. It may be useful for editor highlighting but is not a
candidate for the semantic authority required by ADR-0003.

## Executed spike evidence

### Reproducibility

All POCs and downloaded fixtures lived under one temporary directory outside the repository. No
probe code or dependency entered an app/test target. The environment was:

- repository baseline `bd501a5`, with COR-02 at `1e4be12`;
- Xcode 27.0 beta build `27A5228h`;
- Swift 6.4 (`swiftlang-6.4.0.27.1`);
- macOS 27 SDK; and
- arm64 Apple silicon.

The repository's full non-UI `xcodebuild test` suite passed before the probes. No XCUITest target,
screen automation, or manual verification was used.

Pinned external revisions:

| Dependency or fixture | Revision |
|---|---|
| `github/cmark-gfm` 0.29.0.gfm.13 | `587a12bb54d95ac37241377e6ddc93ea0e45439b` |
| `swiftlang/swift-cmark` 0.7.1 | `5d9bdaa4228b381639fff09403e39a04926e2dbe` |
| `swiftlang/swift-markdown` 0.7.3 | `7d9a5ce307528578dfa777d505496bd5f544ad94` |
| CommonMark 0.31.2 specification | `9103e341a973013013bb1a80e13567007c5cef6f` |
| `commonmark/cmark` 0.31.2 | `eec0eeba6d31189fd828314576494566d539b1e3` |
| Public libheif image fixtures | `1a3583bcce77de6d3f8701c0758e3954863681ba` |

### A — document model

#### macOS 27 SwiftUI `Document`

A strict Swift 6 POC compiled a reference-type `@Observable` document conforming to the new
`Document`, `DocumentReader`, and `DocumentWriter` protocols. It proved:

- stable reference identity;
- direct observation of `URLDocumentConfiguration.fileURL`;
- a canonical string with byte-preserving `Data(text.utf8)` snapshots;
- invalid-UTF-8 refusal;
- `@concurrent`, `sending`, URL-based readers/writers;
- explicit source-edit and undo registration; and
- a new-style `DocumentGroup` scene.

The SDK surface also exposed an important limitation: it provides New/Open actions but no
operation-scoped Save action or Save result. An untitled dependent operation still cannot ask
SwiftUI to Save and learn success versus cancellation. The current Xcode 27 macOS document-app
template also still generates `FileDocument`, not the new protocol. The API works, but is new,
concurrency-annotation-heavy, and does not remove COR-02's hardest bridge.

#### `NSDocument`

A strict Swift 6 POC compiled an `NSDocument` subclass with:

- standard autosave-in-place;
- direct `fileURL`;
- document-owned `UndoManager`;
- completion-bearing dependent Save;
- synchronized read/write state; and
- byte-preserving Markdown data methods.

An executable component probe passed empty, LF, CRLF, BOM, and Unicode fixtures byte-for-byte,
rejected invalid UTF-8, and passed edit → undo → redo. No window or UI automation was needed.

#### Document-model recommendation

For this macOS-only app, the evidence ranks:

1. **Migrate to `NSDocument` before INC-04.** It is the only candidate that owns canonical source,
   file location, Save completion, autosave/Versions, and undo without retaining a second hidden
   document authority or discovering the owner through an editor view.
2. Retain `FileDocument` if migration cost is rejected. It works, but the value binding, Save
   bridge, and view-owned undo become permanent cross-mode infrastructure.
3. Do not migrate to the macOS 27 SwiftUI `Document` yet. Re-evaluate after the API is non-beta or
   exposes operation-scoped Save; its present benefits do not remove enough complexity.
4. Do not adopt deprecated `ReferenceFileDocument`.

This is a proposed revision to ADR-0006, not an accepted decision.

#### Migration impact

If approved, the separate migration would replace `Markdown_EditorDocument` and the SwiftUI
`DocumentGroup` ownership path with an `NSDocument` subclass, AppKit document controller/window
plumbing, and a narrow SwiftUI editor host. `ContentView`, `MarkdownTextView`, and
`ImagePlacementController` would receive a document edit interface rather than a value binding or
text-view-derived owner. COR-02's storage state machine and file operations would not change.

The actor boundary would be document-owned: mutable source and undo on the main actor; immutable
read/write, parse, and projection snapshots sent to background work. Rollback is straightforward
only before INC-04 depends on the new interface, which is why the migration must be its own build.
Retaining `FileDocument` has zero migration cost but makes the Save bridge, view-owned undo, and
value rebinding permanent infrastructure.

### B — parser conformance and source mapping

#### The approved dialect label has no conforming candidate

Direct `cmark-gfm`/`swift-cmark` was built with smart punctuation disabled and only these formal
extensions enabled:

- table;
- strikethrough;
- autolink;
- task list; and
- tag filter.

Results:

| Suite | Result |
|---|---|
| cmark-gfm bundled core suite | 670 passed, 0 failed |
| Selected formal-GFM extension sections | 15 passed, 0 failed, 15 unrelated cases skipped |
| Official CommonMark 0.31.2 suite | **641 passed, 11 failed** |

The CommonMark 0.31.2 failures are example 28 (numeric character reference) and examples 354,
389, 417, 425–427, 464–466, and 468 (newer emphasis/strong-emphasis behavior).

This is not a wrapper bug: formal GFM 0.29 is based on an older CommonMark core.
`swift-markdown` embeds `swift-cmark`/cmark-gfm 0.29.0.gfm.13, so it inherits the same mismatch.
It also attaches table, strikethrough, and task-list extensions but omits formal GFM autolink and
tag-filter attachment, enables smart punctuation unless explicitly disabled, and enables table
spans. It is not the approved dialect authority.

Combining upstream cmark 0.31.2 with cmark-gfm's extension framework is not a narrow wrapper. A
source-tree comparison spans 59 core files and about 20,000 inserted/8,800 removed lines. Owning
that private parser fork would violate the minimum-fuss, maximum-compatibility objective.

#### Source positions

The direct cmark-gfm AST reports one-based UTF-8 byte columns. A value-only `SourceIndex` POC
mapped those positions to:

- absolute UTF-8 ranges;
- Swift `String.Index` boundaries; and
- UTF-16 `NSRange` values used by TextKit.

Representative nodes for headings, emphasis, strong, links, images, task items, and tables mapped
to exact original source slices. Bounds/round-trip fixtures passed for ASCII, multibyte text,
emoji, regional indicators, composed/decomposed marks, BOM, LF/CRLF, tabs, multiline links,
variable code delimiters, and malformed delimiters.

Known limitation: the table delimiter/alignment row is structural parser input but has no AST
node or source span. Cell content can be patched locally; changing columns/alignment requires a
table-level source transaction.

#### Parser decision options

1. **Formal GFM 0.29 as one coherent dialect — recommended.** Pin direct cmark-gfm through the
   maintained Swift C package, enable exactly the five formal extensions, disable smart/extra
   options, wrap only value AST/source-position data, and gate every update with both suites.
   This maximizes real GitHub compatibility and avoids a house dialect.
2. **Keep the hybrid label and own a cmark fork — reject.** It can theoretically combine the
   standards, but creates a large security/correctness maintenance obligation.
3. **CommonMark 0.31.2 without GFM — reject for this product.** It loses approved tables, tasks,
   strikethrough, extended autolinks, and tag filtering.
4. **Continue calling cmark-gfm 0.29 “CommonMark 0.31.2 + formal GFM” — reject.** The executable
   conformance result proves that label false.

Choosing option 1 revises ADR-0003 and the affected requirements. It needs explicit approval.
The cmark-gfm core is BSD-2-Clause, with separately identified permissive MIT-derived files.
Production adoption would pin the exact Swift package revision and rerun both the bundled
formal-GFM suite and the chosen core-dialect suite on every update.

### C — TextKit 1 rich projection

A strict Swift 6 component POC built a separate attributed storage containing rendered content
only. Automated inspection proved:

- headings, emphasis, strong, strikethrough, inline code, and links use attributes;
- parsed Markdown delimiters are absent from `NSTextStorage.string`;
- task controls and images occupy attachment characters rather than hidden source syntax;
- link destinations are `.link` attributes;
- unsupported `==mark==` and malformed `*open` remain literal and unformatted;
- native replacement, selection, undo/redo, and marked-text composition work;
- task/image attachment cells are supported by TextKit 1; and
- a 2×2 native `NSTextTable`/`NSTextTableBlock` projection works.

There was no TextKit 1 failure that justifies reopening ADR-0008 or adopting TextKit 2.

The correct boundary remains:

- an off-main, `Sendable` projection model of strings, semantic runs, source mappings, and
  attachment descriptors; then
- main-actor construction/application of `NSAttributedString`, fonts, colors, table blocks,
  attachment cells, and image objects.

### D — semantic edits, versioning, and undo

A value-source transaction POC proved:

- exact UTF-16 range replacement;
- untouched-source preservation;
- source-version advancement exactly once;
- typed stale-version and invalid-range refusal; and
- local delimiter insertion without document serialization.

An editor-neutral document-session POC then proved:

- Source and WYSIWYG capture source insertion intents through the same interface;
- non-overlapping earlier edits translate a tracked insertion range;
- overlapping edits cancel rather than guess;
- image Markdown commits as one source transaction;
- the document-owned undo manager undoes/redoes the reference in either mode; and
- dependent Save success/cancellation is injected independently of an editor view.

The production design should therefore have a document-owned `SourceTransactionEngine` and one
undo manager. Neither text view writes the other view or owns canonical source.

Formatting locality is not uniform:

- inline text/format/link/task/image-description edits can usually patch exact source spans;
- heading/list/quote/code conversions can patch one block;
- table structure/alignment changes require regenerating one table; and
- ambiguous delimiter content must choose a safe delimiter or return a typed refusal.

No whole-document reserialization is justified.

### E — COR-02 and images

The editor-neutral seam can replace COR-02's view dependency without replacing its validated
storage transaction. It supplies document URL/generation, a captured source intent, current
source for move warnings, dependent Save, one source commit/undo group, and post-commit selection.

Image rendering probes used generated PNG/JPEG/GIF/HEIC plus public libheif HEIC/HEIF fixtures:

| Fixture | Decode | Byte identity |
|---|---|---|
| generated PNG/JPEG/GIF | passed | unchanged |
| generated `public.heic` | passed | unchanged |
| public `example.heic` (1280×854) | passed | unchanged |
| public HEVC `hevc32.heif` | passed | unchanged |
| public JPEG-in-HEIF `jpeg32.heif` | passed | unchanged |

ImageIO could not synthesize a `public.heif` fixture on this machine, but it decoded both public
HEIF variants. Rendering used read-only `CGImageSource`; no image destination, transcoding,
metadata rewrite, or HEIC/HEIF-to-JPEG path exists.

### F — mode host and commands

No toolbar UI was built. The architecture probe established the command boundary:

- keep persistent Source and WYSIWYG TextKit 1 views;
- preserve per-mode logical selection/scroll state;
- route toolbar/menu actions to typed source-edit intents;
- expose command enabled/state from the semantic selection; and
- update the inactive view only from accepted canonical-source versions.

The toolbar product choices were resolved after the decision-enabling probes; accepted outcomes
are recorded below.

### G — performance, concurrency, and failure behavior

Release-build measurements on generated list/link/formatting-heavy input:

| Input | Parse + AST/source-map median | p95 | Source-index median | p95 |
|---:|---:|---:|---:|---:|
| 954 bytes | 0.070 ms | 0.094 ms | 0.005 ms | 0.006 ms |
| 9,964 bytes | 0.686 ms | 0.763 ms | 0.045 ms | 0.046 ms |
| 99,958 bytes | 4.809 ms | 6.471 ms | 0.347 ms | 0.394 ms |
| 999,951 bytes | 53.273 ms | 58.486 ms | 3.388 ms | 3.392 ms |

TextKit 1 attributed-storage replacement medians were 0.124 ms at 990 UTF-16 units, 0.982 ms at
9,990, and 0.561 ms at 99,990. These measure storage replacement, not glyph layout; no UI/layout
claim is inferred from them.

Eight parallel parser/source-map runs completed off-main with identical results. cmark parsing is
synchronous and does not cooperatively cancel mid-parse; cancellation is checked before/after and
stale versions are discarded. A full reparse is therefore reasonable initially—approximately
5 ms at the existing 100,000-unit boundary—without introducing a piece table or incremental
parser. The 1 MB result confirms that parsing must remain off-main and version-gated.

The repeated harness, including 1 MB cases, peaked at about 86.6 MB process footprint. That is a
whole-process upper observation, not per-document retained memory.

Deterministic failure outcomes proven or fixed by construction:

| Failure | Outcome |
|---|---|
| Unsupported/malformed syntax | literal, unformatted projection; source unchanged |
| Invalid source mapping/selection | typed refusal |
| Stale parse/edit version | discard/refuse |
| Overlapping insertion intent | cancel source commit |
| Missing/corrupt image | placeholder/error; source and bytes unchanged |
| Missing document URL or cancelled Save | dependent operation stops |
| Mode switch during async work | intent remains source-based; stale result rejected |
| Parser task cancellation | pre/post check; synchronous parse itself is not interruptible |

### Selected-design follow-up evidence

After the user approved all eight recommendations, bounded throwaway probes completed the
decision-dependent matrix:

- the complete formal-GFM specification with
  `CMARK_OPT_STRIKETHROUGH_DOUBLE_TILDE`: **670 passed, 0 failed**;
- a focused strict-strikethrough check rendered `~single~` literally and `~~double~~` as
  strikethrough, correcting the earlier research's mistaken single-tilde interpretation;
- cmark-gfm's pathological suite: **21 passed, 0 errored, 0 ignored**;
- 17 local/structural edit fixtures covering alternate inline spellings, links, headings, lists,
  quotes, code, tasks, table cell/table scope, and image fields;
- typed stale, invalid-range, ambiguous-delimiter, and overlap refusal;
- complete-dialect TextKit 1 rich substrate with parsed delimiters absent and raw
  HTML/unsupported/malformed source literal;
- persistent Source/WYSIWYG views, WYSIWYG default state, mode selection preservation, IME,
  spelling, Find, plain-text rich paste, and undo;
- direct link action, task action, image selection, checkbox role/label/value, and 2×2 native
  table blocks;
- Source typing, WYSIWYG formatting, task, link, and image undo/redo across mode switches,
  including retained asset and post-undo stale-snapshot rejection;
- HEIC plus HEVC-in-HEIF and JPEG-in-HEIF bounded off-main thumbnail decode with byte hashes
  unchanged and no encode/transcode path; and
- corrupt, oversize, remote, stale, moved-document-resolution, and bounded-cache-eviction
  outcomes.

Additional selected-design release measurements:

| Operation | Median | p95 |
|---|---:|---:|
| local edit translation | 0.000708 ms | 0.000750 ms |
| complete representative projection application | 0.097 ms | 0.123 ms |
| 1280×854 HEIC bounded thumbnail decode | 10.900 ms | 12.211 ms |

The projection application is attributed-storage work, not a glyph/layout benchmark. The image
measurement includes detached scheduling and decode. No threshold is inferred.

## Architecture options

### Document model

| Option | Fit | Main risks | Preliminary assessment |
|---|---|---|---|
| Keep `FileDocument` | Lowest migration cost; existing byte-fidelity tests | Value rebinding, view-owned mutations, bespoke Save bridge, awkward cross-mode undo and URL lifecycle | Viable fallback, but preserves the current architectural seams |
| Adopt macOS 27 SwiftUI `Document` | Stable reference identity, `@Observable`, direct coordinated URL access, async I/O, explicit undo | Beta API; no dependent-Save action/result; migration without removing the hardest bridge | Reassess after API maturity; do not migrate now |
| Adopt `NSDocument` | Mature Save/URL/undo/autosave/Versions control | More AppKit document/window boilerplate; explicit SwiftUI hosting | **Selected for the macOS-only blank-slate architecture** |
| Adopt `ReferenceFileDocument` | Reference identity within older SwiftUI model | Deprecated for new macOS 27 document types; synchronous `FileWrapper` model | Reject |

### WYSIWYG representation

| Option | Source fidelity | Native editing | Assessment |
|---|---|---|---|
| Canonical Markdown + separate rich projection + targeted source edits | Preserves untouched source and unknown syntax | Uses `NSTextView`; owns mapping/edit translation | **Only option that satisfies the approved product and invariants** |
| Make AST/rich text canonical and serialize on Save | Normalizes whole documents and may discard unfamiliar syntax | Straightforward rich editing | Reject: violates INV-2/INV-7 |
| Keep literal source storage and hide/substitute delimiters at layout time | One storage, but complex character/glyph mismatch | Caret, selection, IME, attachment, and accessibility hazards | Reject |
| Web view/contenteditable | HTML-oriented model, conversion/normalization risk | Non-native undo, spelling, selection, accessibility, and file behavior | Reject |

The recommended projection is genuinely rich: its storage contains rendered characters and
attachments, not invisible Markdown delimiters. A separate mapping relates projection ranges to
source ranges.

### Transient versus persistent state

A blank-slate design should separate:

- **`MarkdownDocument`** — persistent canonical source, source version, file configuration,
  read/write snapshots, source-edit application, and undo registration; from
- **`EditorSession`** — active mode, per-mode selection/scroll state, parse task, current AST,
  projection mappings, and display-only resource cache.

Mode, selection, parse trees, and image caches must not become hidden document metadata.

## Accepted architecture

Approved 2026-07-25:

1. Migrate from `FileDocument` to an `NSDocument`-owned canonical source as a separate
   prerequisite build.
2. Use formal GFM 0.29 as one coherent dialect and pin direct cmark-gfm through `swift-cmark`;
   do not own a hybrid parser fork or use `swift-markdown` as semantic authority.
3. Keep TextKit 1 with separate editable Source and genuinely rich WYSIWYG storages.
4. Put parsing, source indexing, and projection-model computation off-main; initially use full
   reparses plus local mapping deltas and source-version rejection.
5. Centralize edits, mode-independent insertion intents, and undo in a document-owned source
   transaction engine.
6. Adapt only COR-02's selection/Save/commit boundary; retain its storage transaction unchanged.
7. Perform the document migration before specifying/building INC-04. Do not combine them.

## Approved product decisions

### Architecture

1. **Document model:** migrate to `NSDocument` in a separate COR-04 before INC-04.
2. **Dialect:** coherent formal GFM 0.29 through direct pinned cmark-gfm; no hybrid fork.

The document choice is independent of syntax. The dialect choice is not cosmetic: formal GFM
0.29 gives one executable standard and GitHub's parser; the hybrid requires maintaining a large
private parser indefinitely.

### Product policies

1. **Normalization boundary.** Preserve exact spelling when a safe patch exists;
   otherwise regenerate only the smallest semantic unit—inline node, block, or table—and never
   the whole document. Example: editing a table cell patches that cell; changing columns rewrites
   that table only. `_word_` stays underscore emphasis when its text changes; converting a Setext
   heading to Heading 3 rewrites that heading block as `### ...`; changing table alignment rewrites
   only that table's delimiter row.
2. **Raw HTML.** Display literal HTML source as unformatted, non-executing,
   editable text in WYSIWYG. Rendering it would require an HTML engine/security policy and could
   hide source that cannot be round-tripped safely.
3. **Rich paste.** Paste plain text for MVP; add rich conversion only as a later independently
   specified feature. Pasting visually bold “Hello” therefore inserts `Hello`, not guessed
   `**Hello**`; a later converter can define exactly which styles and links are accepted.
4. **Tables.** Render and edit existing GFM tables in MVP, including cell-content
   edits, but defer an Insert Table workflow and structural row/column controls.
5. **Image command surface.** Add “Add Image…” using the same COR-02 transaction and a file
   picker; it is placement, not document Import, and HEIC/HEIF remains exact-copy with no JPEG
   generation.
6. **Source-mode toolbar.** Expose the same semantic formatting commands in both
   modes. In Source, commands modify the literal selection through the same transaction engine;
   unsafe/ambiguous commands are disabled or return a typed refusal.

## Sources

- [Apple — Creating a document-based app](https://developer.apple.com/documentation/swiftui/creating-a-document-based-app)
- [Apple — Updating your document-based app](https://developer.apple.com/documentation/swiftui/updating-your-document-based-app)
- [Apple — SwiftUI `Document`](https://developer.apple.com/documentation/swiftui/document)
- [Apple — `NSDocument`](https://developer.apple.com/documentation/appkit/nsdocument)
- [Apple — `NSTextView`](https://developer.apple.com/documentation/appkit/nstextview)
- [GitHub — cmark-gfm](https://github.com/github/cmark-gfm)
- [Pinned cmark-gfm 0.29.0.gfm.13 source](https://github.com/github/cmark-gfm/tree/587a12bb54d95ac37241377e6ddc93ea0e45439b)
- [Pinned swift-cmark 0.7.1 source](https://github.com/swiftlang/swift-cmark/tree/5d9bdaa4228b381639fff09403e39a04926e2dbe)
- [Swift — swift-markdown](https://github.com/swiftlang/swift-markdown)
- [Pinned swift-markdown parser configuration](https://github.com/swiftlang/swift-markdown/blob/7d9a5ce307528578dfa777d505496bd5f544ad94/Sources/Markdown/Parser/CommonMarkConverter.swift)
- [tree-sitter-markdown goals and accuracy warning](https://github.com/tree-sitter-grammars/tree-sitter-markdown/blob/split_parser/README.md)
- [CommonMark 0.31.2](https://spec.commonmark.org/0.31.2/)
- [GitHub Flavored Markdown 0.29-gfm](https://github.github.com/gfm/)
- [Pinned libheif image fixtures](https://github.com/strukturag/libheif/tree/1a3583bcce77de6d3f8701c0758e3954863681ba/examples)
