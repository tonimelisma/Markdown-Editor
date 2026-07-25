# PLAN-0006 — SPIKE-02 document and WYSIWYG architecture

- **Increment:** SPIKE-02
- **Date:** 2026-07-24
- **Status:** Approved — decision-enabling evidence complete; awaiting decision gates
- **Requirements:** Not applicable — standalone discovery/spike; no production behavior
- **Depends on:** COR-02 merged and reconciled;
  [RESEARCH-0007](../research/0007-document-model-and-wysiwyg-architecture.md);
  [ADR-0003](../decisions/0003-markdown-dialect-commonmark-and-formal-gfm.md);
  [ADR-0005](../decisions/0005-discovery-and-build-are-separate-units.md);
  [ADR-0006](../decisions/0006-document-model-filedocument.md);
  [ADR-0008](../decisions/0008-textkit1-nstextview-editor-engine.md);
  [ADR-0010](../decisions/0010-concurrency-highlighting-pipeline.md);
  [ADR-0011](../decisions/0011-image-placement-and-portability.md);
  [ADR-0012](../decisions/0012-transactional-descriptor-relative-image-placement.md)

> This plan authorizes no production implementation. It is a standalone discovery unit:
> automated probes and POC code are throwaway and must not be merged. Its durable outputs are
> completed research, measurements, options, user decisions, and proposed ADRs/plans.

The user approved execution on 2026-07-25. All throwaway probes ran outside the repository.
RESEARCH-0007 records the decision-enabling evidence and the decision-dependent probes that
cannot be specified honestly yet. SPIKE-02 remains Active until its architecture and product
decision gates receive explicit approval and those bounded follow-up probes pass.

## Goal

Produce enough executable evidence to choose the document model, structural parser, source-range
mapping, TextKit 1 WYSIWYG projection, semantic edit boundary, cross-mode undo design, and
COR-02 integration seam for INC-04. The spike succeeds only when the app can plan a genuine
editable WYSIWYG surface—without visible Markdown control characters—while preserving one
ordinary Markdown source and every applicable invariant.

## Objectives

In priority order:

1. Protect INV-1, INV-2, INV-3, INV-5, INV-6, and INV-7 before optimizing convenience.
2. Decide whether the current `FileDocument` remains adequate or must be replaced before INC-04.
3. Prove a TextKit 1 rich projection and targeted source edits; do not revisit TextKit 2 without
   a concrete failed TextKit 1 requirement.
4. Select a structural parser only through executable CommonMark/formal-GFM and source-range
   evidence.
5. Preserve the existing lexical Source mode rather than replacing it with the structural parser.
6. Keep the native keystroke path bounded and all parse/resource computation off-main,
   cancellable, and version-gated.
7. Preserve COR-02's image transaction/storage guarantees while removing its dependence on the
   source view being active.
8. Make every conclusion reproducible through automated tests or inspection—never UI automation
   or manual verification.

## Non-negotiable product contract

The spike evaluates how to build the approved product; it does not reduce it:

1. Source and WYSIWYG are both editable modes over the same source.
2. Source mode shows literal Markdown with live formatting.
3. WYSIWYG shows formatted content with parsed Markdown control characters absent.
4. WYSIWYG is the default; a visible control toggles modes.
5. WYSIWYG has a formatting toolbar.
6. Task checkboxes are interactive.
7. Links are directly clickable.
8. Unsupported semantics remain visible, unformatted, editable, and preserved.
9. Local PNG/JPEG/GIF/HEIC/HEIF references render without mutating or transcoding assets.

## Invariants under test

1. **One source:** only the Markdown string is serialized.
2. **Zero-edit identity:** parse, projection, mode switching, and Save without an edit change no
   source byte.
3. **Local edits:** a WYSIWYG action changes only its explicitly authorized source unit.
4. **Unknown preservation:** unfamiliar or malformed source is never dropped.
5. **Valid generation:** every generated edit is valid under CommonMark 0.31.2 plus formal GFM
   0.29-gfm.
6. **Cross-mode undo:** an edit made in either mode can be undone and redone after switching modes.
7. **Native input:** marked text, Unicode, spelling, selection, copy/paste, keyboard navigation,
   and undo remain native unless a documented semantic adapter is necessary.
8. **Version coherence:** a projection and its source mapping are applied only to the exact source
   version from which they were computed.
9. **No main-thread secondary work:** parsing, projection-model computation, image decode, hashing,
   and disk I/O do not run on the main actor.
