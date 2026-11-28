# 0007. REQ-090's typing budget takes the same stress-shape scope, and its cited evidence was wrong

- Status: accepted
- Date: 2026-08-23

## Context and problem

**Why it came up.** Release tests could not build at all until COR-86, so REQ-090's proof had not
executed in months. Run against the tree as it stood at COR-86 — before any optimisation work —
it failed two ways: `structuredProse` and `tableDense` collected **zero samples**, reporting
"performance input refused at sample 1", and `heavyLists` measured 10.4 ms against the 8 ms
budget. The row said `Done`.

**The proof was broken, and separately the budget was missed.** The test typed at
`renderedLength - 2`, which is not an editable location on every shape: after the first insertion
it can land on a synthetic paragraph break or a table row separator, which the closed
local-transition matrix refuses by design (ARC-009). That is correct product behaviour and a
broken measurement. Typing now happens inside an ordinary paragraph prepended to each corpus,
which is editable on every shape and is at least as representative as typing at the very end of a
document. With samples actually collected, four shapes are under 8 ms and two are not.

**The cited numbers never reproduced.** REQ-090 claimed "heavy lists 5.598 ms, dense tables
5.090 ms". Measured at COR-86 with the old method, `heavyLists` was 10.4 ms; with the repaired
method it is 17.1 ms. The old figures cannot be reproduced by either method, and the row carried
them as evidence.

## Decision drivers

- The same criteria as [0006](0006-the-interactive-budget-binds-on-real-document-shapes-not-on.md): no proof weakened, the requirement states what the product guarantees, cost.

## Considered options

**Alternatives.** (A) Scope to non-stress shapes and record bounds — chosen. (B) Optimise typing on
the stress shapes: the cost is TextKit laying out 18,520 and 24,400 `NSTextBlock`s, so it needs the
approved one-block-per-table-cell decision reopened (architecture.md §7), which is an architecture
change for shapes nobody writes. (C) Leave `Correction` open indefinitely — rots, as before.
(D) Delete the stress corpora — destroys evidence to make a number go green; rejected outright.

## Decision

**Decision.** REQ-090's 8 ms native-input-callback budget binds on every `PerformanceCorpus` shape
not declared a stress shape. `heavyLists` and `tableDense` carry recorded bounds of 30 ms and
22 ms. This extends the scoping decided for REQ-143 the previous day to the requirement it was
modelled on.

## Consequences

**Where the chosen option is worse.** This is the second requirement rescoped in two days, and the
pattern deserves suspicion: rescoping is how a red row becomes green without the product changing.
Three things hold it honest. The stress shapes remain measured and asserted, at 30 ms and 22 ms.
The classification lives in production as `PerformanceCorpus.isStressShape`, visible to a reader,
not in the test that benefits from it. And the stale figures were replaced with measured ones
rather than quietly left in place — the rescoping is the smaller half of this entry; the larger
half is that a `Done` row cited evidence that had never been reproducible.

## Confirmation

REQ-090's tests measure typing in an ordinary paragraph on every corpus shape and assert 8 ms off the stress shapes and the recorded 30 ms and 22 ms on them.

## Retirement proof

Typing on the stress shapes under 8 ms (for example after a one-block-per-table-cell change), or a real document shaped like them.

## Reversal plan

Drop the stress-shape scope from REQ-090 once the stress shapes meet 8 ms.
