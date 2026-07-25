# ADR-0003 — Formal GFM 0.29 is the MVP dialect

- **Status:** Accepted
- **Date:** 2026-07-21; revised 2026-07-22 and 2026-07-25
- **Deciders:** Toni Melisma
- **Related:** [VISION §5](../VISION.md); COR-01; INC-02; INC-04

> Living decision. SPIKE-02 proved that the earlier cross-version combination was not one
> executable dialect. The user approved coherent formal GFM 0.29 and direct pinned cmark-gfm on
> 2026-07-25.

## Context

“Markdown” names a family of dialects. CommonMark defines the core grammar; the formal GFM
specification adds tables, task-list items, strikethrough, and autolinks. github.com also renders
features that are not part of formal GFM. Pandoc and other tools define still other, sometimes
conflicting extensions.

The earlier decision combined formal GFM with footnotes, highlight, superscript, subscript,
smart typography, definition lists, emoji, and heading attributes. That was an undocumented
composite dialect rather than a compatibility contract. It also assigned `~text~` to subscript,
while formal GFM assigns double tildes to strikethrough.

## Decision

The MVP source dialect is the complete **GitHub Flavored Markdown 0.29-gfm specification**,
including its bundled CommonMark core and five formal extensions: tables, task-list items,
strikethrough, extended autolinks, and tag filtering.

- Generated source must be valid under that one named specification.
- “GFM” does not mean all github.com rendering features.
- Unknown or out-of-dialect source is preserved unchanged.
- The source highlighter may be approximate, but its labels and tests must not claim parser
  conformance.
- Footnotes, highlight, superscript, subscript, smart typography, definition lists, emoji, and
  heading attributes move to post-MVP dialect-profile research.
- Formal GFM's double-tilde strikethrough semantics take precedence. COR-03 removes COR-01's
  mistaken single-tilde strikethrough styling; single-tilde spans remain literal and unsupported.
- WYSIWYG semantic authority uses direct cmark-gfm 0.29.0.gfm.13 through pinned
  `swift-cmark` revision `5d9bdaa4228b381639fff09403e39a04926e2dbe`, with exactly the five
  formal extensions enabled, `CMARK_OPT_STRIKETHROUGH_DOUBLE_TILDE` set, and smart/extra options
  disabled.
- Every dependency update must pass the complete formal-GFM specification and pathological
  parser suite before adoption.

## Consequences

- **Positive:** the dialect has one executable reference specification and GitHub's reference
  parser; generated files remain broadly intelligible; syntax conflicts are not hidden behind a
  product-specific label.
- **Negative:** useful extensions are not styled or semantically rendered in the MVP. Files using
  them remain editable, but the app makes no promise about their meaning.
- **Follow-ups:** COR-01's lexical source styles remain presentation-only. INC-04 adopts the
  pinned parser and verifies semantic rendering/generation against the complete formal-GFM suite.

## Alternatives considered

- **The previous GFM-plus-writing-extensions bundle:** rejected because it was a house dialect
  with conflicting syntax and no single conformance target.
- **CommonMark only:** not chosen because formal GFM’s tables, tasks, strikethrough, and autolinks
  are common and have a published specification.
- **CommonMark 0.31.2 plus formal GFM 0.29 extensions:** superseded after SPIKE-02 showed
  cmark-gfm fails 11 of the newer CommonMark cases and a conforming hybrid requires a substantial
  private parser fork.
- **Pandoc Markdown:** coherent and featureful, but would make Pandoc rather than conventional
  GFM the compatibility target.
- **Renderer profiles now:** potentially sound, but unnecessary before WYSIWYG and too much
  preference surface for the MVP.
