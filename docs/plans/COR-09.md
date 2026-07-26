# COR-09 — Editor-state and projection consistency

- **Status:** Approved; not implemented
- **Approved:** 2026-07-25
- **Requirements:** REQ-015, REQ-018, REQ-052, REQ-057, REQ-058, REQ-060, REQ-078,
  REQ-080, REQ-083–REQ-087, REQ-089–REQ-093
- **Architecture:** ARC-001–ARC-014
- **Research:** `../research/macos-editor-platform.md`,
  `../research/markdown-projection-and-compatibility.md`

## Goal

Make Source and WYSIWYG reliable native editors over one canonical Markdown document. Consecutive
accepted input must never be dropped because parsing is pending; source and the editable
WYSIWYG presentation must never represent different revisions. Remove duplicate selection/view
state, compatibility coordinate routes, and unnecessary document-I/O synchronization rather than
patching them.

The finished build retains `NSDocument`, TextKit 1, two persistent editors, pinned cmark-gfm,
formal GFM, the source mutation/history engine, and the image-placement transaction.

## Architecture impact

**No architecture change.** Implement the current contracts in `../ENGINEERING.md`.

If implementation evidence contradicts an `ARC-###` invariant, stop the build. Record a
reproducible counterexample, research options, and obtain approval before changing specs or
production direction. Do not add a compatibility shim.

## Definition of the defect

The current WYSIWYG delegate commits the source mutation, returns `true` to let TextKit apply an
optimistic visible edit, but leaves `EditorSession.projection` on the previous revision until a
full off-main parse finishes. A second keystroke is therefore translated against stale mapping
and can be refused.

Related structural defects:

- `ModeViewState` and `EditorViewState` both model mode-local selection/scroll.
- `SemanticSelection`, `EditorSelectionIntent`, raw domain enums, and typed coordinates overlap.
- `ProjectionRevision` is numerically derived from `SourceRevision` without identifying the
  complete presented snapshot.
- selection callbacks cannot reliably distinguish native input from programmatic restoration.
- normalized entity/code/table content is sometimes identity-mapped or made broadly uneditable
  without a concrete inverse rule.
- the document maintains `DocumentIOText` and `DocumentLoadGate` despite serialized
  `NSDocument` I/O defaults.
- pending selection is stored in the document even though it is window/editor presentation state.
- image intent can be rebuilt from mutable live state after asynchronous work begins.

## Non-negotiable implementation rules

1. Do not add UI tests.
2. Do not retain deprecated overloads, type aliases, raw coordinate domains, or dual paths.
3. Do not make an AST, projection, attributed string, or view canonical.
4. Do not run full parsing synchronously between ordinary keystrokes.
5. Do not expose stale WYSIWYG as editable.
6. Do not guess, clamp, proportionally distribute, or partially apply an edit.
7. Do not transcode file-backed HEIC/HEIF or create an intermediate JPEG.
8. Do not weaken Swift 6 complete concurrency checking or silence warnings.
9. Do not claim framework behavior as inherent when custom code intercepts it.
10. Do not mark a requirement Done until its adapter path—not merely a pure helper—has
    discriminating automated evidence.

## Target code shape

### New or replacement types

Names may be adjusted only to match Swift conventions; responsibilities may not move.

```swift
struct SourceModeState {
    var selection: SourceSelection
    var scrollOffset: CGPoint
}

struct WYSIWYGModeState {
    var selection: ProjectionSelection?
    var scrollOffset: CGPoint
    var availability: WYSIWYGAvailability
}

enum WYSIWYGAvailability {
    case waitingForCurrentProjection(SourceRevision)
    case editable(PresentationSnapshot.ID)
}

struct PresentationSnapshot {
    struct ID: Hashable, Sendable { /* opaque monotonic identity */ }
    let id: ID
    let sourceRevision: SourceRevision
    let locationGeneration: UInt64
    let renderedString: String
    let runs: [ProjectionRun]
    let attachments: [ProjectionAttachment]
    let tables: [ProjectionTable]
    let atoms: [ProjectionAtom]
    let sourceUTF16Count: Int
}

enum ProjectionAtom {
    case identity(IdentityAtom)
    case atomic(AtomicSourceAtom)
    case synthetic(SyntheticAtom)
    case uneditable(UneditableAtom)
}

struct AcceptedEdit {
    let sourceMutation: SourceMutation
    let presentationTransition: PresentationTransition?
    let sourceSelectionAfter: SourceSelection
    let projectionSelectionAfter: ProjectionSelection?
}

enum EditorEditOutcome {
    case accepted(AcceptedEdit)
    case refused(EditRefusal)
}

enum EditorUpdateOrigin {
    case nativeUserInput
    case programmaticPresentation
    case selectionRestoration
    case modeRestoration
    case history
    case composition
}
```

