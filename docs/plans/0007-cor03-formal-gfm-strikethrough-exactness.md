# PLAN-0007 — COR-03 formal-GFM strikethrough exactness

- **Increment:** COR-03
- **Date:** 2026-07-25
- **Status:** Proposed — requires explicit approval before code
- **Requirements:** REQ-048–REQ-049
- **Depends on:** [RESEARCH-0007](../research/0007-document-model-and-wysiwyg-architecture.md),
  [ADR-0003](../decisions/0003-markdown-dialect-commonmark-and-formal-gfm.md),
  [ADR-0009](../decisions/0009-regex-live-highlighting-engine.md)

## Goal

Correct Source mode's remaining dialect mismatch before document migration or WYSIWYG work:
formal GFM 0.29 recognizes double-tilde strikethrough, while the current lexical highlighter also
styles single-tilde spans. After COR-03, `~~text~~` is styled as strikethrough and `~text~`
remains literal, unformatted, preserved text.

## Approach

Replace the current strikethrough regular expression with a double-tilde-only lexical rule that:

- requires exactly a valid `~~...~~` delimiter pair under the highlighter's bounded lexical
  contract;
- does not consume triple-or-longer tilde runs as a false double pair;
- retains escape, code-span, and fenced-code exclusions;
- never treats single tilde as subscript or another semantic style; and
- changes display attributes only, never source.

Do not add cmark to this correction. Source remains the independent lexical presentation path;
the structural dependency belongs to INC-04.

## Steps

1. Add failing table fixtures for valid double tilde; literal single/triple/longer/mismatched
   runs; escapes; inline/fenced code; Unicode; and bounded ranges. `// Verifies: REQ-048/049`.
2. Replace the strikethrough pattern/root logic; remove obsolete single-tilde expectations.
3. Re-run source-fidelity, unsupported-extension, fence, image-destination, and full app unit
   suites.
4. Reconcile REQ-048/049 status and anchors plus ROADMAP before PR.

## Automated verification

- Valid formal-GFM double-tilde fixture table receives `.strikethrough`.
- Single tilde and every non-conforming delimiter fixture receives no semantic token.
- Attribute application leaves the source string unchanged and all ranges in bounds.
- Existing unsupported extension, code, fence, and image tests remain green.
- No UI test or manual verification.

## Risks

- A simplistic negative-lookaround can mishandle longer runs. Use explicit delimiter-boundary
  fixtures and keep the rule readable rather than accreting regex exceptions.
- Lexical highlighting remains approximate; the correction must not claim full parsing.

## Out of scope

- cmark dependency or WYSIWYG parsing
- Document-model migration
- New Markdown extensions
- Source normalization or rewrite
- UI tests
