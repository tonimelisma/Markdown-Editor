# PLAN-0010 — INC-04 correction program

- **Program:** COR-05, COR-06, COR-07
- **Date:** 2026-07-25
- **Status:** COR-05 implemented; COR-06/07 require COR-08 integration correction
- **Research:** [RESEARCH-0008](../research/0008-inc04-correction-architecture-review.md)
- **Decision:** [ADR-0013](../decisions/0013-source-backed-rich-projection-and-semantic-edits.md)
- **Requirements:** REQ-011, REQ-016, REQ-018, REQ-032, REQ-052, REQ-054–REQ-058,
  REQ-078–REQ-090
- **Delivery:** Three sequential app-code worktree/branch/PR/squash-merge units

> This plan corrects the INC-04 implementation from first principles. It is not a collection of
> local patches. WYSIWYG remains delimiter-free and editable; Source remains literal Markdown;
> TextKit 1 and `NSDocument` remain; all link schemes remain directly openable; HEIC/HEIF is
> preserved exactly and never converted to JPEG; no UI or manual test is permitted.
>
> **Post-merge review:** COR-05 established the intended document/mutation foundation, and
> COR-06/07 established the intended projection and persistent-host components. Their integration
> still bypasses typed coordinate, planner, grouping, and placement boundaries in real editor
> paths. [PLAN-0011](0011-cor08-editor-integration-integrity.md) is authoritative for COR-08.
> The outcomes below remain the approved target, not proof that every claim is currently met.

## 1. Outcome

At program completion:

- one `NSDocument` owns canonical source, content-validated mutations, revision, dirty state, and
  unlimited multi-step undo/redo;
- Source and WYSIWYG are persistent native editors over that source;
- every rich character and insertion boundary has an exact source meaning, an explicit synthetic
  policy, or a typed refusal;
- WYSIWYG renders and edits complete formal GFM within the approved MVP surface;
- mode switching, marked text, selection, scroll, Find, spelling, tasks, links, tables, and images
  retain native behavior;
- local PNG/JPEG/GIF/HEIC/HEIF display is bounded, content-validated, off-main, and never changes
  the file;
- structured traces, projection oracles, mutation fixtures, and performance measurements prove
  these claims without logging user content.

## 2. Program invariants

1. Canonical Markdown is the only serialized content.
2. Opening, parsing, projecting, toggling, and zero-edit saving change no source byte.
3. Parsed Markdown control characters do not exist in WYSIWYG storage.
4. Unknown, malformed, and raw-HTML source remains literal, unformatted, editable,
   non-executing, and preserved.
5. Every edit commits one bounded, content-validated source mutation or refuses without mutation.
6. No source/projection coordinate is clamped, proportionally distributed, or guessed.
7. Existing source spelling is preserved when an exact patch exists. Otherwise regeneration is
   limited to the smallest approved semantic unit.
8. Both TextKit 1 editors live for the document-window lifetime; toggling changes visibility and
   focus, not ownership.
9. `NSTextView` owns transient marked text. Canonical source receives one completed composition
   mutation.
10. Async parse/projection/image results apply only to the exact source and location revisions
    that produced them.
11. Add Image, paste, and drag-and-drop are window-scoped entries into the one COR-02 placement
    transaction.
12. File-backed PNG/JPEG/GIF/HEIC/HEIF bytes and metadata are never changed; HEIC/HEIF is never
    converted to JPEG.
13. No document text, selected text, or complete local path is emitted by instrumentation.
14. No XCUITest, screen automation, snapshot UI test, or manual verification is added or run.

## 3. Module boundaries

The names below are the intended ownership boundaries. A developer may adjust filenames during
implementation only when the same responsibilities and dependency directions remain obvious.

### 3.1 Canonical mutation

`SourceMutation.swift`

