# ROADMAP

Increments in logical order, built through the lifecycle in
[CLAUDE.md §3](../CLAUDE.md). A capability is not delivered until its build increment is
`Done` and its requirements have real code and automated-verification anchors.

Discovery and build remain separate units. Approved research, requirements, and a plan authorize
a later build; they do not mean the app already behaves that way.

**Status:** ✅ Done · 🔵 Active · ⚪ Planned · 🅿️ Parked
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
meaning conflicts with formal GFM. The delivered behavior remains recorded truthfully in
REQ-042 and is scheduled for correction next.

## COR-01 · Markdown dialect conformance correction — `[build]` 🔵 Active

**Discovery and plan approved; build is next.**

- Establish CommonMark 0.31.2 plus formal GFM 0.29-gfm as the only supported MVP dialect.
- Remove claimed footnote, highlight, superscript, and subscript semantics from live styling.
- Treat both valid one- and two-tilde forms as formal-GFM strikethrough, never subscript.
- Preserve unfamiliar extension source without styling it as supported semantics.
- Add focused spec-derived tilde and image-destination fixtures.
- Keep the highlighter explicitly lexical; do not add a structural parser in this correction.

Approved design: [PLAN-0004](plans/0004-markdown-dialect-conformance-correction.md).

## INC-03 · Paste and drop images — `[build]` ⚪ Planned

**Discovery and plan approved; blocked only on COR-01.**

- Users add images by paste or drag-and-drop; there is no Import document command.
- Copy supported file-backed PNG, JPEG, GIF, HEIC, and HEIF byte-for-byte into a visible shared
  sibling `assets/` directory. Never transcode HEIC/HEIF.
- Encode bitmap-only clipboard data as PNG.
- Insert ordinary relative `![](assets/name.ext)` source only after all destinations exist.
- Use portable deterministic names, byte-identical reuse, hash-on-collision, exclusive writes,
  resolved containment, and non-destructive failure handling.
- Keep empty image descriptions visible and easy to author; never use a filename as fake alt text.
- Source undo and reference deletion never delete assets.
- Untitled documents save first. Save As/move never silently relocates a shared assets directory.
- Source mode continues to show Markdown; inline rendering is INC-04.

Approved research and design:
[RESEARCH-0004](research/0004-inc03-image-assets-and-portability.md),
[ADR-0011](decisions/0011-image-placement-and-portability.md), and
[PLAN-0003](plans/0003-inc03-image-assets.md).

## INC-04 · WYSIWYG mode — `[build]` ⚪ Planned

- Research and select a structural parser against the exact CommonMark/formal-GFM contract.
- Render inline while preserving the same source file.
- Make WYSIWYG the default and provide a display-only mode toggle.
- Render referenced images without changing source syntax.
- Complete the MVP.

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
