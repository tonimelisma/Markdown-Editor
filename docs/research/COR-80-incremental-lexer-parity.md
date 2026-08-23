# COR-80 — Incremental/full lexer parity divergences

> **Repaired by COR-84 on 2026-08-22.** Both divergences below are fixed and the property now
> asserts zero disagreement. Retained because the two mechanisms — a newline-admitting character
> class, and a second implementation of a precedence rule — are the kind that recur, and because
> the minimized fixtures are now named regression tests.

- **Authority:** evidence only. Not architecture, not a repair plan.
- **First researched:** 2026-08-22
- **Last verified:** 2026-08-22
- **Environment:** macOS 27.0 (Darwin 27.0.0), Xcode-beta, Debug, `Scripts/check.sh`
- **Method:** `PropertyTests.incrementalHighlightingMatchesAFullRelexAfterEveryEditKind` over
  `GeneratedMarkdown.corpus(seedsPerCell: 1)` — 96 documents × 8 edit operations. Deterministic
  (SplitMix64, fixed seeds); reproduces identically with `-parallel-testing-enabled NO`.
- **Refresh triggers:** any change to `IncrementalSourceHighlighter`, `MarkdownHighlighter`,
  `SourceLineIndex`, or `SourceLexState`.

## What was found

REQ-041 and REQ-045 promise that incremental lexing produces what a fresh full relex produces.
Over the generated corpus it does not, in **30 (document, edit) pairs** — 24 on malformed input,
6 on valid input. Both requirements are therefore back to `Correction`.

`PropertyTests.knownParityDivergences` pins the count at 30. It may only ever go down; a repair
that lowers it turns the property red until the baseline is lowered in the same change, and a new
defect that raises it turns it red immediately.

## Divergence 1 — cross-line bracket matching (24 cases, malformed input)

The full lexer matches link and image bracket constructs **across line boundaries**. An unclosed
`[` on one line pairs with a `](` on a later line, producing a token that spans the newline. The
incremental lexer is line-local by construction and cannot produce it.

Smallest observed case (seed `7553996031648910705`, `deleteBackwardOne` at `{7, 1}`):

```markdown
﻿- [x\*delta\_\`

![the quick brown fox](assets/x.png) bravo charlie *bravo charlie*
```

After the edit, inside changed range `{0, 16}`:

```text
full relex : [Token(range: {3, 13}, style: .link)]
incremental: []
```

`{3, 13}` is `[x\*elta\_\`` plus the trailing newline — the match reaches the`](` on the third
line. Confirmed by direct inspection of the offsets, not inferred.

### Minimized regression fixture

`Shrinker` reduces the 233-character generated document to two lines that still reproduce, which is
what makes the mechanism legible rather than merely recorded:

```markdown
- [x\*delta\_\`
![x](assets/x.png) x *x*
```

Edit: delete one character at UTF-16 offset 7. The same fixture reproduces under
`deleteBackwardOne`, `deleteRange`, and `insertAtDocumentStart`, with and without a leading BOM —
so the BOM and the specific edit are incidental and the unclosed bracket is the cause.

Enforcement is `PropertyTests.knownParityDivergences`, which fails if the count moves in either
direction. This fixture is the readable form of what that number counts.

## Divergence 2 — stale cross-line strikethrough carry (6 cases, valid input)

After an edit that changes line topology — `insertFenceMarker` or `insertNewline` — the
incremental lexer retains a `~~` run the full relex no longer produces. This is the state
`IncrementalSourceHighlighter.crossLineStrikethrough` carries between lines (added by COR-72).

Observed (seed `14222530701490724123`, `insertFenceMarker` at `{60, 0}`), inside `{53, 61}`:

```text
incremental: [Token({55, 20}, .strikethrough), Token({62, 29}, .inlineCode)]
full relex : [Token({62, 29}, .inlineCode)]
```

This is the more serious of the two: the input is well-formed, so it is reachable by ordinary
authoring — type ``` on a line above text containing `~~`.

## Why the existing tests did not find this

`IncrementalSourceHighlighterTests` compares incremental against full in
`editSequenceMatchesFreshFullLexer` and `generatedEditSequencesMatchFreshFullLexer`. Both drive
edits at the **tail of three-line documents**, where the patch's changed range covers everything
after the edit, so a stale carry has nothing later to disagree with. Neither exercises malformed
brackets or a topology change above existing multi-line state.

## Impact

Styling only. Neither divergence touches document bytes, the projection, or the canonical source —
`ProjectionOracle` accepts every document in the same corpus. The user-visible symptom is Source
mode showing a strikethrough or link colour that a full re-open would not show.

## Not repaired here

COR-80's plan states that a discovered defect stops the increment and that production repair needs
its own approved plan. No repair is attempted in this change, and no plan has been written for one —
that requires approval.
