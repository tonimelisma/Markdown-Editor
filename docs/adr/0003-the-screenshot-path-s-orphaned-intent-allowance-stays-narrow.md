# 0003. The screenshot path's orphaned-intent allowance stays narrow

- Status: accepted
- Date: 2026-08-22

## Context and problem

Kept here because roadmap.md's delivery ledger, where they used to live, is gone.

**`Scripts/smoke-screenshot.sh --allow-orphaned-intents`** (COR-83). The screenshot capture path
terminates the app mid-open, so the work ledger honestly reports a cancelled intent. The flag
admits **only** records whose own data marks them orphaned. It is not a general suppression and
must not become one. `smoke-test.sh` passed it too, which hid a double parse on every open; since
2026-11-27 replaced work is recorded as superseded, not orphaned, and `smoke-test.sh` no longer
passes the flag.

## Decision drivers

- A suppression flag must admit only what its own records mark as expected.
- An allowance must not hide a real defect (it once hid a double parse on every open).

## Considered options

### Admit orphaned intents only on the screenshot path, only when their own data marks them (chosen)

- Good: the capture path's honest cancellation passes; nothing else does.

### A general suppression

- Bad: hides real orphans, as it did in `smoke-test.sh`.

## Decision

As stated in the context above.

## Consequences

As stated above.

## Confirmation

`Scripts/test-verify-smoke-log.sh` runs the verifier over `Scripts/Fixtures/SmokeLogs/` (orphaned and late-orphaned intents among them) in the gate; `smoke-test.sh` does not pass the flag.

## Retirement proof

A screenshot capture that lets the app finish its open before terminating it, so no intent is cancelled.

## Reversal plan

Remove the flag from `smoke-screenshot.sh` once capture no longer cancels work.
