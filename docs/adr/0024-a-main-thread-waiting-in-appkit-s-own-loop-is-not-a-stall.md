# 0024. A main thread waiting in AppKit's own loop is not a stall until ten seconds

- Status: accepted
- Date: 2026-11-27

## Context and problem

**Why.** After every other fix, a tour (45986962172) still failed on a 1 s main-actor stall after
File › Duplicate. A sample of the same step (probe 45982413288) showed the main thread in AppKit's
title-bar rename session, waiting on its remote view service in a private run-loop mode that
serves no queue. Nothing in the app ran, and the person saw the title become editable. On a
runner the wait sometimes passes a second, so the tour failed or passed by chance.

## Decision drivers

**Criteria:** a fault must mean the app is stalled (CLAUDE.md §3); a real deadlock must still be
reported, as the close hang was, in a private mode; the tour's verdict must not depend on chance.

## Considered options

| Option | Fault means the app stalled | Deadlock in AppKit's loop caught | Deterministic tour |
| --- | --- | --- | --- |
| **Classify by run-loop mode, bound private waits at 10 s (chosen)** | ✓ | ✓ at 10 s | ✓ |
| Wrap each AppKit call that waits in an app-modal session | ✓ where wrapped | ✓ | ✗ the rename starts after our call returns; there is no hook |
| Exclude private modes without a bound | ✓ | ✗ the close hang would go unreported | ✓ |
| Raise the threshold for everyone | ✗ hides real one-second stalls | ✓ | ~ |
| Do nothing | ✗ | ✓ | ✗ |

## Decision

**Decision.** The watchdog reads the main run loop's mode when a hop misses its one-second
threshold. In a mode that serves the main queue (default, event tracking, modal panel), it reports
a stall at once, as before. In any other mode it waits, and reports only if the wait outlasts ten
seconds or the loop returns to a serving mode. The latency probe drops every sample pending across
such a wait. REQ-096 and architecture.md §10 state it.

## Consequences

**Where it is worse.** A deadlock in one of AppKit's private loops is reported after ten seconds,
not one. A stall in the app's code that happens while AppKit waits in such a loop is hidden for as
long as the loop runs, since the main actor could not run then anyway.

## Confirmation

REQ-096's tests cover the watchdog's run-loop-mode classification and the ten-second bound.

## Retirement proof

AppKit's private loops serving the main queue, or a hook around each AppKit wait.

## Reversal plan

Report every one-second miss as a stall again; the tour's verdict becomes chance again.