10. **Editor-neutral image commit:** image placement captures a source intent and commits Markdown
    without requiring Source mode to be visible.
11. **No private state:** parse trees, selection, mode, caches, and mappings are transient.
12. **No UI tests:** every gate uses unit/integration/component tests or a narrow inherent proof.

## Baseline and workspace discipline

1. Record the merged COR-02 SHA and run the repository's full automated test suite.
2. Treat the merged transaction and storage implementation as the image-placement baseline.
3. Confirm REQUIREMENTS and ROADMAP mark COR-02/INC-03 truthfully before beginning probes.
4. Create POCs only in a temporary directory or isolated spike worktree. No spike code enters the
   app target or production test target.
5. Pin every probed external dependency to an exact revision and record the revision/toolchain.
6. Use the repository's macOS 27 / Xcode 27 deployment settings.

## Workstream A — document-model decision

### A1. Capture current `FileDocument` behavior

Build a reusable automated fixture around the landed app's current document model:

- UTF-8 load/write;
- invalid UTF-8 rejection;
- empty file;
- CRLF preservation;
- leading BOM preservation;
- source replacement and undo registration behavior;
- live file-URL changes;
- untitled Save success/cancel/failure through the COR-02 Save bridge;
- Save As/rename/move inputs required by REQ-076.

This is the comparison baseline; do not infer that framework-provided tabs, Recents, autosave, or
Versions are broken.

### A2. Probe the macOS 27 SwiftUI `Document` protocol

Build a minimal throwaway `@Observable final class` document using Apple's current SDK API:

- one canonical `String`;
- asynchronous reader and writer;
- byte-identical snapshots;
- direct `URLDocumentConfiguration`;
- coordinated access using the framework-provided coordinator;
- explicit undo registration;
- observable edits without value-type rebinding.

Automated probes must cover:

- all byte-fidelity fixtures from A1;
- new/open/save snapshots;
- URL availability before and after initial Save, Save As, rename, and move;
- operation-scoped Save success/cancel/failure without discovering `NSDocument` through a view;
- undo/redo across two editor adapters;
- background read/write actor boundaries;
- cancellation and error propagation;
- no change to ordinary `.md`/`.markdown` files.

Record every beta-API limitation, warning, workaround, and source-compatibility risk.

### A3. Evaluate the stable fallback

If A2 fails a hard requirement, create only the smallest necessary `NSDocument` POC to determine
whether the failure is solved by:

- direct `fileURL`;
- completion-handler Save;
- document-owned undo;
- autosave in place and Versions;
- SwiftUI content hosted in an AppKit document window.

Do not fully implement both candidates. Stop when the evidence can rank:

1. new SwiftUI `Document`;
2. `NSDocument`; and
3. retaining `FileDocument`.

`ReferenceFileDocument` is excluded because Apple deprecates it for new macOS 27 document types.

### A4. Decision gate

The document-model recommendation must include:

- exact problems removed or introduced;
- production files/types that would change;
- impact on COR-02's Save and URL logic;
- undo ownership;
- concurrency/actor model;
- migration and rollback cost;
- framework/beta risk; and
- why retaining `FileDocument` is or is not still the simplest correct choice.

No migration begins until the user approves a proposed ADR and separate build plan.

## Workstream B — structural parser and source index

### B1. Build a parser conformance harness

Probe direct pinned cmark-gfm and any serious alternative through a common value-only interface.
The harness must configure exactly:

- CommonMark 0.31.2 core;
- GFM table;
- GFM task list;
- GFM strikethrough;
- GFM extended autolink; and
- GFM tag-filter behavior where rendering makes it relevant.

Disable smart typography and every unapproved extension.

### B2. Run executable fixtures

Run:

- the official CommonMark examples;
- the formal GFM extension examples;
- the repository's COR-01 tilde, escape, code-span, and image-destination fixtures;
- malformed and pathological nesting cases;
- unsupported extension examples that must remain plain/preserved.

Classify mismatches as parser defects, configuration defects, renderer differences, or
out-of-contract behavior. Do not patch semantic gaps with regex.

### B3. Prove source-position fidelity

Create a `MarkdownSourceIndex` prototype that maps:

- UTF-8 parser positions;
- Swift `String.Index`;
- UTF-16 `NSRange`; and
- projected rich-text ranges.

Required fixtures:

- ASCII and multibyte Unicode;
- emoji and regional indicators;
- composed and decomposed combining marks;
- CRLF and LF;
- leading BOM;
- tabs and indentation;
- multiline emphasis/links;
- escaped punctuation and entities;
- inline/reference links and images;
- variable-length code delimiters;
- tight/loose/nested lists;
- task markers;
- tables and alignment rows;
- malformed/open delimiters.

For every semantic node, prove that its mapped source slice is within bounds and corresponds to
the expected original bytes. Reject a candidate whose public source positions cannot support the
required edit model without inventing a second parser.

### B4. Parser decision gate

Report:

- exact dependency revision and license;
- enabled extensions/options;
- conformance results and mismatches;
- source-range coverage;
- wrapper size and ownership;
- parse performance and memory;
- cancellation behavior; and
- update policy with the conformance suite as a mandatory gate.

## Workstream C — TextKit 1 WYSIWYG projection

### C1. Build the projection model

From an immutable parse snapshot, produce:

- an attributed string containing rendered content only;
- stable semantic node identifiers;
- projection-range ↔ source-range mappings;
- insertion anchors for synthetic content such as list markers and paragraph boundaries;
- attachment descriptors for images and task controls; and
- literal fallback runs for unsupported/malformed source.

AppKit types are created/applied on the main actor. The off-main projection model carries only
`Sendable` values.

### C2. Prove absence, not concealment

Automated component tests must inspect the WYSIWYG `NSTextStorage.string` and verify that parsed:

- heading markers;
- emphasis delimiters;
- link brackets/destinations;
- image syntax;
- list markers;
- quote markers;
- fence markers;
- table separators; and
- task brackets

are absent from the rendered storage. Literal punctuation that is actual content remains.

Do not use zero-size fonts, clear colors, glyph suppression, or source-character attachments as
the WYSIWYG mechanism.

### C3. Render the complete MVP dialect

Probe TextKit 1 rendering for:

- paragraphs and soft/hard breaks;
- Heading 1–6;
- emphasis and strong emphasis;
- strikethrough;
- inline and fenced/indented code;
- links and extended autolinks;
- block quotes;
- thematic breaks;
- ordered, unordered, nested, tight, and loose lists;
- task lists;
- GFM tables;
- local images; and
- raw HTML and unsupported syntax fallback.

The spike must not silently defer a formal-GFM construct while claiming the MVP dialect is
complete.

### C4. Native behavior probes

Instantiate TextKit 1 views directly in component tests and exercise:

- marked-text/IME callbacks;
- selection and replacement;
- spelling configuration;
- copy and plain/rich paste hooks;
- find ranges;
- direct link clicks;
- task-control hit testing;
- accessibility roles/labels/value;
- image attachment selection; and
- undo coalescing.

No XCUITest target, screen automation, or manual verification is permitted.

## Workstream D — semantic edit engine

### D1. Define edit intents

Prototype pure value operations for:

- text insertion/replacement/deletion;
- bold, italic, strikethrough, and inline-code toggles;
- link creation, update, and removal;
- paragraph/Heading 1–6 conversion;
- ordered, unordered, and task-list conversion;
- indent/outdent and list continuation/termination;
- block quote and code-block conversion;
- task checkbox toggle;
- table-cell content edit; and
- image-description/destination edit.

Each operation receives the exact source snapshot/version and projection selection. It returns
either one explicit source transaction plus a post-edit logical selection, or a typed refusal.
It never mutates files or AppKit state.

### D2. Prove edit locality

For each operation, test alternative valid spellings:

- `*` versus `_`;
- `**` versus `__`;
- single/double tilde;
- inline/reference links;
- `-`, `+`, and `*` bullets;
- ordered-list delimiters and starting numbers;
- backtick-run lengths;
- ATX and setext headings;
- fenced and indented code;
- compact and padded tables.

Measure the exact changed source interval. Preserve the original spelling when a safe patch exists.
Where regeneration is unavoidable, show the user the smallest candidate normalization unit and
its before/after examples before requirements are written.

### D3. Consecutive typing without stale mappings

Prove a safe algorithm for rapid edits:

1. native TextKit insertion occurs;
2. a bounded source edit and mapping delta are computed from the current version;
3. canonical source advances once;
4. parse/projection recomputation runs off-main;
5. further edits either use a correctly updated mapping or are serialized safely;
6. stale results cannot replace newer rich text; and
7. selection survives the accepted projection.

Record whether full-document reparse is adequate or an incremental source/mapping structure is
required. Do not introduce a piece table or incremental parser without measurements.

