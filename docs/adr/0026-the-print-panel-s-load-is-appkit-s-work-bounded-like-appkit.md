# 0026. The print panel's load is AppKit's work, bounded like AppKit's own loops

- Status: accepted
- Date: 2026-11-27

## Context and problem

**Why.** Tours that passed every check still logged main-actor pauses of 0.5–2 s, and some
failed on a 1.2 s `mainActorStall`. A tour profiled throughout (agent-drive 46004639447) put the
stall in `-[NSPrintPanel beginSheetWithPrintInfo:…]`: a synchronous XPC call to the print agent
for the default printer, PrintingUI's nibs, and a `dlopen` of PrintingPrivate. The app's own code
was one sample of it. Probing each panel in its own minute (46007142113) measured the first print
panel at 1.4 s and a second at 0.5 s in Debug; the Release tour (46007567920) measured 2 s. The
main thread stays in the default mode throughout, so the run-loop classification cannot see it.
Whether the watchdog reported it depended on whether AppKit happened to spin a private loop
during the load, so the tour's verdict was chance.

## Decision drivers

**Criteria:** a fault must mean the app stalled (CLAUDE.md §3); a print that never returns must
still be reported, as the print activity's wedge was; the tour must be deterministic; no new
prompt or launch cost (vision.md, objectives 4 and 7).

## Considered options

| Option | Fault means the app stalled | A hung print still reported | Deterministic | No new cost or prompt |
| --- | --- | --- | --- | --- |
| **Bounded AppKit-work session around the sheet's start (chosen)** | ✓ | ✓ at 10 s | ✓ | ✓ |
| An unbounded app-modal session (`around`) | ✓ | ✗ a hang would never be reported | ✓ | ✓ |
| Warm the print system in the background at launch | ~ only the warmed part | ✓ | ~ | ✗ wakes the print agent every launch, and Print brought macOS's local-network prompt |
| Do nothing | ✗ | ✓ | ✗ | ✓ |

## Decision

**Decision.** File › Print begins its sheet inside `AppModalSession.aroundAppKitWork`. While that
runs, the watchdog treats the main thread as waiting in AppKit's own loop, reported only past ten
seconds, and the latency probe drops the samples it spans. REQ-096, REQ-124 and architecture.md §10
state it.

## Consequences

**Where it is worse.** The person still waits up to two seconds the first time they print, and no
metric now shows it. That wait is AppKit's, as long in TextEdit, and nothing the app does shortens
it. A stall of the app's own during those seconds is hidden with it, since the main actor could
not run then anyway.

## Confirmation

REQ-096 and REQ-124's tests (`MacOSCitizenshipTests`, `WorkLedgerTests`) cover `AppModalSession.aroundAppKitWork` and the latency probe's dropped samples.

## Retirement proof

A print panel whose first load no longer blocks the main thread.

## Reversal plan

Begin the print sheet outside the bounded session.
