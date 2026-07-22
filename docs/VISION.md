# VISION — Product & Engineering

The durable north star: **what is true** about the product and its architecture — vision,
principles, invariants, and rules. *How we work* lives in [CLAUDE.md](../CLAUDE.md);
*what to build* in [REQUIREMENTS.md](REQUIREMENTS.md); *when* in [ROADMAP.md](ROADMAP.md).

Living but slow-moving. Change it only when a genuine principle changes — and record the
*why* as an [ADR](decisions/).

---

## 1. What it is

A native macOS Markdown editor — pure and simple.

**Pitch:** *"The Markdown editor that feels like it came with macOS."*

## 2. Product principles

1. **No surprises.** Don't make the user think. Idiomatic and HIG-faithful throughout.
2. **The file is the truth.** Edit plain `.md` in place — no proprietary format, no lock-in.
3. **Local-first & private.** No accounts, no telemetry, works fully offline.
4. **Fast & light.** Native performance, small memory footprint.

## 3. Editing model

- Two modes over the *same* file: **WYSIWYG (the default)** and **raw source**, toggleable.
- Switching modes is **display-only** — it never alters the file.
- We build up to it: **plain-text → live-styled source → WYSIWYG-default** (see [ROADMAP.md](ROADMAP.md)).

## 4. Markdown dialect

- **Base:** CommonMark + GitHub Flavored Markdown — tables, task lists, strikethrough, autolinks.
- **Writing extensions:** footnotes; `==highlight==`; superscript `^x^`; subscript `~x~`;
  smart typography (curly quotes, em/en-dashes, ellipses); definition lists; emoji shortcodes
  `:name:`; heading anchors/attributes `{#id}`.
- **Syntax-highlighted fenced code blocks** — language-aware coloring inside ` ``` ` fences.
- **Images (first-class):**
  - Inline display in the editor (not just the `![]()` markup).
  - Insert via clipboard **paste** and **drag-and-drop**.
  - **Auto-managed sibling assets folder** for pasted/dropped files.
  - **Image sizing syntax** (exact syntax chosen during the images increment).
  - Referenced by path — **never** embedded as base64.
- **Deferred to the post-MVP backlog:** Mermaid diagrams, YAML front matter, and notes-app
  syntax (wiki-links, transclusion, tags). See the [ROADMAP backlog](ROADMAP.md).

## 5. Non-goals

Deliberately out of scope (revisit only by amending this section with an ADR):

- **Not a notes app / knowledge base** — no note library, graph, or backlink index.
- **No sync service of our own.**
- **Not collaborative / multi-user.**
- **macOS-only** — not cross-platform.

## 6. Engineering guidelines

Only what is actually decided lives here.

- **Pure Swift; SwiftUI-first.** As much SwiftUI as possible; drop to AppKit only where SwiftUI
  genuinely can't reach, and wrap it cleanly.
- **Ride the platform.** Prefer native, system-provided behaviors (autosave, Versions, tabs,
  find, spell-check, …) over reinventing them.

**Deferred to increment-1 research (not decided here):** the text engine (TextKit 1 vs
TextKit 2 vs a third-party view), the Markdown parser, the document model (`FileDocument`
vs `NSDocument`/`ReferenceFileDocument`), and any third-party dependency decisions. These
will be resolved by spikes and recorded as ADRs before implementation.

## 7. Invariants

Hard rules that must always hold. Breaking one is a bug; a change that would break one
requires an ADR first.

- **INV-1 — No data loss** on crash, quit, or mode-switch.
- **INV-2 — Round-trip fidelity:** opening then saving without edits leaves untouched bytes
  unchanged (modulo an explicit, documented normalization).
- **INV-3 — Plain-text files only.** No proprietary on-disk format.
- **INV-4 — Offline:** all core editing works with no network access.
- **INV-5 — HIG conformance:** standard macOS shortcuts and menus behave as expected.
- **INV-6 — Accessibility:** usable with VoiceOver and full keyboard control.

## 8. Distribution

- **Direct download only**, signed with a **Developer ID** and **notarized** by Apple.
- **Not sandboxed for now** — a deliberate choice to avoid file-access friction during
  development. App Sandbox can be adopted later if we ever want the Mac App Store.
