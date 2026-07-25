# PLAN-0004 — COR-01 Markdown dialect conformance correction

> Historical build plan. SPIKE-02 later replaced the cross-version dialect label with coherent
> formal GFM 0.29 and found that this plan incorrectly treated single tildes as formal
> strikethrough. COR-03 corrects that remaining source-style mismatch; see ADR-0003 and
> RESEARCH-0007.

- **Increment:** COR-01
- **Date:** 2026-07-22
- **Status:** Implemented
- **Requirements:** REQ-047–REQ-051
- **Depends on:** [ADR-0003](../decisions/0003-markdown-dialect-commonmark-and-formal-gfm.md),
  [ADR-0009](../decisions/0009-regex-live-highlighting-engine.md),
  [RESEARCH-0004](../research/0004-inc03-image-assets-and-portability.md)

## Goal

Correct the delivered source highlighter and its claims so the product has one honest MVP
dialect: CommonMark 0.31.2 plus formal GFM 0.29-gfm. Remove custom Tier-2 semantic styling,
improve image-destination fixtures, and clearly keep the regex engine lexical rather than
calling it a parser. This completed plan styled both single- and double-tilde spans, but that
part was based on a mistaken reading of the standard and is superseded by COR-03.

## Approach

Keep the current TextKit and concurrency architecture. Change only highlighter patterns, style
labels/tests, and synchronized documentation:

- remove footnote, highlight, superscript, and subscript recognition from supported semantics;
- retain the completed single- and double-tilde source-styling change as historical scope;
  COR-03 removes single-tilde styling to match formal GFM;
- preserve all source bytes and leave unknown extension syntax unstyled;
- improve the lexical image pattern enough to recognize focused valid CommonMark destination
  fixtures without claiming complete nested grammar support; and
- add spec-derived fixtures with source links and expected display ranges.

Do not add a parser dependency in this correction. Parser selection belongs to INC-04 discovery.

## Steps

1. Replace the Tier-2 styles and patterns with GFM-aligned tilde handling (REQ-047–REQ-049).
2. Add focused CommonMark/GFM fixture tables covering tilde runs, escapes, code spans, and image
   destinations with angle brackets, titles, escaped characters, and balanced parentheses
   (REQ-048, REQ-050).
3. Assert every styled range is in bounds and every styling pass leaves the source string
   byte-for-byte unchanged (REQ-049, REQ-051).
4. Remove or rename tests and theme cases that imply supported footnote/highlight/super/subscript
   semantics; unknown examples remain explicit preservation fixtures (REQ-047, REQ-049).
5. Reconcile REQ-041/REQ-042 statuses and exact code/test anchors on the branch before opening
   the PR, then mark COR-01 done in ROADMAP after review (REQ-047–REQ-051).

## Testing

- Table-driven unit tests derived from cited CommonMark 0.31.2 and GFM 0.29-gfm examples.
- Historical regression tests for `~one~` and `~~two~~`, plus intraword/whitespace edge cases,
  escaped tildes, and code spans; COR-03 replaces the incorrect single-tilde expectation.
- Image-reference fixtures for simple portable paths and selected valid destination/title forms.
- Unknown-extension fixtures proving source preservation and absence of claimed semantic styles.
- Existing concurrency, range-boundary, and large-document tests remain green.

These tests establish the approved lexical behavior. They do not certify that regex is a
conforming Markdown parser.

## Risks / open questions

No product questions remain. Regex cannot model the full nested grammar; focused fixtures and
honest labeling bound the correction until a structural parser is selected.

## Out of scope

WYSIWYG, parser adoption, footnote/highlight/super/subscript rendering, smart typography,
definitions, emoji, heading attributes, image file placement, and language-aware code coloring.
