# PLAN-0011 — COR-08 editor integration integrity

- **Increment:** COR-08
- **Unit:** Build
- **Status:** Implemented (COR-08 build)
- **Corrects:** COR-04, INC-04, COR-06, and COR-07 integration defects
- **Requirements:** REQ-015, REQ-057, REQ-058, REQ-060, REQ-069, REQ-078, REQ-080,
  REQ-083, REQ-084, REQ-087, and REQ-089
- **Architecture:** [VISION](../VISION.md),
  [ADR-0013](../decisions/0013-source-backed-rich-projection-and-semantic-edits.md)
- **Evidence:** [RESEARCH-0008](../research/0008-inc04-correction-architecture-review.md)
  and the post-COR-07 code review recorded on 2026-07-25

> This is a root-cause correction, not a feature increment and not a collection of local
> patches. Keep one canonical Markdown source, `NSDocument`, TextKit 1, pinned cmark-gfm,
> the concrete-source projection, and semantic edit planners. Remove the remaining paths
> that bypass those boundaries.

## 1. Outcome

After COR-08:

1. Source coordinates and WYSIWYG projection coordinates are different Swift types. A raw
   `NSRange` cannot cross that boundary accidentally.
2. Every user edit enters one typed command pipeline that knows its coordinate domain, semantic
   context, source revision, selection affinity, and undo grouping.
3. Native typing, deletion, paste, image placement, toolbar commands, task toggles, links, and
   table-cell changes use the same pipeline. No adapter silently patches canonical source.
4. Projection ranges come from concrete source structure. Repeated text never decides which
   source bytes are edited.
5. Synthetic projection content follows its declared edit policy at selections and carets.
   Natural whole-document and whole-block selections work.
6. Each accepted operation changes exactly the intended source range, reparses to the intended
   semantics, registers the correct undo unit, and restores the correct typed selection.
7. Authored image descriptions survive into the accessible WYSIWYG representation.
8. Automated non-UI integration tests prove the actual adapter-to-document paths. Component
   tests alone are not accepted as proof.

COR-08 is complete only when all proof gates in §11 pass. A green pre-COR-08 suite is merely the
baseline.

## 2. Non-negotiable invariants

1. `MarkdownDocument` owns the only serialized source string and undo history.
2. `EditorSession`, views, projections, and parsers own derived state only.
3. Every range has a source or projection domain. Conversion is explicit and fallible.
4. No range is clamped, proportionally distributed, inferred from equal text, or reinterpreted
   by convention.
5. Synthetic content is editable only according to its `SyntheticInsertionPolicy`.
6. A semantic edit identifies its source target before mutation and changes the smallest
   supported semantic unit.
7. A mutation contains expected revision/text, exact replacement, source selections before and
   after, action name, and undo grouping.
8. Parsing and postcondition validation happen before canonical mutation. Failure changes
   neither source, selection, history, nor files.
9. One user action creates one logical undo unit. Consecutive ordinary typing may coalesce;
   formatting, paste, image insertion, task toggles, and structural edits are discrete.
10. Source remains literal Markdown; WYSIWYG remains delimiter-free for parsed syntax.
11. Supported image files, including HEIC/HEIF, are never transcoded for display.
12. No UI tests, screen automation, or manual verification may be completion evidence.

If a step cannot satisfy these invariants, revise the design. Do not add a special-case offset,
fallback cast, global string replacement, or permissive postcondition.

## 3. Defects to close

### D1 — Natural selections are refused

The coordinate map rejects non-empty selections whose endpoint character is synthetic.
Paragraphs end in a synthetic break and lists begin with synthetic markers, so Select All and
whole-list replacement/deletion can fail.

### D2 — WYSIWYG image placement uses projection offsets as source offsets

The WYSIWYG view reports a raw projection selection to the document. Image placement later treats
that value as canonical source coordinates. Hidden Markdown delimiters make those offsets differ.

### D3 — Task toggling rewrites unrelated marker-like text

Checked-task toggling replaces every `[x]`/`[X]` in the list-item slice. Literal label text and
nested items can change. The fallback postcondition proves only that some marker-like text exists.

### D4 — Fenced-code body mapping uses substring search

The compiler searches the full node source for the rendered body. When the info string or earlier
content matches the body, edits can target the wrong bytes.

### D5 — Native table typing bypasses the table planner

