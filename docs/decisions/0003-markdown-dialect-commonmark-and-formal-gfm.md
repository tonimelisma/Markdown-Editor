# ADR-0003 — CommonMark plus formal GFM is the MVP dialect

- **Status:** Accepted
- **Date:** 2026-07-21; revised 2026-07-22
- **Deciders:** Toni Melisma
- **Related:** [VISION §5](../VISION.md); COR-01; INC-02; INC-04

## Context

“Markdown” names a family of dialects. CommonMark defines the core grammar; the formal GFM
specification adds tables, task-list items, strikethrough, and autolinks. github.com also renders
features that are not part of formal GFM. Pandoc and other tools define still other, sometimes
conflicting extensions.

The earlier decision combined formal GFM with footnotes, highlight, superscript, subscript,
smart typography, definition lists, emoji, and heading attributes. That was an undocumented
composite dialect rather than a compatibility contract. It also assigned `~text~` to subscript,
while formal GFM assigns one or two tildes to strikethrough.

## Decision

The MVP source dialect is **CommonMark 0.31.2 plus formal GFM 0.29-gfm**.

- Generated source must be valid under those named specifications.
- “GFM” does not mean all github.com rendering features.
- Unknown or out-of-dialect source is preserved unchanged.
- The source highlighter may be approximate, but its labels and tests must not claim parser
  conformance.
- Footnotes, highlight, superscript, subscript, smart typography, definition lists, emoji, and
  heading attributes move to post-MVP dialect-profile research.
- Formal GFM’s single- or double-tilde strikethrough semantics take precedence. COR-01 removed
  the conflicting single-tilde subscript styling before INC-03.
- A structural parser for WYSIWYG must be evaluated against this exact contract.

## Consequences

- **Positive:** the dialect has an executable reference specification; generated files remain
  broadly intelligible; syntax conflicts are not hidden behind a product-specific label.
- **Negative:** useful extensions are not styled or semantically rendered in the MVP. Files using
  them remain editable, but the app makes no promise about their meaning.
- **Follow-ups:** COR-01 reconciles the existing lexical highlighter and requirements. INC-04
  selects and verifies a structural parser before semantic rendering.

## Alternatives considered

- **The previous GFM-plus-writing-extensions bundle:** rejected because it was a house dialect
  with conflicting syntax and no single conformance target.
- **CommonMark only:** not chosen because formal GFM’s tables, tasks, strikethrough, and autolinks
  are common and have a published specification.
- **Pandoc Markdown:** coherent and featureful, but would make Pandoc rather than conventional
  GFM the compatibility target.
- **Renderer profiles now:** potentially sound, but unnecessary before WYSIWYG and too much
  preference surface for the MVP.