`PresentationSnapshot.ID` is not interchangeable with `SourceRevision`. A provisional
presentation and a later authoritative presentation can share a source revision while remaining
different snapshots.

### Files expected to be added

- `EditorModeState.swift`
- `PresentationSnapshot.swift`
- `PresentationTransition.swift`
- `ProjectionAtom.swift`
- `ProjectionSelectionClassifier.swift`
- `MarkdownLiteralEncoder.swift`
- `EditorUpdateOrigin.swift`

Small pure helpers may be placed in an existing cohesive file instead. Do not add files that only
forward to another type.

### Files expected to be substantially modified

- `EditorSession.swift`
- `EditorCoordinates.swift`
- `MarkdownProjectionModel.swift` or its replacement
- `ProjectionCompiler.swift`
- `ProjectionCoordinateMap.swift`
- `ProjectionOracle.swift`
- `SemanticEditEngine.swift`
- `SemanticEditPlanners.swift`
- `StructuralSourceSpans.swift`
- `WYSIWYGTextView.swift`
- `MarkdownTextView.swift`
- `EditorHost.swift`
- `EditorToolbar.swift`
- `MarkdownDocument.swift`
- `ImagePlacementController.swift` and its intent models
- `EditorTrace.swift`

### Files/types expected to be deleted

- `EditorSelectionIntent.swift` after any still-needed `CompositionState` is moved
- `DocumentIOText.swift`
- `DocumentLoadGate.swift`
- `ModeViewState`
- `EditorViewState`
- `EditorViewChromeState`
- `SemanticSelection`
- `EditorCoordinateDomain`
- `EditorSelectionIntent`
- `LogicalSelection`
- compatibility `nsRange` accessors used to erase coordinate domains
- compatibility initializers/overloads that accept raw `NSRange` plus numeric version
- document-owned `pendingSelection`
- boolean callback flags whose meaning is replaced by `EditorUpdateOrigin`
- any legacy projection application or edit route displaced by the new transaction
- historical increment/plan/decision comments that are no longer useful current guidance
- `COR08IntegrationCharacterizationTests.swift` after its cases are moved into behavior-named
  suites

The final deletion gate determines completion. If a named compatibility symbol remains in
production, COR-09 is not done.

## Implementation phases

Complete phases in order. Keep the branch buildable and run the focused tests at each boundary.

### Phase 0 — Establish red characterization

Before production edits:

1. Add a non-UI adapter/session test that installs `hi\n`, creates a current WYSIWYG presentation,
   submits `"a"` at projection offset 0, immediately submits `"b"` at offset 1 without waiting for
   parsing, and proves the current second edit refuses as stale.
2. Add a 100-operation sequence fixture covering insert, replace selection, backward delete,
   forward delete, newline, punctuation, and paste.
3. Add tests showing programmatic `setSelectedRange` sends a delegate notification and currently
   affects typing-group state.
4. Add source inspection assertions demonstrating duplicate state/coordinate symbols exist.
5. Keep these tests failing for the intended reason before implementation.

Anchors: REQ-083–REQ-086, REQ-089–REQ-093; ARC-002–ARC-006, ARC-013.

### Phase 1 — Replace mode and coordinate state

1. Introduce `SourceModeState` and `WYSIWYGModeState`.
2. Make `EditorSession` the only owner of both.
3. Store typed `SourceSelection` and `ProjectionSelection`; never store a bare range whose domain
   depends on the active mode.
