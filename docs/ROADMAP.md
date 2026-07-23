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

## SPIKE-01 · Text engine — `[discovery/spike]` ✅ Done  *(between INC-01 and INC-02)*

Decide the editor's text foundation **before** we need live styling.
- Evaluate **TextKit 1 vs TextKit 2 vs a third-party view** for: live syntax highlighting,
  large-document performance, and scrolling/viewport stability.
- Throwaway POC(s) only — **no production code merged**.
- Output: a research doc + recommendation + an ADR. Feeds INC-02.

## INC-02 · Markdown engine + live-styled source — `[build]` ✅ Done

Make the raw-source mode **live-styled** (styled in place, markup still visible).
- Uses a lexical (regex) Markdown highlighter for GFM core and the implemented light Tier-2
  extensions; it deliberately does not claim full grammatical parsing.
- Live-styles source as the user types with display attributes only; fenced code blocks are
  distinguished with a monospaced font and subtle tint. In-fence language coloring remains
  deferred.
- Displays live word and character counts off the main actor, with cancellation-aware stale-work
  coalescing.
- Replaces the interim `TextEditor` with the SPIKE-01-selected **TextKit 1 `NSTextView`**
  ([ADR-0008](decisions/0008-textkit1-nstextview-editor-engine.md)), including native Find &
  Replace, undo, and spell-check.

## INC-03 · Images (first-class) — `[build]` 🔵 Active (discovery)

- Import and manage images through paste and drag-drop; insert portable source Markdown.
- Auto-managed per-document sibling assets folder; preserve original files where possible.
- Source mode continues to display `![]()` markup, not an inline image. WYSIWYG rendering is
  INC-04 work.
- Do not add a sizing syntax in this increment until a compatibility decision is explicitly made.
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
- *(SPIKE-01, done)* — RESEARCH-0002 + POC on macOS 27; text engine = TextKit 1 `NSTextView`
  (ADR-0008). POC code was throwaway (not merged).
- *(INC-02 build, done)* — merged (squash `a139213`, PR #2); `MarkdownTextView` replaces
  `TextEditor`; regex source styling covers GFM core plus footnotes/highlight/superscript/
  subscript; fenced blocks are monospaced and tinted; live counts and native Find & Replace
  landed. The final review fixed large-document main-thread restyling, stale count-work
  cancellation, and longer fence closers. `NSTextStorage` display attributes were adopted after
  implementation showed temporary attributes cannot provide the required font styling; the saved
  string remains unchanged (INV-2). In-fence language coloring and the remaining Tier-2 dialect
  stay deferred.
- *(INC-03 discovery, active)* — research and a draft plan are in progress. Current recommendation:
  content-local `<document-stem>.assets/` folders, byte-preserving imports, and standard relative
  `![]()` syntax; source mode remains source-only. Asset naming, collision handling, supported
  formats, and any future sizing extension await explicit approval before requirements or code.
