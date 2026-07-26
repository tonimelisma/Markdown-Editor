# ROADMAP

Increments in logical order, built through the lifecycle in
[CLAUDE.md §3](../CLAUDE.md). A capability is not delivered until its build increment is
`Done` and its requirements have real code and automated-verification anchors.

Discovery and build remain separate units. Approved research, requirements, and a plan authorize
a later build; they do not mean the app already behaves that way.

**Status:** ✅ Done · 🔵 Active · ⚪ Planned · 🟠 Correction required · 🅿️ Parked
**Unit type:** `[docs]` · `[discovery/spike]` · `[build]`

---

## INC-00 · Docs and process foundation — `[docs]` ✅ Done

Established the conservative spec-driven documentation model, operating manual, templates,
living ADRs, and private GitHub remote.

## INC-01 · Editor foundation — `[build]` ✅ Done

Delivered ordinary UTF-8 Markdown documents, open/new/save/autosave, Versions, tabs, Recents,
undo/redo, spelling, and native appearance.

## SPIKE-01 · Text engine — `[discovery/spike]` ✅ Done

Evaluated TextKit 1, TextKit 2, and third-party options. Selected TextKit 1 `NSTextView`; the
throwaway POC was not merged.

## INC-02 · Live-styled source — `[build]` ✅ Done

Delivered lexical styling with visible markup, fenced-code treatment, live word/character
counts, native Find and Replace, off-main computation, and cancellation. The regex highlighter is
a presentation aid, not a Markdown parser.

INC-02 also delivered styling for a proposed “Tier-2” extension bundle. Subsequent standards
research found that bundle was an undocumented house dialect and that its `~text~` subscript
meaning conflicts with formal GFM. COR-01 removed that styling; REQ-042 is Deferred to
post-MVP dialect-profile research.

## COR-01 · Markdown dialect conformance correction — `[build]` ✅ Done

Delivered the then-approved CommonMark 0.31.2 plus formal GFM 0.29-gfm source labels. SPIKE-02
later replaced that cross-version label with coherent formal GFM 0.29 while retaining COR-01's
token correction. Footnote/highlight/superscript/subscript remain unsupported. COR-03 corrects
the remaining single-tilde mistake so only formal-GFM double tildes receive strikethrough.
Unknown extensions remain unstyled; focused image destinations are styled lexically. The regex
engine remains a presentation aid, not a parser.

Approved design: [PLAN-0004](plans/0004-markdown-dialect-conformance-correction.md).

## INC-03 · Paste and drop images — `[build]` ✅ Done (corrected by COR-02)

Delivered paste/drop image placement into a shared sibling `assets/` directory with exact-copy
PNG/JPEG/GIF/HEIC/HEIF policy. The first merge required COR-02 to replace defective transaction,
promise, Save, and filesystem mechanics.

Approved research and design:
[RESEARCH-0004](research/0004-inc03-image-assets-and-portability.md),
[ADR-0011](decisions/0011-image-placement-and-portability.md), and
[PLAN-0003](plans/0003-inc03-image-assets.md).

## COR-02 · Image placement transaction rewrite — `[build]` ✅ Done

Replaced the INC-03 placement pipeline with an explicit transaction state machine, operation-scoped
Save bridge, one-to-many promise receipt, dedicated non-main I/O executor, non-reentrant keyed
storage lease, descriptor-relative exclusive publication, identity-pinned cleanup, exhaustive
insertion tracking, and source-derived move warnings.

Approved design:
[RESEARCH-0005](research/0005-image-placement-correction-architecture.md),
[RESEARCH-0006](research/0006-document-save-bridge-spike.md),
[ADR-0012](decisions/0012-transactional-descriptor-relative-image-placement.md), and
[PLAN-0005](plans/0005-cor02-image-placement-transaction-rewrite.md).

## SPIKE-02 · Document and WYSIWYG architecture — `[discovery/spike]` ✅ Done

