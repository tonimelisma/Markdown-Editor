# ROADMAP

Increments in logical order, built the way [CLAUDE.md §3](../CLAUDE.md) prescribes.
**Future vs. existing is explicit:** a capability is not "in the app" until its build
increment is `Done` and its requirements carry real code/test anchors in
[REQUIREMENTS.md](REQUIREMENTS.md).

**Discovery and build are separate units** (CLAUDE.md §3). Every build increment is
preceded by its own approved discovery — research → open questions → requirements → plan —
and **spikes are standalone**, never folded into a coding increment.

**Status:** ✅ Done · 🔵 Active · ⚪ Planned · 🅿️ Parked (post-MVP)
**Unit type:** `[docs]` · `[discovery/spike]` · `[build]`

---

## INC-00 · Docs & process foundation — `[docs]` ✅ Done

The spec-driven documentation system and operating manual.
- `VISION.md`, `CLAUDE.md`, `ROADMAP.md`, `REQUIREMENTS.md` (skeleton).
- ADRs 0001–0005 (decisions already made) + doc templates (ADR / research / plan).
- GitHub remote (`origin`, private) configured.

## INC-01 · Editor foundation — `[build]` ✅ Done

A real editor over real `.md` files — **plain-text editing only** (no styling yet).
- Fix the template's `com.example.plain-text` UTType placeholder → proper Markdown types.
- Wire up the document lifecycle: open / save / autosave / Versions / tabs / Recents.
- Standard behaviors: undo/redo, spell-check, Light/Dark (find & replace deferred to INC-02).
- *Discovery first:* its own research + requirements + plan, approved before coding.

## SPIKE-01 · Text engine — `[discovery/spike]` 🔵 Active  *(between INC-01 and INC-02)*

Decide the editor's text foundation **before** we need live styling.
- Evaluate **TextKit 1 vs TextKit 2 vs a third-party view** for: live syntax highlighting,
  large-document performance, and scrolling/viewport stability.
- Throwaway POC(s) only — **no production code merged**.
- Output: a research doc + recommendation + an ADR. Feeds INC-02.

## INC-02 · Markdown engine + live-styled source — `[build]` ⚪ Planned

Make the raw-source mode **live-styled** (styled in place, markup still visible).
- Parse CommonMark + GFM + the Tier-2 writing extensions.
- Live syntax styling as you type; **syntax-highlighted fenced code blocks**.
- Live word / character count.
- Builds on SPIKE-01's decision.

## INC-03 · Images (first-class) — `[build]` ⚪ Planned

- Inline display in the editor; insert via paste & drag-drop.
- Auto-managed sibling assets folder; image sizing syntax.
- *(Order relative to INC-04 is provisional — this roadmap is living.)*

## INC-04 · WYSIWYG mode (flagship) — `[build]` ⚪ Planned

- Inline rendering (markup hidden); **flip the default to WYSIWYG**.
- Mode toggle stays display-only (VISION INV — never mutates the file).
- **Completes the MVP.**

---

## Post-MVP backlog (uncommitted — the "random ideas" bucket)

Captured so nothing is lost; not scheduled. Promote to an increment when it earns priority.

**Named for later:**
- Mermaid diagrams
- YAML front matter
- Notes-app syntax (wiki-links, transclusion, tags)

**Candidate ideas to weigh later:**
- HTML / PDF export
- Focus mode & typewriter scrolling
- Themes / typography options
- Document outline (table-of-contents) sidebar

---

## Change log

- *(INC-00, done)* — Documentation foundation complete: VISION, CLAUDE.md, ROADMAP,
  REQUIREMENTS skeleton, ADRs 0001–0005, templates, and a private GitHub remote. Text-engine
  work split out as standalone SPIKE-01 between INC-01 and INC-02, per the discovery/build
  separation rule.
- *(INC-01 discovery, done)* — RESEARCH-0001; requirements REQ-001…032; PLAN-0001;
  ADR-0006 (FileDocument) and ADR-0007 (interim TextEditor). Build unit is next.
- *(INC-01 build, done)* — merged (squash `6211ecb`, PR #1); 7 unit tests; review fixes
  (BOM fidelity, Swift-6 isolation, `.fileReadUnknown`, Info.plist); traceability reconciled;
  framework behaviors verified `inherent` (no manual tests).
