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
counts, native Find and Replace, off-main computation, cancellation, and a large-document cap.
The regex highlighter is a presentation aid, not a Markdown parser.

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

## COR-03 · Formal-GFM strikethrough exactness — `[build]` 🟠 Correction required

Correct COR-01's remaining standards mistake: formal GFM 0.29 requires double-tilde
strikethrough, while the current Source highlighter also styles single-tilde spans. Preserve
single tilde literally and style only conforming double-tilde source.

Correction requirements: REQ-048–REQ-049. Proposed implementation:
[PLAN-0007](plans/0007-cor03-formal-gfm-strikethrough-exactness.md). The plan requires explicit
approval before implementation.

## COR-04 · NSDocument migration — `[build]` ⚪ Planned

Replace the current `DocumentGroup`/`FileDocument` ownership path with one `NSDocument` that owns
canonical source, version, URL/location generation, Save completion, transactions, and undo.
Preserve current Source behavior and COR-02 storage unchanged while replacing their view-derived
document/commit seams.

Approved requirements: REQ-013–REQ-019. Proposed implementation:
[PLAN-0008](plans/0008-cor04-nsdocument-migration.md). The plan requires explicit approval before
implementation.

## INC-04 · WYSIWYG mode — `[build]` ⚪ Planned

- Provide two editable modes over the same canonical Markdown source:
  - Source shows literal Markdown with live lexical styling.
  - WYSIWYG omits parsed Markdown control characters, shows formatted content, and supports direct
    editing through native selection and a formatting toolbar.
- Make WYSIWYG the default and provide a visible Source/WYSIWYG toggle that never rewrites source.
- Render complete formal GFM 0.29 using pinned direct cmark-gfm; leave unsupported semantics and
  raw HTML visible, unformatted, editable, non-executing, and preserved.
- Make task checkboxes interactive and links directly clickable.
- Render local PNG/JPEG/GIF/HEIC/HEIF references without changing source syntax or asset bytes.
- Reuse COR-02's image transaction in either mode rather than creating a second placement path.
- Provide “Add Image…” through that same transaction; there is no Import command.
- Paste rich clipboard content as plain text for MVP.
- Render/edit existing tables but defer table insertion and structural controls.
- Complete the MVP.

Approved requirements: REQ-052–REQ-059 and REQ-078–REQ-087. Proposed implementation:
[PLAN-0009](plans/0009-inc04-source-and-wysiwyg-editing.md). INC-04 is blocked until COR-03 and
COR-04 are Done and PLAN-0009 is explicitly approved.

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