```swift
struct SourceMutation: Sendable, Equatable {
    let id: UUID
    let expectedRevision: UInt64
    let range: NSRange
    let expectedText: String
    let replacement: String
    let selectionBefore: SourceSelection
    let selectionAfter: SourceSelection
    let actionName: String
    let grouping: MutationGrouping
}
```

`HistoryPatch.swift`

- stores the exact range, before/after content, selections, and action name;
- validates current affected content before undo or redo;
- creates its inverse from the mutation that actually committed;
- never stores an expected historical document revision.

`MarkdownDocument`

- remains the main-actor owner;
- exposes one public expected-revision mutation entry;
- uses one private apply method for user edits, undo, and redo;
- increments source revision exactly once for each successful edit, undo, or redo;
- lets `NSDocument`/`UndoManager` notifications drive dirty-state accounting;
- replaces `nonisolated(unsafe)` byte state with `Synchronization.Mutex`.

### 3.2 Source coordinates

`SourceCoordinateMap.swift`

- owns UTF-8 line/column, absolute UTF-8, Swift index, and UTF-16 conversion;
- treats cmark end positions as inclusive and converts them exactly;
- distinguishes scalar/character boundaries from arbitrary bytes;
- returns typed failures; never clamps.

`ProjectionSegment.swift`

```swift
enum ProjectionSegment: Sendable, Equatable {
    case source(
        projection: NSRange,
        source: NSRange,
        insertionBefore: Int,
        insertionAfter: Int
    )
    case synthetic(
        projection: NSRange,
        kind: SyntheticKind,
        insertion: SyntheticInsertionPolicy
    )
    case literalFallback(projection: NSRange, source: NSRange)
    case uneditable(projection: NSRange, reason: ProjectionRefusal)
}
```

`ProjectionCoordinateMap`

- answers source range for a rich selection;
- answers rich selection for a source selection;
- uses affinity at boundaries;
- returns `.ambiguous`, `.stale`, `.outOfBounds`, or `.unsupported` rather than a best guess.

### 3.3 Projection and editing

`ProjectionCompiler`

- combines cmark semantics with exact concrete source slices;
- emits rendered text, styles, paragraph/list/table descriptors, attachments, and typed segments;
- emits visible ordered/unordered markers and nesting;
- emits literal fallback runs for unsupported/raw-HTML regions;
- contains no AppKit object.

Split edit planners:

- `InlineEditPlanner`
- `BlockEditPlanner`
- `ListEditPlanner`
- `TableCellEditPlanner`
- `LinkEditPlanner`

Each planner:

1. accepts immutable source/tree/map/selection values;
2. computes one smallest-range candidate;
3. reparses the candidate document through the pinned parser;
4. checks the intended semantic postcondition;
5. returns one `SourceMutation` or one typed refusal.

No generic prefix-stripping loop or whole-document rich serializer remains.

### 3.4 Editor host and input

`EditorHostController`

- is one window-scoped AppKit controller;
- creates Source and WYSIWYG TextKit 1 views once;
- keeps both attached for its lifetime;
- toggles visibility and first responder;
- records/restores selection, affinity, scroll offset, and accepted revision per mode.

`EditorSelectionIntent`

- includes coordinate domain, source revision, range, and affinity;
- must resolve through `ProjectionCoordinateMap` before document mutation or image placement.

`WYSIWYGInputCoordinator`

- translates ordinary native changes through exact coordinates;
- owns a pure `CompositionState` value;
- lets marked text remain transient in the native storage;
- suppresses projection rebuild while marked text is active;
- commits one final source mutation at composition completion;
- refuses safely when its captured source revision is stale.

### 3.5 Images and document actions

`EditorActionRouter`

- is constructed per document window;
- injects the COR-02 placement operation into the session/toolbar;
- replaces `.editorAddImageClaims` and its `NotificationCenter` subscription.

`LocalImageDecoder`

- resolves only local relative references;
- asks Image I/O to allow only PNG, JPEG, GIF, HEIC, and HEIF;
- validates the detected UTI, dimensions, and decode result;
- creates a bounded `CGImage` off-main;
- returns the `Sendable` `CGImage` without encoding PNG or JPEG.

