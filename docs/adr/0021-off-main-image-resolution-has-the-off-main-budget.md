# 0021. Off-main image resolution has the off-main budget

- Status: accepted
- Date: 2026-11-27

## Context and problem

**Why.** The tour's log reported `imageResolution` over budget at 19.7 ms on opening the showcase
document. The stage reads, inspects and decodes image files in the parse task, off the main actor
(REQ-090 requires that). No frame waits on it, so the frame budget described nothing the person
sees, and it warned on every rich document opened on a slow machine.

## Decision drivers

**Criteria:** a measurement must bound what it describes (CLAUDE.md §3); a warning in the log must
mean something the person would notice; cost.

## Considered options

| Option | Bound describes the stage | Warning means a problem | Cost |
| --- | --- | --- | --- |
| **100 ms, the off-main allowance (chosen)** | ✓ the parse task's whole result waits on it | ✓ | none |
| Keep 16 ms | ✗ a frame, for work no frame waits on | ✗ every rich open on a slow Mac | none |
| Remove the metric | ✗ unbounded work then goes unmeasured | — | loses the decode cost's only number |
| Move decoding lazily onto display | ✗ puts decode work on the main actor, which REQ-090 forbids | — | large |

## Decision

**Decision.** `imageResolution` is budgeted at 100 ms p95, as the other off-main stages
(`parseProjection`, `sourceHighlightCompute`) are, not at a 16 ms frame.

## Consequences

**Where it is worse.** A decode slower than a frame but under 100 ms no longer warns. The person
sees it only as an image arriving that much after the text, which the 100 ms covers.

## Confirmation

`PerformanceBudgetTests` hold `imageResolution` to the off-main allowance; `Scripts/verify-smoke-log.py` knows the metric.

## Retirement proof

Image decoding moving onto a path a frame waits on.

## Reversal plan

Return the metric to the 16 ms frame budget.
