# COR-33 — Fenced code content is not an identity mapping in CRLF documents

- **Status:** Approved; not implemented

## Scope

`.codeBlock` refuses on an ordinary identity paragraph selection in a CRLF document, while
`.unorderedList`, `.orderedList`, `.taskList`, `.blockQuote`, `.setParagraph`, and `.setHeading`
all succeed there after COR-26's terminator fix. Make the fenced-code projection carry a proven
mapping under CRLF, or refuse for a stated reason rather than through a mapping accident.

## Reproduction

Found while fixing the PR #32 review comment about CRLF terminator width, and confirmed by
instrumenting the failing expectation:

- Source `"First paragraph.\r\n\r\nSecond paragraph.\r\n"`, WYSIWYG projection selection `{0,16}`.
- Classification is `.identityText(sourceRange: {0, 16})` — the selection is not the problem.
- Projection is `"First paragraph.\nSecond paragraph.\n"`.
- `.codeBlock` returns `.refused`; the other line-reshaping commands return `.accepted`.

## Cause

cmark normalises line endings to `\n` internally, so a code block's `literal` is
`"First paragraph.\n"` while the corresponding **source** span is `"First paragraph.\r\n"`.
`ProjectionCompiler` appends that literal as a source-backed run, so for a CRLF document the
projected length and the source length of fenced content disagree by one UTF-16 unit per line.
`ProjectionCoordinateMap` only maps a source-backed segment positionally when
`projection.length == source.length`, so the post-command caret inside the new fence cannot be
projected exactly and `planAuthoritativeTransition` refuses.

This is a projection-fidelity defect, not a caret defect. COR-26 fixed the caret and does not
claim this case; `CommandLivenessMatrixTests.lineReshapingCommandsApplyInCRLFWYSIWYGDocuments`
excludes `.codeBlock` with that exclusion stated in the test.

## Requirements and invariants

- REQ-007/REQ-015: CRLF documents are preserved byte-for-byte — this must not be "fixed" by
  rewriting the user's line endings.
- REQ-054/056: the projection is compiled from pinned cmark semantics plus original source.
- REQ-113: an enabled command performs; `.codeBlock` is currently enabled and refuses here.
- ARC-007: exact or refused, never guessed. A positional mapping across mismatched lengths is
  precisely the guess this forbids.
- **Architecture impact: possible.** If the resolution requires atomic-representation atoms with
  a proven decoder/encoder for CRLF fenced content rather than an identity run, that touches the
  §6 projection model and needs the architecture change gate before implementation.

## Options, none yet chosen

1. Emit fenced content from the **concrete source span** rather than cmark's normalised literal,
   so identity holds under any line ending. Most faithful; needs care where cmark's literal and
   the source span legitimately differ (indented code, tabs).
2. Represent CRLF fenced content as an **atomic** atom with a proven `\r\n`↔`\n` decoder and
   inverse encoder, which is exactly what ENGINEERING §6 case 2 exists for.
3. Refuse `.codeBlock` explicitly in CRLF documents with a stated reason, and disable the command
   so it never reports `enabled` — honest, but it removes a capability from CRLF users.

## Automated non-UI proof

Extend `lineReshapingCommandsApplyInCRLFWYSIWYGDocuments` to include `.codeBlock` — it must fail
before the fix. Add round-trip proofs that a CRLF document containing a fenced block survives
open → project → command → save byte-identically apart from the intended edit, and that LF
documents are unchanged by whatever mechanism is chosen.

## Failure and rollback behavior

If no exact mapping can be proven, option 3 is taken: the command is disabled rather than left
enabled-and-refusing, because REQ-113 makes "enabled" a promise. Source is never rewritten to
make the mapping work.

## Deletion and conformance gate

- No line-ending normalisation may be introduced into canonical source (REQ-007).
- Both gate scripts and both smoke scripts pass; delete this plan in the implementing change.
