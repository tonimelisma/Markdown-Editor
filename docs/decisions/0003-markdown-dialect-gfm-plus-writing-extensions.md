# ADR-0003 — Markdown dialect: CommonMark + GFM + writing extensions + first-class images

- **Status:** Accepted
- **Date:** 2026-07-21
- **Deciders:** Toni Melisma
- **Related:** [VISION §4](../VISION.md); ROADMAP INC-02 / INC-03

## Context

"Markdown" is layered — a CommonMark core, GitHub Flavored Markdown (GFM) on top, then many
optional extensions (math, diagrams, callouts, front matter, wiki-links, …). A "pure and
simple" editor must pick a coherent dialect: broad enough to be useful, narrow enough to stay
simple and buildable.

## Decision

The supported dialect is:

- **Base:** CommonMark + **GFM** — tables, task lists, strikethrough, autolinks.
- **Writing extensions:** footnotes; `==highlight==`; superscript `^x^`; subscript `~x~`;
  smart typography; definition lists; emoji shortcodes; heading anchors/attributes.
- **Syntax-highlighted fenced code blocks.**
- **First-class images:** inline display, paste & drag-drop, an auto-managed sibling assets
  folder, and image sizing syntax; referenced by path — never base64.
- **Deferred to the post-MVP backlog:** Mermaid, YAML front matter, and notes-app syntax
  (wiki-links, transclusion, tags). Math, callouts, and CriticMarkup are **out of scope**
  (not planned) unless explicitly added later.

## Consequences

- **Positive:** covers what people actually write without becoming a knowledge base; keeps the
  product coherent with the non-goals.
- **Negative / costs:** several extensions are beyond what a stock GFM parser gives; the parser
  choice and per-extension work are assessed during INC-02.
- **Follow-ups:** parser selection is its own decision (recorded when made); image sizing
  syntax is chosen during the images increment (INC-03).

## Alternatives considered

- **Strict CommonMark only:** rejected — no tables/task lists; users would miss them.
- **Obsidian-style superset (wiki-links, callouts, math by default):** rejected — pulls the
  product toward a knowledge base, against the non-goals; heavy to build.
