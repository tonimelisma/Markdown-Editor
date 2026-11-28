# 0028. A p95 is judged from twenty samples or more

- Status: accepted
- Date: 2026-11-27

## Context and problem

**Why.** Each document's sampler flushes every minute. A document opened and edited a few times
gave summaries of 4 to 12 samples. The nearest-rank p95 of fewer than 20 samples is their
largest, so each such summary judged the document's one first layout after opening (34–40 ms) as
if it were a p95 (tours 46012382716, 46013947916). Those were most of the tours' remaining
budget notes, and none of them was a p95.

## Decision drivers

**Criteria:** a recorded verdict must mean what it says (CLAUDE.md §3, "A measurement describes
only the input it was measured on"); no sample is dropped; the budget still binds where it can.

## Considered options

| Option | Verdict means a p95 | No sample dropped | Binds on a short-lived document |
| --- | --- | --- | --- |
| **Twenty or more, carrying the rest (chosen)** | ✓ | ✓ | ✗ fewer than twenty edits are never judged |
| Judge every summary, as before | ✗ judges the largest sample | ✓ | ✓ |
| A separate budget on the largest sample | ✓, as a different bound | ✓ | ✓, but no such bound is written down |
| Do nothing | ✗ | ✓ | ✓ |

## Decision

**Decision.** A performance summary is written once a metric has at least 20 samples; fewer
carry into the next minute. When a sampler ends with fewer, its summary is written, largest
included, and its p95 is not judged against the budget. REQ-103 states it.

## Consequences

**Where it is worse.** A document closed after fewer than twenty samples of a metric is never
judged against its budget, however slow each was; its summary still shows the largest.

## Confirmation

REQ-103's tests (`PerformanceBoundaryTests`) write a summary only after twenty samples and leave a shorter final summary unjudged.

## Retirement proof

A separate, written-down bound on the largest sample of a short-lived document.

## Reversal plan

Judge every summary again; short documents' first layouts read as p95s again.