The `NSTextViewDelegate` path turns every replacement into generic `.insertText`.
`TableCellEditPlanner` runs only for explicit `.replaceTableCell`, so real typing can alter table
structure.

### D6 — WYSIWYG typing does not coalesce undo

`EditorSession.perform` uses a compatibility adapter that always creates a `.discrete` mutation.
Tests prove grouping only by directly constructing `.typing` mutations.

### D7 — Source selection `{0, 0}` is treated as missing

The toolbar treats a real caret at offset zero as uninitialized and can fall back to a document
selection containing projection coordinates.

### D8 — Resolved images lose accessibility descriptions

The Markdown image description is used for a missing-image placeholder but not attached to a
successfully resolved image.

### D9 — A delayed background read can overwrite a newer mutation

Background `read(from:ofType:)` schedules loaded text onto the main actor without a load
generation or expected source revision. If a newer mutation exists before the callback applies,
the callback unconditionally replaces source and resets revision/selection state.

### D10 — Document undo checkpoint observers are not removed

The document installs a block-based undo checkpoint observer and retains its token, but does not
remove it deterministically. Closed documents can leave dead observer registrations behind.

## 4. Target design

### 4.1 Typed coordinate values

Introduce immutable `Sendable`, `Equatable` source/projection range and selection values. Use
existing revision types rather than duplicate counters. The compiler must prevent a projection
range from being submitted as a source range.

```swift
struct SourceRange: Sendable, Equatable {
    let utf16: NSRange
}

struct ProjectionRange: Sendable, Equatable {
    let utf16: NSRange
    let revision: ProjectionRevision
}

struct SourceSelection: Sendable, Equatable {
    let range: SourceRange
    let affinity: SelectionAffinity
}

struct ProjectionSelection: Sendable, Equatable {
    let range: ProjectionRange
    let affinity: SelectionAffinity
}
```

Rules:

- `NSRange` exists only at AppKit/Foundation boundaries.
- Convert immediately after reading `NSTextView.selectedRange()`.
- `MarkdownDocument` and `DocumentActionInterface` store/accept source values only.
- Each `EditorViewState` stores its own typed selection.
- `ImagePlacementController` receives a resolved source selection.
- Delete untyped `activeSelection`/`reportActiveSelection` after caller migration. Do not keep
  compatibility overloads.

### 4.2 One edit request pipeline

Both adapters submit one typed request:

```swift
enum EditorSelection {
    case source(SourceSelection)
    case projection(ProjectionSelection)
}

struct EditorEditRequest {
    let command: SemanticCommand
    let selection: EditorSelection
    let expectedSourceRevision: SourceRevision
    let grouping: MutationGrouping
}
```

The pipeline, in order:

1. Validate source and projection revisions.
2. Resolve projection selection to an exact source target.
3. Classify its semantic context.
4. Choose the correct planner.
5. Produce a complete mutation.
6. Reparse and validate the planner-specific postcondition.
7. Commit once through `MarkdownDocument`.
8. Apply the returned typed selection only to a matching displayed revision.

There is no generic “replace these source bytes” WYSIWYG escape hatch. Source mode may build a
direct exact-range mutation because its visible coordinates are source coordinates.

### 4.3 Region-aware native edit dispatch

Classify the segments/nodes intersecting every WYSIWYG native edit:

- plain source-backed text → exact text planner;
- inline semantics → inline planner;
- link label → link-label planner;
- table cell → table-cell planner;
- code span/fenced body → exact code-content planner;
- task attachment → task-marker planner;
- uneditable attachment/synthetic → typed refusal;
- incompatible regions → typed ambiguity refusal unless a block planner supports the selection.

The `NSTextViewDelegate` constructs a request and returns the pipeline result. It neither chooses
a shortcut nor mutates canonical source.

### 4.4 Structural concrete-source spans

Record fenced code opening fence, info string, body, closing fence, and whole-node ranges. Derive
them from fence metadata and concrete line boundaries—never `range(of: renderedText)`.

Record list marker, indentation/prefix, exact task marker, item content, and nested-child ranges.
The task planner patches only the exact three-character task marker. Reparse and locate the item
at the expected structural position; prove checked state flipped and all outside bytes remained
unchanged.

### 4.5 Synthetic endpoint semantics

Remove blanket endpoint rejection:

