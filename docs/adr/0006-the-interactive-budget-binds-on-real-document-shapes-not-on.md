# 0006. The interactive budget binds on real document shapes, not on stress shapes

- Status: accepted
- Date: 2026-08-22

## Context and problem

REQ-143's 16 ms interactive budget failed on two corpus shapes nobody writes (a table row every 1.2 characters, a list item every 4.3), while real-document shapes passed. The choice was between rescoping the requirement and rewriting the parse strategy.

## Decision drivers

**Criteria**, from vision.md's objective ordering: (1) preservation and correctness — no proof may be
weakened; (2) honesty — the requirement must state what the product actually guarantees; (3) user
value; (4) implementation and maintenance cost, and risk to the parse path everything depends on;
(5) reversibility.

## Considered options

**Alternatives.**

- **A — rescope, declare the stress shapes** (chosen). Weakens no proof. Costs nothing. The two
  stress shapes stay asserted against recorded ceilings, so they cannot silently regress.
- **B — bounded reparse.** Reparse the enclosing block and splice, checking
  `splice == parse(whole)` over the 1,324 spec examples. The only design that closes all six. Best
  on user value in principle, worst on cost and risk: it touches the parse path everything else
  depends on, and the equivalence may simply not hold for lazy continuations or link reference
  definitions.
- **C — leave REQ-143 in `Correction` indefinitely.** Honest, costs nothing, weakens nothing, and
  rots: an open `Correction` nobody intends to close is a to-do disguised as a status.
- **D — delete the two stress corpora.** Rejected outright. It would make the number go green by
  destroying the evidence, which is the failure mode this repository exists to avoid.

**Ranking.** A and B tie on correctness and honesty. B wins on user value *in principle* and loses
it in fact: real documents look like `structuredProse`, which is at 13.1 ms, while `tableDense` is
a table row every 1.2 characters and `heavyLists` a list item every 4.3 — shapes nobody writes. B
is far worse on cost and risk. C loses on honesty over time. A wins.

## Decision

**Decision.** REQ-143's 16 ms budget applies to every `PerformanceCorpus` shape not declared a
stress shape. `heavyLists` and `tableDense` are declared stress shapes in production
(`PerformanceCorpus.isStressShape`) and carry recorded bounds instead. REQ-143 is `Done`.

## Consequences

**Where the chosen option is worse.** A is a requirement change that makes a red row green, which
is exactly the Goodhart move [ADR 0001](0001-the-verification-apparatus-was-removed.md) warns about, and it deserves the suspicion. Three
things distinguish it from moving the goalposts. The stress shapes are still measured and still
asserted, at 50 ms and 55 ms, so nothing stopped being checked. The classification lives in
production as a closed declaration a reader can see, not in the test that would benefit from it.
And the 16 ms target was never reachable on those shapes by any means short of B — a single
authoritative rebuild is 26.9 ms on `tableDense`, so the original requirement asserted something
no implementation short of a parse-strategy rewrite could satisfy.

**Correction, same day.** REQ-143 first said "16 ms p95" and the test asserted worst-of-three
against 16 ms. That failed at 19.9 ms on a run whose median was 13.1 ms — scheduling noise under a
parallel suite, not a regression. A handful of samples cannot express a 95th percentile at all:
`p95` over three samples *is* the maximum. The requirement now says what is actually asserted —
**16 ms for a median command, 32 ms for any command** — which is precise, non-flaky, and honest,
where the p95 wording was none of the three. The Release evidence run in `docs/research/` remains
the place percentile claims can be made.

## Confirmation

REQ-143's tests (`SemanticCommandBudgetTests`) assert 16 ms on every shape where `PerformanceCorpus.isStressShape` is false, and the recorded bounds on `heavyLists` and `tableDense`.

## Retirement proof

**What would reopen it.** A real document that behaves like the stress shapes, or a profile
showing `structuredProse` drifting toward the budget. B remains available and its plan text is in
Git.

## Reversal plan

Implement option B (bounded reparse) and drop the stress-shape exemption; a parse-path change with the equivalence risk described above.