4. Make the WYSIWYG selection optional while no current presentation exists.
5. Move `CompositionState` to a composition-specific file.
6. Migrate toolbar, host, adapters, tasks, links, tables, and image entry points directly.
7. Delete `ModeViewState`, `EditorViewState`, `EditorViewChromeState`, `SemanticSelection`,
   `EditorCoordinateDomain`, and their compatibility paths immediately after call-site migration.

Tests:

- compiler-enforced source/projection APIs;
- offset-zero selection remains valid;
- each mode retains its own selection/affinity/scroll;
- wrong-domain calls cannot be constructed through production interfaces;
- no duplicate owner symbol remains.

### Phase 2 — Make presentation indivisible

1. Replace the independent `projection`, `tree`, `acceptedSourceVersion`, and applied adapter
   version fields with one session-owned `PresentationSnapshot` plus any separately named
   authoritative reconciliation metadata.
2. Give every snapshot an opaque identity.
3. Build the coordinate map once as part of snapshot construction; do not derive a potentially
   different map lazily from mutable arrays.
4. Make attributed construction consume one snapshot and return content associated with the same
   snapshot ID.
5. The adapter records one applied snapshot ID, never a bare source version.
6. `ProjectionOracle` validates the complete snapshot before it can become editable.

Tests:

- mixed fields from two snapshots cannot be constructed;
- equal source revision with different snapshot identity is distinguishable;
- stale/partial publication is rejected;
- rendered length, atom coverage, table metadata, attachments, and map bounds agree.

### Phase 3 — Implement the accepted-edit transaction

1. Change the semantic engine to return `EditorEditOutcome`.
2. For a Source request, return a source mutation and typed selections.
3. For a WYSIWYG request, return both the source mutation and a prevalidated
   `PresentationTransition`.
4. `EditorSession.perform` validates everything before committing.
5. On document refusal, apply no presentation change.
6. On commit success, advance the session presentation snapshot and selection synchronously.
7. Ordinary WYSIWYG replacement is intercepted in `shouldChangeTextIn`; apply the accepted
   attributed transition programmatically under `.programmaticPresentation` and return `false`
   so TextKit does not perform a second optimistic mutation.
8. Attribute-only native operations remain native.
9. The transition application must be deterministic and non-failable after source commit:
   validate ranges, resulting lengths, atoms, attributes, and selection before commit.
10. Schedule authoritative reconciliation only after the synchronous transition is installed.

Do not retain the current “commit source, return true, wait for projection” route.

Tests:

- two and 100 immediate keystrokes;
- accepted edit advances source and presentation exactly once;
- refused edit changes neither;
- adapter storage matches the accepted presentation before the callback completes;
- no duplicate TextKit mutation or undo registration;
- selected replacements and deletion at atom boundaries;
- mode switch immediately after accepted input.

### Phase 4 — Projection transitions

Implement pure transition planners for:

- identity text insertion/replacement/deletion;
- paragraph newline and merge/split where exact local structure is known;
- atomic source representations;
- explicit synthetic insertion boundaries;
- task-marker state;
- one table-cell content replacement; and
- selection/affinity updates.

Each transition:

1. identifies affected atoms;
2. produces the exact source replacement;
3. produces the next rendered replacement;
4. shifts later source/projection coordinates mechanically;
5. updates structural metadata or marks it for authoritative replacement;
6. creates a new opaque snapshot ID at the new source revision;
7. runs the oracle; and
8. returns accepted or refusal.

Do not approximate complex structural changes. Toolbar commands that need a full semantic unit may
build an exact next snapshot synchronously from already-available tree/source metadata, provided
the Release budget passes. Otherwise disable/refuse until a proven transition exists.

### Phase 5 — Literal encoder and concrete atomic representations

1. Add `MarkdownLiteralEncoder`.
2. Define an input containing intended visible text, exact source context, neighboring
   characters, container type, and supported dialect.
3. Use the pinned CommonMark/GFM parsing rules to choose the minimum source spelling that reparses
   to the intended literal content without changing surrounding semantics.