- `.refuse` rejects edits requiring that segment.
- `.atSourceLocation(location)` folds a touched endpoint to `location`.
- `.atSourceBoundaries(before, after)` maps leading/trailing boundaries according to role and
  affinity.

For non-empty selections, union source-backed overlaps, allowed endpoint anchors, and allowed
interior bridges. Return exact only for one contiguous in-bounds source range with an explicit
policy for every projection unit.

Rewrite the test asserting that selection from a list marker must fail. Required selections:

- Select All in empty, single-paragraph, multi-paragraph, and list documents;
- ordered, unordered, nested, and task lists;
- list marker through item text;
- selection ending at a paragraph break;
- cross-paragraph and nested-block selections;
- deletion, replacement, and applicable formatting over those selections.

### 4.6 Undo grouping

Carry grouping through request → planner → mutation:

- ordinary consecutive insertion/deletion and one IME commit → `.typing`;
- paste, image insertion, formatting, task, table, link, and block transforms → `.discrete`.

Close typing groups on selection/mode/command change, discrete action, undo/redo, load/close, and
composition ownership change.

Delete the general discrete-only `commitSourceEdit`. If COR-02 needs an adapter, it must construct
a complete discrete mutation at its source-domain boundary.

### 4.7 Image-placement intent

At paste, drop, or Add Image:

1. Capture typed active-editor selection and affinity.
2. Resolve projection intent against the exact current projection.
3. Refuse before file work if stale, ambiguous, or unsupported.
4. Pass immutable source intent into placement and start source-range tracking.
5. Preserve COR-02 exact-copy, ordering, publication, rollback, overlap cancellation, and single
   discrete transaction.

Never consult whichever editor is active after asynchronous work starts.

Test after emphasis, links, all list markers, emoji/non-BMP text, empty WYSIWYG source, and a mode
switch during pending work. Exercise exact-copy PNG/JPEG/GIF/HEIC/HEIF fixtures. Never generate
JPEG from HEIC/HEIF.

### 4.8 Toolbar and accessibility

`EditorViewState` always has initialized domain-correct selection. Offset zero is valid, never a
sentinel. The toolbar reads only the active mode's state and never falls back to a document-global
selection.

For resolved images, expose authored description as the accessibility label. Empty descriptions
use an intentional decorative-image policy; never invent alt text from a path. Verify properties
by direct non-UI object inspection.

### 4.9 Generation-bound document loading and observer ownership

Give each load request an immutable generation/token. A scheduled main-actor application may
replace source only when:

- its token is still the document's current load token; and
- no newer source mutation has advanced the expected revision since the read began.

Initial document loading must complete before editing ownership is exposed. A stale load
application returns/records a typed stale result and does not reset source, history, dirty state,
or selection.

Store the undo checkpoint observer token in the document and remove it deterministically during
teardown. Closing an open typing group and observer removal must be idempotent. Add a lifecycle
test using an injected notification center or observer-registration seam; do not rely on object
deallocation timing or UI windows.

## 5. Implementation sequence

Complete phases in order. Focused tests must pass before proceeding.

### Phase 0 — Lock in failures

Add failing regression tests for D1–D10 before production changes. Each must use the real non-UI
adapter/coordinator or pipeline entry, assert exact source and typed selections, check undo where
relevant, and prove refusal changes nothing.

### Phase 1 — Typed coordinate domains

1. Inventory every editor/projection/document/placement `NSRange`.
2. Classify source, projection, or boundary-only.
3. Add typed values and validated initializers.
4. Migrate coordinate-map signatures, view state, semantic selection, pending selection, and
   selection intent.
5. Migrate document and COR-02 interfaces to source-only values.
6. Delete untyped stored selection and fallback APIs.

Checkpoint: production has no untyped stored active selection.

### Phase 2 — Complete mutations

1. Add grouping and typed selections to semantic requests/results.
2. Make planners return complete mutation proposals.
3. Validate expected text and postconditions before commit.
4. Migrate Source, WYSIWYG, COR-02, toolbar, task, table, link, paste, and IME callers.
5. Delete the discrete-only semantic adapter.
6. Prove typing coalescence and discrete boundaries through `EditorSession`.
7. Add generation-bound load application and deterministic observer teardown.

Checkpoint: `EditorSession.perform` does not call `commitSourceEdit`.
Background read application cannot overwrite a later committed mutation.