### D4. Cross-mode undo

Using one injected `UndoManager`, test:

- source typing → WYSIWYG → undo/redo;
- WYSIWYG typing → Source → undo/redo;
- toolbar formatting → mode switch → undo/redo;
- task toggle and link edit;
- image reference commit and undo with asset retained;
- coalesced typing versus discrete toolbar operations; and
- stale async result after undo.

If the current document model cannot satisfy this without fragile view ownership, feed that
failure into Workstream A rather than adding another local workaround.

## Workstream E — images and COR-02

### E1. Editor-neutral action boundary

Against the landed COR-02 code, prototype a narrow interface that supplies:

- current document URL/location generation;
- active source selection;
- insertion-intent tracking across edits;
- current canonical source for move warnings;
- operation-scoped Save;
- one source transaction/undo group; and
- post-commit logical selection.

The storage state machine, staging, promises, hashing, naming, descriptor-relative publication,
identity-pinned cleanup, and exact-copy policy remain untouched.

### E2. WYSIWYG image rendering

Resolve local Markdown destinations relative to the document URL without changing source. Test:

- PNG, JPEG, GIF, HEIC, and HEIF;
- byte identity before/after display;
- off-main bounded decode;
- intrinsic-size and fit-to-editor display;
- missing/corrupt/unsupported placeholder;
- meaningful alternative text and empty-description accessibility;
- document move/Save As rerender;
- no remote fetch;
- no metadata stripping;
- no transcoding, especially HEIC/HEIF → JPEG; and
- cancellation/stale decode after source changes.

Rendering is read-only. Placement remains the only path that writes companion files.

### E3. Placement in both modes

Use fake storage and document-edit seams to prove:

- paste/drop in Source captures the source selection;
- paste/drop in WYSIWYG maps the projection selection to a source insertion intent;
- one image selects the empty description semantically;
- several images preserve provider order;
- overlapping edits cancel source insertion exactly as COR-02 requires;
- switching modes during an active action neither loses nor guesses the intent; and
- undo removes only the source reference.

## Workstream F — toolbar, commands, and mode host

Prototype—but do not ship—a SwiftUI `EditorHost` and native command model:

- keep persistent Source and WYSIWYG TextKit 1 views for the window lifetime;
- show only the active surface;
- preserve per-mode logical selection and scroll state;
- make WYSIWYG the default;
- toggle without changing source;
- route toolbar/menu commands through semantic edit intents; and
- expose command enabled/state values from the current semantic selection.

The candidate toolbar includes:

- Source/WYSIWYG mode;
- Paragraph/Heading 1–6;
- bold;
- italic;
- strikethrough;
- inline code;
- link;
- ordered, unordered, and task list;
- block quote; and
- code block.

The spike records, but does not pre-decide, Insert Table, Add Image, rich paste, raw HTML,
source-mode toolbar behavior, and nonessential shortcuts.

## Workstream G — performance and failure behavior

### G1. Corpus

Create generated and real-fixture documents spanning:

- empty and small notes;
- the existing 100,000 UTF-16 source-highlighting boundary;
- large prose;
- deeply nested lists/quotes;
- delimiter-heavy inline markup;
- wide/long tables;
- many local images;
- pathological CommonMark cases; and
- Unicode-heavy text.

Keep fixtures free of private user content.

### G2. Measurements

Record at minimum:

- parse wall time and memory;
- source-index construction;
- projection-model construction;
- main-actor attributed-string application;
- ordinary typing edit translation;
- structural command translation;
- selection remapping;
- image decode/cache cost; and
- cancellation/stale-result rate during bursts.

Report raw distributions by corpus size rather than inventing thresholds before measurement.
Any proposed threshold or graceful-degradation behavior requires user approval before becoming a
requirement.

### G3. Failure matrix

Prove deterministic fallbacks for:

- parser failure or unsupported node;
- invalid mapping;
- stale source version;
- untranslatable selection;
- source edit conflict;
- image missing/corrupt/too large;
- document URL unavailable;
- Save cancelled/failed;
- mode switch during async work; and
- memory pressure/cancellation.

The fallback must keep source accessible and unchanged; it must not silently guess.

## Automated verification matrix