4. Cover ASCII punctuation, backslash, ampersand, `<`, `>`, entity-like text, emphasis boundaries,
   headings at line start, blockquote/list markers, thematic-break candidates, code delimiters,
   brackets, parentheses, and table pipes.
5. Parse the smallest safe semantic unit after encoding and verify the intended postcondition.
6. Store atomic source atoms with an explicit decoder/encoder kind, concrete source range, rendered
   range, and insertion affinities.
7. Decode entities and escapes according to pinned cmark/CommonMark behavior.
8. Preserve authored spelling when untouched. Only edited atomic content receives newly selected
   safe spelling.
9. Make normalized inline/fenced code editable only after a proven delimiter/content inverse;
   otherwise keep the precise atom uneditable.

Tests use official-spec-derived fixtures plus adversarial neighbor matrices. WYSIWYG assertions
must prove protective escapes/entities are absent from visible content.

### Phase 6 — Full selection classifier

1. Classify the complete projection selection, not only its start.
2. Accept identity/atomic text only when all intersected atoms form one provable contiguous source
   edit.
3. Require an explicit insertion policy at every zero-length synthetic boundary.
4. Resolve task interactions through the task atom's exact source marker.
5. Resolve a table edit only when the full selection belongs to one cell and the replacement
   preserves allowed table structure.
6. Escape literal pipes using the cell's concrete decoder/encoder.
7. Refuse cross-cell, delimiter-row, mixed-table/text, mixed-editability, or ambiguous selections.
8. Preserve selected source-domain before/after history markers.

Tests:

- half-open table boundaries with upstream/downstream affinity;
- escaped pipe editing;
- cell clear and ordinary replacement;
- cross-cell and cell-to-paragraph refusal;
- list/task marker endpoints;
- entity/code atom boundaries;
- select-all and paragraph-break mappings;
- no partial mutation on any refusal.

### Phase 7 — Native update origin, selection, IME, and undo

1. Replace boolean update flags with scoped `EditorUpdateOrigin`.
2. Every programmatic storage/selection operation establishes an origin for the complete callback
   interval and restores the previous origin with `defer`.
3. Only `.nativeUserInput` selection changes close an open typing group.
4. Mode changes explicitly close typing and publish one restoration instruction.
5. Move pending selection from `MarkdownDocument` into one-shot session state keyed by domain and
   presentation identity.
6. Consume the instruction once after the matching view snapshot is installed.
7. Preserve native marked text in the active WYSIWYG view.
8. On completed composition, classify/encode once, commit one source mutation, install one
   presentation transition, and register one typing history operation.
9. On stale or unsupported composition completion, cancel/refuse without source mutation and
   schedule a current presentation.
10. Undo/redo publishes source-domain history selection; the session maps/restores only against a
    matching presentation.

Tests:

- programmatic selection does not close typing;
- real caret movement does;
- typing coalesces across programmatic projection updates;
- mode switch and discrete commands split groups;
- IME completion is one transaction;
- IME cancellation and stale completion do not mutate;
- undo/redo selection restoration is correct in both modes.

### Phase 8 — Authoritative reconciliation and availability

1. Capture immutable source text, source revision, location generation, and operation generation.
2. Parse/index/compile off-main.
3. Build and oracle-check a complete authoritative snapshot.
4. Publish only if every input identity still matches.
5. If the provisional presentation already represents that source revision, replace it with the
   authoritative snapshot under `.programmaticPresentation` while preserving mapped selection.
6. If no current projection is available after load or source-only structural change, set
   `.waitingForCurrentProjection` and disable WYSIWYG editing.
7. Never display stale WYSIWYG as editable. Source remains available.
8. Trace scheduled, cancelled, discarded, accepted, unavailable, and reconciliation-latency
   outcomes without content.

Tests:

- out-of-order completion;
- source revision reuse is impossible;
- location generation change;
- mode toggling during reconciliation;
- authoritative replacement after provisional input;
- parser failure;
- zero stale-result applications.

### Phase 9 — Simplify `NSDocument` I/O

1. Add focused tests for the inherited `canConcurrentlyReadDocuments` and
   `canAsynchronouslyWrite` defaults.
