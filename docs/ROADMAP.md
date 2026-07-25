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

Delivered CommonMark 0.31.2 plus formal GFM 0.29-gfm as the only supported MVP dialect labels.
Removed footnote/highlight/superscript/subscript semantic styling; one- and two-tilde forms are
formal-GFM strikethrough; unknown extensions remain unstyled; focused image-destination fixtures
are styled lexically. The regex engine remains a presentation aid, not a parser.

Approved design: [PLAN-0004](plans/0004-markdown-dialect-conformance-correction.md).

## INC-03 · Paste and drop images — `[build]` 🟠 Correction required

The merged build established the intended paste/drop surface and exact-copy policy, but review
found correctness failures in action serialization, zero-length edit tracking, multi-file
promises, main-thread I/O, exclusive race handling, Save completion, restart-independent move
warnings, and automated verification. It is not a completed capability until COR-02 replaces
the pipeline. Source mode still shows Markdown; inline image rendering remains INC-04.

Approved research and design:
[RESEARCH-0004](research/0004-inc03-image-assets-and-portability.md),
[ADR-0011](decisions/0011-image-placement-and-portability.md), and
[PLAN-0003](plans/0003-inc03-image-assets.md).

## COR-02 · Image placement transaction rewrite — `[build]` ⚪ Planned

Keep ADR-0011's user-visible policy while replacing the implementation with one explicit
transaction state machine, correct one-to-many promise receipt, operation-scoped Save completion,
a dedicated non-main I/O executor, descriptor-relative exclusive publication/retry,
identity-proven cleanup, exhaustive insertion tracking, and source-derived move warnings.

Discovery is complete in
[RESEARCH-0005](research/0005-image-placement-correction-architecture.md).
[ADR-0012](decisions/0012-transactional-descriptor-relative-image-placement.md) and
[PLAN-0005](plans/0005-cor02-image-placement-transaction-rewrite.md) are proposed and require
user approval before the build starts.

## INC-04 · WYSIWYG mode — `[build]` ⚪ Planned

- Research and select a structural parser against the exact CommonMark/formal-GFM contract.
- Render inline while preserving the same source file.
- Make WYSIWYG the default and provide a display-only mode toggle.
- Render referenced images without changing source syntax.
- Complete the MVP.

INC-04 is blocked until COR-02 is Done.

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
- **COR-02 discovery:** RESEARCH-0005 compared correction architectures; proposed ADR-0012 and
  PLAN-0005 select a full transaction/storage rewrite and await approval.
