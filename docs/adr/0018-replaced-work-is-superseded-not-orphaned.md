# 0018. Replaced work is superseded, not orphaned

- Status: accepted
- Date: 2026-11-27

## Context and problem

**Why.** Latest-wins scheduling cancels work by design: every keystroke supersedes the parse in
flight. All of it was recorded as a fault, so every document open and every burst of fast typing
logged one, and `smoke-test.sh` admitted orphaned intents wholesale. That allowance hid a real
defect: `bind(editorWindow:)` compared the window's scale with the previous window's, the first
window has none, and every open parsed the document twice.

## Decision drivers

**Criteria:** faults that mean something (a pristine run has none), honesty of the record, cost.

## Considered options

| Option | Faults mean something | Honest | Cost |
| --- | --- | --- | --- |
| **Classify superseded work (chosen)** | ✓ | ✓ the record says why the work stopped | one symbol, one parameter |
| Keep orphans as faults, allow them in every verifier | ✗ a real orphan hides among expected ones | ✓ | none |
| Stop recording cancelled work | ✓ | ✗ the work done is lost from the ledger | small |

## Decision

**Decision.** An intent whose work was cancelled because newer demand replaced it, or because its
session went away, finishes as `superseded`. It is recorded at debug level with that reason.
Only work that ends incomplete for any other reason (an orphan) or arrives after its intent closed
(`lateWork`) is a fault.

## Consequences

**Where it is worse.** Wasted work is now only visible by counting parses. The double parse at open
was found that way, and it is fixed, not reclassified.

## Confirmation

`WorkLedgerTests` classify superseded, orphaned and late work; `Scripts/smoke-test.sh` no longer admits orphans.

## Retirement proof

A scheduler that never cancels work, so nothing is superseded.

## Reversal plan

Record cancelled work as a fault again; the smoke allowance would have to return.