Before INC-04, use throwaway automated probes to decide whether the current value-type
`FileDocument` remains adequate or should migrate; select a structural parser against the exact
CommonMark/formal-GFM contract; prove TextKit 1 rich projection, source-range mapping, targeted
source edits, cross-mode undo, and an editor-neutral COR-02 commit boundary; and measure
performance/failure behavior without UI or manual tests. The completed probes selected
`NSDocument`, coherent formal GFM 0.29 through pinned direct cmark-gfm, and the source-backed
TextKit 1 projection/transaction architecture.

Approved discovery plan:
[RESEARCH-0007](research/0007-document-model-and-wysiwyg-architecture.md) and
[PLAN-0006](plans/0006-spike02-document-and-wysiwyg-architecture.md). The user approved all eight
recommendations on 2026-07-25 and the selected-design follow-up probes passed. No spike code or
dependency was retained.

## COR-03 · Formal-GFM strikethrough exactness — `[build]` ✅ Done

Corrected COR-01's remaining standards mistake: formal GFM 0.29 requires double-tilde
strikethrough. Source highlighting now styles only conforming `~~…~~` spans; single-tilde text
stays literal and unstyled. Also removed the former 100,000 UTF-16-unit live-styling suspension so
Source keeps highlighting at every document size (debounce + off-main + version gate remain).

Correction requirements: REQ-048–REQ-049. Approved design:
[PLAN-0007](plans/0007-cor03-formal-gfm-strikethrough-exactness.md).

## COR-04 · NSDocument migration — `[build]` ✅ Done

Replaced `DocumentGroup`/`FileDocument` with one `NSDocument` that owns canonical source,
version, URL/location generation, Save completion, transactions, and undo. Source behavior and
COR-02 storage remain; view-derived document/commit seams are gone.

Approved requirements: REQ-013–REQ-019. Implemented design:
[PLAN-0008](plans/0008-cor04-nsdocument-migration.md).

