# COR-33 — Fenced code content is not an identity mapping in CRLF documents

- **Status:** Approved; not implemented
- **Delivers:** REQ-113

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

## Alternatives considered and rejected

**Option 1 — emit code content from the concrete source span instead of cmark's literal.**
Identity would hold under any line ending because the projection would carry source bytes. But
the projection is *what the user sees*: it would then contain literal `\r` characters inside code
blocks, which TextKit renders as stray control characters, and it breaks the rule that the
projection is delimiter-free rendered content rather than a copy of source. **Rejected.**

**Option 3 — disable `.codeBlock` in CRLF documents.**
Honest and small: REQ-113 makes `enabled` a promise, so a command that cannot perform must not
claim it can. But it leaves existing fenced code uneditable in CRLF documents with no plan, and
it silently splits the product's capabilities by the user's line-ending convention — something
VISION never contemplates and no requirement states.

## Approved approach

**Atomic code-block content with a proven `\r\n`↔`\n` decoder, in two stages.**

ENGINEERING §6 case 2 exists for exactly this: "visible content differs from source spelling, but
a concrete decoder and inverse encoder prove the transformation." The decoder is total and
provably invertible — each `\r\n` in the source span maps to one `\n` in the projection, and the
inverse re-expands using the document's own line-ending convention, which REQ-007 already
requires the document to preserve.

Chosen over the alternatives because:

1. It is the only option that fixes the actual defect. Options 1 and 3 address the command; the
   measured cause is that *all* code-block content is uneditable under CRLF, which affects
   reading and editing an existing document, not merely creating a new block.
2. It uses a mechanism the architecture already defines rather than inventing one. `.atomicText`
   with a proven decoder/encoder is precisely ENGINEERING §6 case 2, and
   `ProjectionSelectionClassifier` already has an `.atomicText` path with an
   `AtomicRepresentationKind`.
3. The proof obligation is unusually tractable. Most atomic representations must reason about
   escapes; this decoder is a pure function over one source span with a finite, testable inverse.

### Stage 1 — availability honesty (no architecture gate; do this first)

REQ-113 says an `enabled` command performs. `.codeBlock` currently reports `enabled` in a CRLF
document and then refuses, so **REQ-113 is presently violated** and is marked `Correction`
against this increment.

Stage 1 corrects only availability: `EditorCommandController.availability(for:)` must report
`.codeBlock` as disabled when the target document's code content cannot be projected editably.
This ships independently, needs no architecture change, and makes the promise honest while
stage 2 is designed. It does **not** make code blocks editable and must not be described as
fixing this defect.

The availability predicate must be derived from the same projection facts the editor already
has — a segment classified `.uneditable` covering the target — not from sniffing the document for
`\r\n`. A line-ending sniff would be a second source of truth about editability, which is
precisely the duplicate-authority pattern ENGINEERING forbids.

### Stage 2 — atomic code content (requires the architecture change gate)

Stage 2 changes the projection's atom vocabulary and therefore cannot proceed from this plan
alone. ENGINEERING §15 requires, before production code: a reproduced counterexample (the probe
in this plan supplies it), fresh research including real API probes, credible options compared
against the architecture drivers, explicit approval, an atomic ENGINEERING and requirements
update, an executable proof that would fail under the old behaviour, and deletion of the
displaced path in the same build.

**That discovery unit is DISC-02 in ROADMAP.** Stage 2 must not begin until DISC-02 closes with
explicit approval. If DISC-02 concludes the atom vocabulary should not change, stage 1 stands and
this plan is rewritten around whatever DISC-02 approves — it is not silently widened.

## Automated non-UI proof

**Stage 1.** A test that `.codeBlock` reports disabled availability in a CRLF document and
enabled in the equivalent LF document, driven through the real `EditorCommandController`. Add the
CRLF document to `CommandLivenessMatrixTests`' matrix as an explicitly declared
`notASourceMutation`/disabled cell, so the closed-set gate covers it rather than the exclusion
living in a comment.

**Stage 2.** Extend `lineReshapingCommandsApplyInCRLFWYSIWYGDocuments` to include `.codeBlock` —
it must fail before the change. Add:

- a decoder round-trip table over `\r\n`, `\n`, a lone `\r`, a CRLF file whose final line has no
  terminator, and a fenced block containing a blank line;
- a proof that editing one line of a fenced block in a CRLF document leaves every other line's
  terminator byte-identical (REQ-007);
- a proof that LF documents produce byte-identical output to today, so the change is provably
  scoped to CRLF;
- the oracle assertions for the new atom kind, since `ProjectionOracle` validates exact
  round-trip mappings where promised.

## Failure and rollback behavior

If no exact mapping can be proven, option 3 is taken: the command is disabled rather than left
enabled-and-refusing, because REQ-113 makes "enabled" a promise. Source is never rewritten to
make the mapping work.

## Deletion and conformance gate

- No line-ending normalisation may be introduced into canonical source (REQ-007). The fix makes
  the *projection* tolerant of CRLF; it never rewrites the user's line endings.
- Prove one editability predicate: stage 1's availability rule must read the projection's own
  classification, with no second line-ending test anywhere in production.
- Both gate scripts and both smoke scripts pass. Delete this plan only when **both** stages have
  landed, or rewrite it if DISC-02 approves a different stage 2 — a plan that has delivered only
  stage 1 is not implemented.