| Area | Required evidence |
|---|---|
| Document model | Byte fixtures, URL lifecycle, Save result, explicit undo, actor boundaries, migration diff |
| Parser | Official CommonMark/formal-GFM fixtures, options/extensions, pathological cases, dependency pin |
| Source index | UTF-8/Swift/UTF-16/projected round trips and exact expected slices |
| Projection | Expected rich string/attributes/mappings; parsed delimiters absent; unsupported text retained |
| Edits | Before/after source tables, exact changed range, generated-source conformance, typed refusal |
| Undo | Cross-mode typing/format/task/link/image sequences with stale-result rejection |
| TextKit | Non-UI component tests for selection, marked text, links, tasks, attachments, accessibility values |
| Images | Real PNG/JPEG/GIF/HEIC/HEIF fixtures, no byte changes/transcoding/network, stale decode |
| COR-02 | Existing transaction suite unchanged plus editor-neutral selection/commit seam |
| Concurrency | Executor/actor identity, cancellation, version gates, no AppKit crossing boundaries |
| Performance | Reproducible corpus, raw timing/memory distributions, no unmeasured threshold claim |

## Decision rubric

A candidate is rejected if it breaks any non-negotiable invariant. Passing candidates are ranked,
in order, by:

1. zero-edit and unknown-source fidelity;
2. correctness of rich edit → source mapping;
3. native undo/input/accessibility behavior;
4. exact dialect conformance;
5. operation-scoped document and image lifecycle correctness;
6. predictable failure/degradation;
7. implementation surface and maintainability;
8. measured latency and memory;
9. dependency stability/update cost; and
10. ability to add later dialect profiles without source migration.

## Deliverables

SPIKE-02 produces:

1. completed RESEARCH-0007 with commands, revisions, fixture results, measurements, and failures;
2. a document-model comparison and recommendation;
3. a parser comparison and recommendation;
4. a proven or rejected TextKit 1 projection/edit architecture;
5. exact normalization examples for user decision;
6. a COR-02 editor-neutral integration design;
7. a toolbar/command proposal with unresolved product choices;
8. proposed ADR changes, not silently accepted decisions;
9. proposed requirements for the next approved build; and
10. one or more separate build plans:
    - a document-model migration plan if selected; and
    - the INC-04 WYSIWYG implementation plan after all prerequisites are resolved.

Throwaway POC code, test apps, dependency checkouts, and generated benchmark artifacts are deleted
after their results are captured.

## Exit gates

SPIKE-02 may be marked Done only when:

- COR-02 is merged and its full automated suite is green;
- all workstreams above have reproducible evidence or an explicit documented impossibility;
- no production code or spike dependency was merged;
- no UI/manual verification is claimed;
- the user has received concrete before/after examples for every open product decision;
- the document model, parser, edit normalization boundary, HTML/paste/table/image/toolbar policy,
  and prerequisite sequence are explicitly approved;
- ADR-0006/0008/0009 and any new ADR proposals accurately reflect the evidence; and
- a later build plan contains no unresolved discovery disguised as an implementation step.

## Risks and mitigations

- **macOS 27 `Document` is beta:** pin the exact SDK, compile/probe the real API, record churn, and
  retain `NSDocument`/current `FileDocument` as explicit alternatives.
- **cmark source positions may be insufficient:** reject or wrap only proven public positions; do
  not create regex semantics or silently normalize the document.
- **Full reparse may race rapid editing:** measure; maintain bounded mapping deltas or serialize
  edits; keep version rejection mandatory.
- **TextKit table/task interaction may be awkward:** prove it in component tests before promising
  an implementation architecture.
- **Two text views can split undo/responder state:** centralize source transactions and inject one
  document undo manager; treat failure as a document-model signal.
- **COR-02 is view-coupled:** adapt only its selection/commit boundary during the later approved
  build; do not rewrite its validated storage transaction.
- **Rich paste can create a second dialect:** keep it an explicit product decision and accept only
  semantics that the selected dialect can generate.
- **Large local images can cause memory spikes:** decode off-main, bound/cache derived display
  state, and never alter original files.
- **Beta/document migration could consume the increment:** keep the migration as a separate build
  if chosen; INC-04 does not absorb it.

## Out of scope

- Production document-model migration
- Production parser dependency
- Production WYSIWYG editor or toolbar
- Changes to the existing Source highlighter
- TextKit 2 or third-party editor adoption without a newly demonstrated TextKit 1 failure
- New Markdown extensions or dialect profiles
- Raw-HTML execution
- Remote-image loading/downloading
- Image resizing syntax, transcoding, optimization, or metadata stripping
- File-picker image placement unless separately approved
- UI tests or manual verification