`LocalImageCache`

- keys by stable file identity/content freshness, display bound, and location generation;
- stores decoded cost as `bytesPerRow * height`;
- maintains deterministic LRU eviction;
- never exceeds 64 MiB.

## 4. Instrumentation and proof harness

### 4.1 `EditorTrace`

Add a privacy-safe event sink with an in-memory test implementation and an `OSLog` implementation.
Events contain identifiers and numeric metadata only:

- mutation requested/committed/refused;
- undo/redo registered/applied/refused;
- parse/index/projection started/completed/cancelled/discarded;
- coordinate mapping succeeded/refused;
- composition started/updated/committed/cancelled/refused;
- image decode/cache hit/miss/eviction;
- mode toggle and state restoration.

Do not include source text, replacement text, selected text, image description, URL string, or
complete path. Production logging uses privacy-safe signposts and fault summaries only.

### 4.2 `ProjectionOracle`

For every test projection:

1. rendered UTF-16 units are fully covered exactly once;
2. source-backed and fallback ranges lie within source;
3. source ranges never have negative length or overflow;
4. synthetic units have explicit insertion policies;
5. each projection boundary maps exactly or has a typed refusal;
6. source → rich → source preserves exact representable selections;
7. mapping a rich edit and applying it changes only the declared source range;
8. reparse of a generated edit satisfies the intended semantic predicate.

### 4.3 Corpora

Create checked-in, immutable fixtures:

- formal-GFM conformance corpus;
- one-character and empty-node source positions;
- ASCII, composed/decomposed Unicode, emoji, combining marks, entities, and escapes;
- LF, CRLF, BOM, tabs, and final-newline variants;
- nested emphasis/link/code combinations;
- ordered/unordered/task/nested/tight/loose lists;
- tables with alignments, escapes, and inline formatting;
- raw HTML, unsupported extensions, malformed-looking but valid Markdown, and literal fallback;
- distinct, licensed PNG/JPEG/GIF/HEIC/HEIF files with provenance and SHA-256 manifests.

Tests create document URLs in a unique temporary directory. They never write into checked-in
fixtures.

### 4.4 Golden and seeded tests

Each reviewed golden case records:

- exact input source;
- expected WYSIWYG plain string;
- expected segment kinds and source ranges;
- command and selection;
- exact expected output source;
- semantic postcondition.

Add a deterministic seeded generator that composes supported constructs and edit sequences.
Every failure prints the seed and minimal fixture identifier, not private user text.

### 4.5 Shadow comparison

During COR-06 only, a test/debug harness runs old and new projection engines over the same corpus
and records differences. The old result is not an oracle. Each difference is resolved by the
formal parser result, exact source slice, approved invariant, or reviewed golden case.

Delete the old engine and shadow harness after the new oracle passes and before COR-06 merges.

### 4.6 Performance evidence

Use optimized builds and record:

- hardware and OS;
- Xcode/Swift versions;
- source fixture and UTF-16 size;
- warm-up count and sample count;
- median, p95, maximum, and allocation/cache cost.

Gates:

| Metric | Gate |
|---|---|
| synchronous keystroke translation | p95 < 8 ms |
| mode toggle | p95 < 16 ms |
| parse + index + projection at 100,000 UTF-16 units | p95 < 100 ms off-main |
| stale async result application | 0 |
| parser/image decode on main actor | 0 |
| decoded image cache | ≤ 64 MiB |

A failed gate blocks the increment. Do not weaken or suppress the measurement without a new
approved discovery decision.

## 5. COR-05 — Source integrity and Swift 6

### Goal

Make canonical source mutation, undo/redo, byte snapshots, and concurrency boundaries trustworthy
before any projection work depends on them.

### Required failing characterization tests

Add these first and confirm that at least the marked current failures fail before production
changes:

1. Three independent edits, then three undos and three redos restore every intermediate source.
2. Undo/redo increments source revision once per successful history operation.
3. Undo validates current expected content and refuses a divergent history patch without
   mutation.
4. Typing groups coalesce according to the explicit grouping policy; toolbar/task/image actions
   remain discrete.
5. Undo/redo restores source selections across mode changes.
6. Dirty state returns to clean when history reaches the saved state and becomes dirty on redo.
7. Concurrent/background `data(ofType:)` reads a complete immutable snapshot.
8. Forced Swift 6 complete-concurrency build reproduces the current failure.

### Implementation checklist

- [x] Add `EditorTrace` event protocol and in-memory recorder.
- [x] Add `SourceMutation`, `MutationGrouping`, and `HistoryPatch`.
- [x] Add the one private document mutation application method.
- [x] Validate revision, range, and expected content before public commits.
- [x] Register undo using a dynamic history operation; never call the version-gated public API
      from an undo closure.
- [x] Define typing coalescing and discrete semantic-action grouping.
- [x] Remove duplicate manual `objectWillChange` sends where `@Published` already supplies them.
- [x] Replace `ioLock` plus `nonisolated(unsafe) ioText` with `Synchronization.Mutex`.
- [x] Remove the dead `MarkdownSourceIndex.stringIndex` loop.
- [x] Remove the custom actor-inferred `Result.flatMap`.
- [x] Replace constructed Save selectors with `#selector`.
- [x] Resolve every Swift 5 concurrency warning without `nonisolated(unsafe)`.
- [x] Make app and test code compile with `SWIFT_VERSION=6` and complete concurrency.
- [x] After the code is clean, land the project configuration enabling Swift 6 as prescribed by
      the repository Git workflow.

### COR-05 stop conditions

Do not continue to COR-06 unless:

- all history characterization tests pass;
- existing document and COR-02 tests pass;
- Swift 6 complete-concurrency app and test builds pass with no warnings;
- mutation traces show one revision and one history registration per operation;
- REQ-011, REQ-016, REQ-018, REQ-083, and REQ-088 are reconciled accurately.

## 6. COR-06 — Exact projection and semantic edits

### Goal

Replace heuristic rich/source mapping and broad string manipulation with a lossless projection
compiler and exact semantic planners.

### Required failing characterization tests

1. A one-character cmark node maps to one source character.
2. Invalid rich selections are refused, not clamped.
3. Emphasis/link/entity/escape projections map visible text to their exact source slices.
4. Synthetic paragraph breaks, list markers, tasks, thematic breaks, tables, and attachments have
   explicit insertion behavior.
5. Ordered and unordered lists retain visible marker and nesting semantics.
6. Nested block transformations do not strip unrelated quote/list/task prefixes.
7. Every formatting command covers all approved alternate spellings and Unicode boundaries.
8. Existing GFM table cell edits change only the intended cell content.

### Implementation checklist

- [x] Correct and exhaustively test inclusive cmark source positions.
- [x] Implement `SourceCoordinateMap`.
- [x] Implement typed `ProjectionSegment` and `ProjectionCoordinateMap`.
- [x] Implement concrete-source delimiter/content resolution.
- [x] Implement `ProjectionCompiler` for every formal-GFM node and fallback.
- [x] Add ordered/unordered marker and nesting descriptors.
- [x] Delete `sourceAnchors` and `sourceUTF16ForProjectionUnit`.
- [x] Delete proportional distribution and all mapping clamps.
- [x] Split `SemanticEditEngine` into the five approved planners.
- [x] Define command state and refusal reasons from semantic selection.
- [x] Reparse and validate every candidate mutation before commit.
- [x] Add reviewed golden cases and deterministic seeded cases.
- [x] Add `ProjectionOracle`.
- [x] Run temporary shadow comparison and adjudicate every difference.
- [x] Delete the old projection/edit engine and the shadow harness before merge.

### Command matrix

