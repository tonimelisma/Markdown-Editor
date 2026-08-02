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

## Cause — measured, and not what this plan first assumed

A throwaway probe parsed four fixtures through the real `MarkdownParser` and
`MarkdownProjectionModel` and dumped the resulting segments:

| Fixture | cmark `literal` | Projection segment |
| --- | --- | --- |
| LF fenced | `"let a = 1\nlet b = 2\n"` | `.source proj={0,20} src={4,20}` — lengths match |
| **CRLF fenced** | `"let a = 1\nlet b = 2\n"` | **`.uneditable(ambiguous)`** |
| **CRLF indented code** | `"let a = 1\n"` | **`.uneditable(ambiguous)`** |
| CRLF paragraphs | — | `.source` segments, lengths match |

Two corrections to this plan's original text:

1. cmark normalises CRLF to LF in the literal — **confirmed**.
2. The compiler does **not** emit a mismatched source-backed run, as this plan first claimed. It
   already detects that it cannot prove the mapping and emits `.uneditable(ambiguous)`. ARC-007 is
   upheld — the system refuses rather than guessing. The original wording accused the compiler of
   a fidelity bug it does not have, and that error is recorded here rather than quietly edited
   away.

The true consequence is broader than the reported symptom: **in a CRLF document, all code-block
content — fenced and indented — is uneditable in WYSIWYG.** The `.codeBlock` *command* then
refuses as a second-order effect, because after its mutation the new source contains a fenced
block whose content is uneditable, so the post-command caret has no projection preimage.

CRLF paragraphs are unaffected: a paragraph's text contains no interior newline, so its segment
lengths match. That is why COR-26's terminator fix made every other line-reshaping command work
under CRLF while `.codeBlock` alone stayed refused.

## Options, compared against the measured behaviour

**Option 1 — emit code content from the concrete source span instead of cmark's literal.**
Identity would hold under any line ending because the projection would carry source bytes. But
the projection is *what the user sees*: it would then contain literal `\r` characters inside code
blocks, which TextKit renders as stray control characters, and it breaks the rule that the
projection is delimiter-free rendered content rather than a copy of source. **Rejected.**

**Option 2 — represent code content as an atomic atom with a proven `\r\n`↔`\n` decoder.**
ENGINEERING §6 case 2 exists for exactly this: "visible content differs from source spelling, but
a concrete decoder and inverse encoder prove the transformation." The decoder is total and
provably invertible here — each `\r\n` in the source span maps to one `\n` in the projection, and
the inverse re-expands using the document's own line-ending convention, which REQ-007 already
requires the document to preserve. It fixes the general defect (code blocks become editable in
CRLF documents), not just the command symptom. **Architecture impact: touches ENGINEERING §6's
atom vocabulary and ARC-007's proof obligations, so it requires the architecture change gate
before implementation.**

**Option 3 — disable `.codeBlock` in CRLF documents.**
Honest and small: REQ-113 makes `enabled` a promise, so a command that cannot perform must not
claim it can. But it leaves existing fenced code uneditable in CRLF documents with no plan, and
it silently splits the product's capabilities by the user's line-ending convention — something
VISION never contemplates and no requirement states.

## Recommendation

**Option 2, preceded by the architecture change gate.** Reasons, in order:

1. It is the only option that fixes the actual defect. Options 1 and 3 address the command; the
   measured cause is that *all* code-block content is uneditable under CRLF, which affects
   reading and editing an existing document, not merely creating a new block.
2. It uses a mechanism the architecture already defines rather than inventing one. `.atomicText`
   with a proven decoder/encoder is precisely ENGINEERING §6 case 2, and
   `ProjectionSelectionClassifier` already has an `.atomicText` path with an
   `AtomicRepresentationKind`.
3. The proof obligation is unusually tractable. Most atomic representations must reason about
   escapes; this decoder is a pure function over one source span with a finite, testable inverse.

**Interim measure while option 2 is unbuilt:** apply option 3's *availability* correction only —
`.codeBlock` must not report `enabled` in a document whose code content is uneditable. That keeps
REQ-113's promise honest without pretending the deeper defect is fixed, and it is worth doing in
this increment's first phase rather than leaving a command that claims it can act and cannot.

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