### Phase 3 — Structural projection and endpoint mapping

1. Add structural fenced-code/task spans.
2. Delete rendered-substring discovery and global marker replacement.
3. Implement policy-aware synthetic endpoints.
4. Expand `ProjectionOracle` for coverage, bounds, structural spans, and round trips.
5. Replace the incorrect list-marker refusal test.
6. Run the formal-GFM fixture corpus.

Checkpoint: no `range(of: rendered` mapping or whole-item task marker replacement remains.

### Phase 4 — Semantic native dispatch

1. Add a pure context classifier.
2. Route every context in §4.3.
3. Make the delegate call the single pipeline.
4. Apply optimistic native updates only after acceptance; replace them only with matching
   projection revisions.
5. Add adapter-path tests for each context.

Checkpoint: unescaped table pipe/newline refuses without mutation; escaped pipe changes one cell.

### Phase 5 — Image, toolbar, accessibility

1. Resolve image intent before COR-02 starts.
2. Remove controller reads of generic live selection.
3. Remove toolbar sentinel/fallback behavior.
4. Preserve resolved-image accessibility descriptions.
5. Add hidden-delimiter, mode-switch, offset-zero, and accessibility tests.
6. Re-run every COR-02 exact-copy/rollback/Save/collision/tracking test.

### Phase 6 — Remove obsolete paths and smells

Delete:

- untyped selection storage;
- discrete-only generic commit adapters;
- substring source discovery;
- global task-marker replacement;
- toolbar `{0, 0}` sentinel logic;
- tests asserting invalid behavior;
- unused compatibility overloads/comments.

Then verify observer removal, revision/location gates, immutable cross-actor captures, one document
commit path, and one immutable source intent per placement action. Do not leave two paths
temporarily.

## 6. Required automated proof

All verification is non-UI unit/integration/property testing.

### Coordinate matrix

For every supported construct, test carets with both affinities, selections beginning/ending at
each segment kind, adjacent segment pairs, whole nodes/documents, defined round trips, deterministic
refusals, emoji, combining marks, CRLF, and non-BMP Unicode.

Cover paragraphs, headings, emphasis, strong, strikethrough, inline/fenced code, links, images,
quotes, ordered/unordered/task lists, tables, thematic breaks, raw HTML, and literal fallback.

### Exact mutation fixtures

Each fixture records initial source/selection, command, accepted/refused result, exact final
source/selection, semantic postcondition, grouping, and exact undo/redo source.

Mandatory adversarial fixtures:

- fenced info string identical to body and repeated body text;
- checked task containing literal `[x]`, plus nested checked tasks;
- table unescaped/escaped pipes, newline, empty content, Unicode;
- Select All over paragraphs and every list type;
- toolbar action from real source offset zero;
- image paste after hidden delimiters and during a mode switch.

### Real-path integration

Through production session/coordinator entry points, prove:

- WYSIWYG keystrokes coalesce;
- selection movement closes typing group;
- paste is discrete;
- table typing reaches its planner;
- task action reaches exact-marker planner;
- image intent resolves before placement;
- toolbar uses the active typed selection;
- cross-mode undo/redo restores exact source/selections.

Direct planner tests are component coverage, not integration proof.

### Deterministic property tests

Generate supported Markdown, valid projection selections, and mixed edit/mode/undo sequences.
Record failure seeds. Prove refused actions are inert, accepted actions touch only their declared
target, source remains valid, undo/redo is exact, projection oracle remains valid, and image bytes
never change.

## 7. Instrumentation

Extend privacy-safe traces with:

- coordinate domain and revision pair;
- semantic context and chosen planner category;
- mapping/refusal result;
- mutation grouping and affected lengths;
- postcondition result;
- projection accepted/stale;
- image intent captured/resolved/refused.

Never record source/replacement/selected text, descriptions, link destinations, URLs, or paths.
Integration tests assert expected planner/grouping traces in addition to exact source results.

Re-run Release gates after correction: p95 translation below 8 ms, mode toggle below 16 ms,
parse/index/projection below 100 ms at 100,000 UTF-16, zero stale application, no parser/image
decode on main actor, and cache at most 64 MiB. Report raw samples, median, p95, configuration,
hardware, corpus hash, and seed.

## 8. File-level map

Expected files:

- `ProjectionSegment.swift` — typed coordinates/revisions and synthetic policies.
- `ProjectionCoordinateMap.swift` — policy-aware mappings.
- `ProjectionCompiler.swift` — structural code/task spans.
- `ProjectionOracle.swift` — structural/round-trip invariants.
- `SemanticEditEngine.swift` — typed request/context dispatch.
- `SemanticEditPlanners.swift` — exact task/code/table planners.
- `EditorSession.swift` — one request/mutation path and grouping.
- `EditorSelectionIntent.swift`, `EditorViewState.swift` — typed mode-local state.
- `WYSIWYGTextView.swift`, `MarkdownTextView.swift` — AppKit boundary conversion only.
- `EditorToolbar.swift` — active typed selection.
- `DocumentActionInterface.swift`, `ImagePlacementController.swift` — source-only placement.
- `MarkdownDocument.swift` — complete mutation commit, generation-bound load application, and
  observer teardown.
- `RichTextBuilder.swift` — image accessibility.
- `EditorTrace.swift` — privacy-safe routing proof.

Split by responsibility if needed; do not create a generic helpers dumping ground.

## 9. Code-quality rules

- Prefer exhaustive enums to boolean mode flags.
- Prefer immutable request/results to shared coordinator state.
- Never use `NSNotFound`, `{0, 0}`, empty text, or revision zero as initialization sentinels.
- Never use global notifications or document-global selection for local editor intent.
- Never locate parser-owned structure with regex/substrings.
- Never accept a postcondition because matching syntax exists somewhere.
- Never retry a typed mapping failure with a raw range.
- Delete migrated compatibility paths.

## 10. Build workflow

1. Create worktree/branch `fix-cor08-editor-integration-integrity`.
2. Add failing characterizations before production fixes.
3. Commit coherent phases.
4. Rebase on current `main`.
5. Reconcile docs/traceability before the PR.
6. Open one PR; do not split partially compatible mutation paths across PRs.
7. Spawn a separate review agent against this plan/requirements.
8. Post findings, claim/fix every comment at root cause, and identify fixing commits.
9. Run required PR-comment triage, squash-merge, and clean all own artifacts.

## 11. Completion gates

- [ ] D1–D10 each had a failing regression test.
- [ ] Source/projection domains are distinct throughout production APIs.
- [ ] No document-global raw selection remains.
- [ ] Every WYSIWYG mutation uses the semantic pipeline.
- [ ] Every mutation reaches one complete commit path.
- [ ] Natural whole-document/list selections edit correctly.
- [ ] Code/task ranges are structural.
- [ ] Native table typing reaches the table planner.
- [ ] WYSIWYG typing coalesces; discrete actions remain discrete.
- [ ] Image intent resolves before asynchronous file work.
- [ ] Source offset zero remains valid toolbar state.
- [ ] Resolved images expose authored descriptions.
- [ ] Delayed loads cannot overwrite newer mutations.
- [ ] Undo checkpoint observers are removed deterministically.
- [ ] Exact, adapter-path, coordinate, and property suites pass.
- [ ] Existing Source/parser/COR-02/document/undo/IME/image suites pass.
- [ ] Strict Swift 6 complete-concurrency build passes.
- [ ] Release performance evidence passes reproducibly.
- [ ] Trace privacy/routing tests pass.
- [ ] No UI/manual tests are used.
- [ ] Obsolete-path searches are empty.
- [ ] Separate-agent review is resolved.
- [ ] REQUIREMENTS/ROADMAP traceability is truthful.

Any unchecked item leaves COR-08 Active or Correction required—not Done.

## 12. Junior-developer handoff

Before editing:

1. Read this plan, VISION's editor/invariant sections, ADR-0013, and RESEARCH-0008.
2. Run baseline non-UI tests and strict-concurrency build.
3. Create the required worktree/branch.
4. Add the ten failing regressions.

For each phase:

1. Name the invariant/defect.
2. Change one coherent boundary.
3. Run focused tests plus oracle/fixtures.
4. Search for remaining superseded callers.
5. Commit only when internally consistent.

Before review:

1. Run every §11 gate.
2. Inspect for raw cross-domain ranges and duplicate mutation paths.
3. Inspect refusals for guessing.
4. Reconcile every affected requirement with real code/test anchors.
5. Mark COR-08 Done only after the evidence exists.