For Source and WYSIWYG, test every applicable command against:

- empty insertion;
- caret inside content;
- partial selection;
- complete semantic-node selection;
- selection crossing compatible nodes;
- selection crossing incompatible nodes;
- alternate valid delimiter/marker spelling;
- nested inline/block context;
- composed/decomposed Unicode;
- stale projection;
- unsupported/literal fallback;
- undo and redo.

Commands:

- Paragraph and Heading 1–6;
- bold, italic, strikethrough, inline code;
- link add/update/remove;
- ordered, unordered, and task list;
- indent/outdent and continuation/termination where already in scope;
- block quote and code block;
- task toggle;
- table-cell content;
- image description/destination.

### COR-06 stop conditions

Do not continue to COR-07 unless:

- every rich boundary is exact, explicit synthetic, or refused;
- no mapping clamp, proportional map, generic prefix stripper, or old engine remains;
- formal-GFM, oracle, golden, seeded, and existing Source/COR-02 suites pass;
- parse + index + projection p95 is below 100 ms at 100,000 UTF-16 units off-main;
- REQ-054–REQ-058, REQ-080, REQ-087, and REQ-089/090 are reconciled accurately.

## 7. COR-07 — Persistent native editing and interaction completion

### Goal

Connect the exact core to two persistent native editors and complete composition, window routing,
tasks, tables, accessibility, and local image display.

### Required failing characterization tests

1. Both TextKit 1 views retain object identity across repeated mode toggles.
2. Each mode restores its own selection, affinity, and scroll offset.
3. Source and WYSIWYG selection intents cannot be used in the wrong coordinate domain.
4. Marked-text updates remain transient and commit once at composition completion.
5. A stale composition refuses without changing canonical source.
6. Add Image in one window cannot reach another document window.
7. Task checkbox mouse, Space, Return, and accessibility press produce the same one-marker
   transaction.
8. HEIC and HEIF both decode from distinct fixtures while original hashes remain unchanged.
9. A supported extension with unsupported/corrupt content is rejected by detected UTI/decode.
10. Cache replacement after a file changes returns the new image and remains within 64 MiB.

### Implementation checklist

- [x] Add `EditorHostController` containing both persistent text views.
- [x] Replace the conditional SwiftUI mode branches with that one host.
- [x] Add mode-local selection, affinity, scroll, focus, and accepted-revision state.
- [x] Add typed `EditorSelectionIntent`.
- [x] Route every native edit and toolbar command through exact selection resolution.
- [x] Add pure `CompositionState` and `WYSIWYGInputCoordinator`.
- [x] Suppress rich rebuild during marked text and commit one final mutation.
- [x] Ensure native typing remains the synchronous path.
- [x] Replace `.editorAddImageClaims` and global notification subscription with
      `EditorActionRouter`.
- [x] Capture image insertion intent before asynchronous picker/placement work.
- [x] Implement task checkbox role, label, value, Space, Return, and accessibility press.
- [x] Preserve direct all-scheme link opening through the injected `NSWorkspace` action.
- [x] Render and edit table-cell content through exact cell mappings.
- [x] Implement allowed-UTI, bounded `CGImage` decode off-main.
- [x] Remove intermediate display PNG encoding and every JPEG destination path.
- [x] Implement content-aware, display-bound, location-aware, 64 MiB LRU image cache.
- [x] Add distinct licensed image fixtures and SHA-256 manifest.
- [x] Move every test-created file into a unique temporary directory.
- [x] Add signposts and run all performance gates.

### Native component verification

Instantiate AppKit controllers and text views directly in unit/integration tests. Verify state,
delegates, marked ranges, selections, attributed storage, accessibility properties/actions,
transactions, and traces. Do not launch the application or use XCUITest.

### COR-07 stop conditions

The program is complete only when:

- both editor objects remain alive across mode switches;
- selection/scroll/affinity and zero-change toggles pass;
- IME state-machine and direct TextKit component tests pass;
- multi-window action isolation passes;
- task/link/table/image/accessibility matrices pass;
- distinct PNG/JPEG/GIF/HEIC/HEIF hashes and decode tests pass;
- no image destination encoder is used for file-backed display;
- keystroke p95 < 8 ms, toggle p95 < 16 ms, cache ≤ 64 MiB, stale applications = 0, and
  parser/image main-actor work = 0;
- all affected requirements return to `Done` with real code and test/inherent anchors;
- no UI or manual test exists.

## 8. File-level retain/rewrite guide

### Retain and adapt

- `MarkdownDocumentData` byte codec and fixtures
- `MarkdownParser` pinned cmark ownership and conformance harness
- `MarkdownHighlighter` Source presentation path
- COR-02 placement state machine, storage, exact-copy, and rollback components
- `PastePolicy`
- theme values and basic rich attributed construction

### Replace

- `MarkdownDocument.commitSourceEdit` history implementation
- unsafe document byte snapshot storage
- `MarkdownSourceIndex` source-position and conversion implementation
- `MarkdownProjectionModel` coordinate arrays/builder
- `SemanticEditEngine`
- conditional mode host in `ContentView`
- WYSIWYG selection and native-change adapter
- global Add Image notification route
- task mouse-only interaction
- `LocalImageResolver` descriptor/cache implementation

### Split for maintainability

- `MarkdownProjectionModel.swift`
- `SemanticEditEngine.swift`
- `ImagePlacementController.swift` only if correction work must touch it; do not rewrite proven
  COR-02 state/storage logic merely to reduce line count.

File size alone is not a defect. Split when a file mixes independently testable responsibilities
or owns multiple reasons to change.

## 9. Pull request procedure for each correction

1. Create the required worktree and a repository-conforming fix branch such as
   `fix-cor-05-source-integrity`.
2. Add failing characterization tests first and record the pre-fix failure in the PR.
3. Implement only that correction's scope.
4. Run its focused tests, the full non-UI test target, strict Swift 6 build, trace/oracle gates,
   and applicable optimized performance measurements.
5. Reconcile requirements, roadmap, ADR/research/plan status on the branch before opening the PR.
6. Open the PR and automatically spawn the required independent review agent.
7. Have the reviewer inspect code, tests, trace evidence, plan, and requirements and post findings
   to the PR.
8. Rebase if needed; triage the last 10 PRs and every comment under CLAUDE.md §6a.
9. Squash-merge only after every finding has a root-cause fix and fixing commit reference.
10. Remove the worktree, local/remote branch, WIP, and owned stash.
11. Run the stale-work sweep and DoD.

## 10. Program rollback boundaries

- **COR-05:** mutation engine is internal behind the existing document interface. Revert the PR
  if history or strict-build gates fail.
- **COR-06:** new projection/edit engine is developed behind test/debug comparison until its
  cutover commit. Do not retain two production engines.
- **COR-07:** the persistent host replaces the conditional host only after direct component tests
  pass. The canonical source and COR-02 store remain unchanged.

No phase writes migration data or changes the Markdown file format.

## 11. Definition of Done

In addition to CLAUDE.md §9:

- [ ] every reproduced defect has a regression test;
- [ ] every architectural claim has a trace, oracle, test, inherent construction proof, or
      recorded optimized measurement;
- [ ] no test writes into the repository;
- [ ] no mapping guess or coordinate-domain conflation remains;
- [ ] no process-wide document action remains;
- [ ] no intermediate PNG/JPEG is encoded for file-backed image display;
- [ ] original HEIC/HEIF hashes are unchanged;
- [ ] Swift 6 complete-concurrency app and tests compile without warnings;
- [ ] all performance gates pass with reproducibility metadata;
- [ ] all affected docs and traceability anchors are current;
- [ ] old/temporary engines and shadow scaffolding are deleted;
- [ ] no UI or manual test was added or run.