2. Keep concurrent reads and asynchronous writes disabled.
3. In nonisolated `read(from:ofType:)`, decode the immutable bytes, assert `Thread.isMainThread`,
   and use `MainActor.assumeIsolated` to install through one canonical load path. This is justified
   by AppKit's documented opt-in background-read behavior; do not dispatch an asynchronous apply.
4. In nonisolated `data(ofType:)`, assert the same serialized main-thread contract and use
   `MainActor.assumeIsolated` to snapshot canonical document data without a second text mirror.
5. Keep mutable document state main-actor isolated; do not capture the document in detached test
   tasks.
6. Preserve empty, LF, CRLF, BOM, Unicode, invalid UTF-8, zero-edit byte fidelity, change count,
   autosave, Versions, and undo observer behavior.
7. Delete `DocumentIOText`, `DocumentLoadGate`, their test seams, generation tokens, and scheduling
   bridges.

Exercise actual `NSDocumentController` open/save component paths in addition to direct override
fixtures. If AppKit invokes either callback off-main while the opt-ins remain false, stop and
document the exact runtime counterexample. Do not restore the old bridge without a separately
approved architecture change.

### Phase 10 — Immutable image intent

1. Capture `ImagePlacementIntent` once at paste/drop/Add Image entry.
2. It contains source selection, source revision, location generation, window/document operation
   identity, and immutable claims.
3. WYSIWYG resolves its current projection selection to source before the asynchronous operation
   begins.
4. Placement consumes the immutable value; it never consults later live editor state for the
   insertion point.
5. Preserve the existing exact-copy, containment, order, Save, rollback, and undo behavior.

Tests:

- selection and mode change after picker/promise start;
- two document windows;
- overlapping source edit cancellation;
- ordered batch;
- HEIC/HEIF byte identity and absence of encode path.

### Phase 11 — Decompose the semantic engine

After behavior is covered, make orchestration legible:

- `SemanticEditEngine` validates request and dispatches only.
- `ProjectionSelectionClassifier` owns full-range classification.
- `MarkdownLiteralEncoder` owns literal source spelling.
- inline, block, list/task, table, link, and code planners own their semantic units.
- `PresentationTransitionPlanner` owns next-snapshot construction.
- `ProjectionOracle` owns validity, not production repair.

No file should both classify context, choose source spelling, mutate document state, and update
AppKit. Avoid generic “manager”, “coordinator”, or “state” types without one stated owner.

### Phase 12 — Instrumentation and proof

Extend `EditorTrace` with content-free fields:

- input origin and command class;
- source revision before/after;
- presentation snapshot identity before/after;
- selection classification;
- planner/encoder kind;
- accepted/refusal category;
- provisional transition duration;
- reconciliation scheduled/discarded/applied;
- WYSIWYG availability transitions; and
- undo-group boundary reason.

Trace tests must reject document content, replacement content, selections' text, URLs, image
descriptions, and complete paths.

Release evidence:

- 100 immediate WYSIWYG edits, repeated samples, zero loss/refusal;
- keystroke translation p95 <8 ms at 100,000 UTF-16;
- mode toggle p95 <16 ms;
- off-main parse/index/projection p95 <100 ms;
- zero parser/image work on main actor;
- decoded-image cache ≤64 MiB; and
- before/after comparison showing no regression from the recorded baseline.

Record machine, OS, Xcode/Swift, build configuration, corpus hash/size, warmups, samples, median,
p95, failures, and maximum retained cache.

### Phase 13 — Deletion and conformance gate

Before broad tests:

1. Delete every displaced file/type/overload listed above.
2. Search production and tests for every deleted symbol.
3. Search for raw projection/source `NSRange` APIs paired with numeric versions.
4. Search for direct view-to-document mutations outside the session/document transaction.
5. Search for projection updates keyed only by source version.
6. Search for stale/optimistic edit comments and compatibility aliases.
7. Remove `ADR-*`, `PLAN-*`, `COR-*`, and obsolete `INC-*` implementation comments; replace only
   still-useful rationale with current `REQ-###`/`ARC-###` language.