Post-merge review found that REQ-016's undo closure captured a historical expected version and
REQ-018 did not compile under Swift 6 complete concurrency. Those defects are corrected by
[COR-05](#cor-05--source-integrity-and-swift-6--build--done).

A later integration review found that a delayed background read can apply without a load
generation/revision guard and overwrite newer source state. COR-08 corrects that remaining
document-lifecycle boundary.

## INC-04 · WYSIWYG mode — `[build]` ✅ Done (corrected by COR-05–COR-08)

- Provide two editable modes over the same canonical Markdown source:
  - Source shows literal Markdown with live lexical styling.
  - WYSIWYG omits parsed Markdown control characters, shows formatted content, and supports direct
    editing through native selection and a formatting toolbar.
- Make WYSIWYG the default and provide a visible Source/WYSIWYG toggle that never rewrites source.
- Render complete formal GFM 0.29 using pinned direct cmark-gfm; leave unsupported semantics and
  raw HTML visible, unformatted, editable, non-executing, and preserved.
- Make task checkboxes interactive and links directly clickable (all URL schemes via NSWorkspace /
  injected opener — no http/https/mailto allowlist).
- Render local PNG/JPEG/GIF/HEIC/HEIF references without changing source syntax or asset bytes.
- Reuse COR-02's image transaction in either mode rather than creating a second placement path.
- Provide “Add Image…” through that same transaction; there is no Import command.
- Paste rich clipboard content as plain text for MVP.
- Render/edit existing tables but defer table insertion and structural controls.
- No document-size degraded mode / styling suspension for Source or WYSIWYG.
- Complete the MVP.

Approved requirements: REQ-052–REQ-059 and REQ-078–REQ-087. Implemented design:
[PLAN-0009](plans/0009-inc04-source-and-wysiwyg-editing.md).

The initial build established the parser, toolbar, and two visible modes, but post-merge review
found heuristic source mapping, incomplete semantic rendering/editing, non-persistent mode views,
undefined IME composition ownership, global image-command routing, incomplete accessibility, and
incomplete HEIF/cache proof. A passing shallow suite did not establish the affected requirements.

Approved correction research and program:
[RESEARCH-0008](research/0008-inc04-correction-architecture-review.md),
[ADR-0013](decisions/0013-source-backed-rich-projection-and-semantic-edits.md), and
[PLAN-0010](plans/0010-inc04-correction-program.md).

## COR-05 · Source integrity and Swift 6 — `[build]` ✅ Done

Replaced stale-version undo with content-validated dynamic `HistoryPatch` history, established one
canonical `SourceMutation` path with explicit typing/discrete grouping, replaced unsafe
byte-snapshot isolation with `DocumentIOText` (`Synchronization.Mutex`), added privacy-safe
`EditorTrace` for mutation/history events, and enabled Swift 6 complete concurrency.

Requirements: REQ-011, REQ-016, REQ-018, REQ-083, REQ-088–REQ-089.
Approved design: [PLAN-0010](plans/0010-inc04-correction-program.md) §5.

## COR-06 · Exact projection and semantic edits — `[build]` ✅ Done (integration closed by COR-08)

Replaced proportional/clamped coordinates with typed `ProjectionSegment` / `ProjectionCoordinateMap`,
`ProjectionCompiler` (visible list markers), split semantic planners with reparse gates, and
`ProjectionOracle` plus characterization/performance evidence.

Requirements: REQ-054–REQ-058, REQ-080, REQ-087, REQ-089–REQ-090.
Approved design: [PLAN-0010](plans/0010-inc04-correction-program.md) §6.

Post-merge review found that natural selections at declared synthetic boundaries can be refused,
fenced-code body ranges can be selected by repeated rendered text, task toggles can rewrite
unrelated marker-like content, and native table typing can bypass the table planner. COR-08
reopens the affected integration claims without replacing the projection architecture.

## COR-07 · Persistent native editing and interaction completion — `[build]` ✅ Done (integration closed by COR-08)

Hosts both TextKit 1 editors persistently (`EditorHostView`); mode-local selection/scroll/affinity;
IME `CompositionState`/`WYSIWYGInputCoordinator`; window-scoped `EditorActionRouter`; task
mouse/Space/Return/accessibility press; bounded direct `CGImage` display with distinct
PNG/JPEG/GIF/HEIC/HEIF fixtures + SHA-256 manifest; Release keystroke/toggle gates.

Requirements: REQ-032, REQ-052, REQ-078–REQ-087, REQ-089–REQ-090.
Approved design: [PLAN-0010](plans/0010-inc04-correction-program.md) §7.

Post-merge review found that WYSIWYG image placement can pass projection offsets as source
offsets, WYSIWYG typing is committed as discrete undo, a real source caret at offset zero can
fall back to stale projection state, and resolved images lose authored accessibility descriptions.
COR-08 reopens those integration claims.

## COR-08 · Editor integration integrity — `[build]` ✅ Done

Make source and projection coordinate domains unmixable, route every real editor action through
one context-aware semantic mutation pipeline, derive fenced-code/task ranges structurally,
honor synthetic endpoint policies, restore correct typing undo groups, capture image intent in
source coordinates before asynchronous placement, preserve image accessibility descriptions,
and generation-gate background document loads.

This correction retains the approved `NSDocument` + pinned cmark-gfm + concrete-source TextKit 1
projection architecture. It removes integration bypasses and requires adapter-path, adversarial,
property, trace, strict-concurrency, and Release-performance proof. No UI or manual tests.

Approved design: [PLAN-0011](plans/0011-cor08-editor-integration-integrity.md).
Requirements: REQ-015, REQ-057, REQ-058, REQ-060, REQ-069, REQ-078, REQ-080, REQ-083, REQ-084,
REQ-087, REQ-089.

---

## Post-MVP backlog

Uncommitted ideas. Each needs research, explicit requirements, and approval before promotion.

- Named dialect profiles for footnotes, highlight, superscript, subscript, smart typography,
  definition lists, emoji, and heading attributes
- Mermaid diagrams
- YAML front matter
- Wiki-links, transclusion, and tags
- Language-aware coloring inside fenced code
- Image sizing with an explicit compatibility contract
- Metadata inspection or stripping
- Explicit “Save a Copy with Assets”
- Explicit, ownership-safe unreferenced-asset cleanup
- Remote-image download
- HTML/PDF export
- Focus mode and typewriter scrolling
- Themes and typography options
- Document-outline sidebar

---

## Change log

- **INC-00:** documentation foundation and lifecycle established.
- **INC-01 discovery/build:** RESEARCH-0001, PLAN-0001, ADR-0006/0007; merged PR #1
  (`6211ecb`) with seven unit tests and traceability reconciliation.
- **SPIKE-01:** RESEARCH-0002 and throwaway POC selected TextKit 1; ADR-0008.
- **INC-02:** RESEARCH-0003, ADR-0009/0010, PLAN-0002; merged PR #2 (`a139213`). Review fixed
  main-thread large-document styling, stale count cancellation, and longer fence closers.
- **COR-01 and INC-03 discovery:** broader standards and ecosystem review replaced the custom
  dialect and per-document managed-folder proposals. Approved outcomes are formal GFM, shared
  non-owned `assets/`, exact-copy PNG/JPEG/GIF/HEIC/HEIF, transactional placement, and no
  Import command. COR-01 must land before INC-03.
- **COR-01 build:** PLAN-0004; formal-GFM tilde strikethrough, Tier-2 style removal, image
  destination fixtures, REQ-047–REQ-051 Done; REQ-042 Deferred to dialect-profile research.
- **INC-03 build:** PLAN-0003 / ADR-0011 merged, but post-merge review reopened the capability;
  affected REQ-060–REQ-077 rows are `Correction`, not Done.
- **COR-02 discovery:** RESEARCH-0005 compared correction architectures; ADR-0012 and PLAN-0005
  select a full transaction/storage rewrite. RESEARCH-0006 proved the DocumentGroup→NSDocument
  Save bridge. REQ-076 conservative source-derived warnings approved.
- **COR-02 build:** PLAN-0005 / ADR-0012 implemented — transactional controller, promise/Save
  bridges, ImageIOExecutor, descriptor-relative store, identity-pinned rollback, scanner;
  REQ-060–REQ-077 Done; old coordinator/service removed.
- **SPIKE-02 planning:** RESEARCH-0007 records the repository/online findings and PLAN-0006
  proposes automated document-model, parser, TextKit 1 WYSIWYG, semantic-edit, undo, image, and
  performance probes before INC-04 requirements or a build plan are written.
- **SPIKE-02 execution:** approved 2026-07-25. Decision-enabling strict-concurrency, conformance,
  source-index, TextKit 1, document, image, edit-seam, and performance probes completed. After all
  eight recommendations were approved, selected-design conformance, edit, interaction, undo,
  image-failure/cache, and performance probes passed. RESEARCH-0007; ADR-0003/0006/0013;
  PLAN-0007/0008/0009.
- **COR-03 build:** PLAN-0007 — double-tilde-only Source strikethrough; REQ-048/049 Done; removed
  the Source live-styling document-size suspension (REQ-045 / ADR-0010).
- **COR-04 build:** PLAN-0008 — `NSDocument` ownership, source transactions, editor-neutral
  DocumentActionInterface; REQ-013–019 Done; FileDocument/DocumentGroup removed.
- **INC-04 post-merge correction discovery:** RESEARCH-0008 reproduced the strict-concurrency
  failure and identified transaction, mapping, persistent-host, interaction, image, test, and
  documentation defects. The approved decision retains `NSDocument`, cmark-gfm, TextKit 1, and
  canonical source while replacing the defective core. PLAN-0010 defines COR-05/06/07 with
  falsifiable trace/oracle/performance gates; affected requirements are `Correction`.
- **COR-08 build:** PLAN-0011 — typed source/projection coordinates, unified semantic
  mutation pipeline, structural code/task spans, synthetic endpoint policy, typing undo
  coalescence, generation-bound loads, image accessibility; REQ-015/057/058/060/069/078/080/
  083/084/087/089 Done; INC-04/COR-06/COR-07 integration claims closed.