8. Correct the stale highlighter comment that describes a cross-version CommonMark/GFM dialect.
9. Redistribute the historical `COR08IntegrationCharacterizationTests` cases into the
   behavior-named suites and delete that file.
10. Run the documentation-authority check.
11. Update requirement code/test anchors and statuses on the branch.
12. Delete this plan in the implementation branch only after every gate passes.

No result may be waived as “temporary.”

## Test organization

Prefer focused suites with behavior names:

- `EditorStateOwnershipTests`
- `PresentationSnapshotTests`
- `AcceptedEditTransactionTests`
- `RapidWYSIWYGInputTests`
- `MarkdownLiteralEncoderTests`
- `ProjectionSelectionClassifierTests`
- `NativeUpdateOriginTests`
- `DocumentSerializedIOTests`
- existing projection/image/history suites, migrated to typed APIs
- `ArchitectureConformanceTests`

Use Swift Testing unit/component/integration tests hosted by the existing non-UI test target.
Construct `NSTextView` directly where the adapter boundary matters. Never use XCUITest, screen
automation, or manual verification.

Generated/property fixtures must use deterministic seeds and print the seed on failure.

## Required verification matrix

| Contract | Minimum discriminating evidence |
|---|---|
| REQ-015/018; ARC-001/011 | serialized document defaults; byte fixtures; clean strict-concurrency build; no I/O mirror/gate |
| REQ-052/086; ARC-002/004 | one typed state per mode; persistent identities; current-only WYSIWYG |
| REQ-057/084/091/093; ARC-003/005/006 | immediate rapid input; atomic source/presentation; stale reconciliation discarded |
| REQ-058/092; ARC-008 | punctuation literal; formatting commands semantic and separate |
| REQ-078/080/087; ARC-007/009 | task/table/atomic boundary matrix; cross-domain refusal |
| REQ-083/084; ARC-010/013 | typing/discrete undo; origin-aware selection; IME; history selection |
| REQ-060; ARC-012 | immutable source-domain image intent under async selection/mode changes |
| REQ-089/090; ARC-014 | privacy-safe traces and Release thresholds, no UI/manual evidence |

## Build and delivery sequence

1. Create a dedicated `cor-09-editor-consistency` worktree and branch from current `main`.
2. Implement phases 0–13 with focused commits.
3. Run focused Debug tests after each phase.
4. Run the complete non-UI Debug test target.
5. Run the complete non-UI Release gates with testability enabled.
6. Run a clean Swift 6 complete-concurrency build and treat warnings as failures.
7. Reconcile REQUIREMENTS and ROADMAP on the branch; ENGINEERING changes only if separately
   researched and approved.
8. Delete this implemented plan on the branch.
9. Open a PR.
10. Have a separate agent review code against requirements, ENGINEERING, and this plan.
11. Address every review finding at its root and record fixing commits.
12. Review comments on the last 10 PRs as required by `CLAUDE.md`.
13. Squash-merge, remove branch/worktree/stashes, then run the stale-work and documentation sweep.

## Completion checklist

- [ ] Consecutive accepted input is never dropped while parsing is pending.
- [ ] Source and editable presentation never expose different revisions.
- [ ] Literal WYSIWYG punctuation remains visible literal content.
- [ ] Formatting remains a separate semantic command.
- [ ] One session-owned typed state exists per mode.
- [ ] Presentation snapshot fields are indivisible.
- [ ] Full selection classification refuses mixed/cross-cell/unprovable edits atomically.
- [ ] Programmatic callbacks cannot alter typing-group semantics.
- [ ] IME, undo/redo, selection restoration, paste, tasks, links, tables, and images pass adapter
  integration evidence.
- [ ] Default serialized document I/O preserves every byte fixture.
- [ ] Image intent is immutable and source-domain before async work.
- [ ] Swift 6 complete-concurrency build is clean.
- [ ] Release performance and privacy-safe trace gates pass.
- [ ] Every displaced symbol and route is deleted.
- [ ] All affected requirements have current code and verification anchors.
- [ ] No UI or manual test was added, run, or cited.
- [ ] This plan is deleted in the completed implementation change.
