# 0029. A document window's content stays SwiftUI

- Status: accepted
- Date: 2026-11-27

## Context and problem

**Why.** Release profiles of window opening (probes 46014139254, 46018864413) put most of the cost
in the window's first layout, spread over SwiftUI's view graph, the Swift runtime, CoreFoundation
and AppKit layout, with no hotspot; the app's own code is 48 of 345 samples (the toolbar 40, both
editors 8). SwiftUI is roughly a third of the rest. The tour's latency notes that remain come from
its pace, several such operations a minute, while every section alone holds a p95 under 1 ms
(probes 46023988152, 46028521303).

## Decision drivers

**Criteria:** vision.md's objective order (correct editing first, fast and light seventh); CLAUDE.md §1,
SwiftUI-first with narrow AppKit adapters; cost and risk.

## Considered options

| Option | Product direction | Expected gain | Risk |
| --- | --- | --- | --- |
| **Keep SwiftUI content (chosen)** | ✓ | none | none |
| Rebuild the window's content in AppKit | ✗ reverses §1 | about a third of a window's opening, not the first window's first-use costs | every binding `ContentView` owns: sessions, sheets, alerts, toolbar |
| Build the Source editor lazily | ✓ | 10–20 ms (2026-11-27, "The first window is laid out once") | REQ-052's persistent editors |

## Decision

**Decision.** The document window keeps its SwiftUI content (`ContentView` in an
`NSHostingController`). Opening a window, 0.15–0.3 s warm and 0.6–0.9 s for a process's first on
a CI runner, is not cut by rebuilding that content in AppKit.

## Consequences

**Where it is worse.** A window still takes a perceptible moment to open on a slow machine, and
the tour keeps logging the minutes that open several.

## Confirmation

The window's content is `ContentView` in an `NSHostingController`; REQ-052's persistent-editor tests cover the SwiftUI host.

## Retirement proof

A profile on a real Mac in which SwiftUI's first layout is the dominant, avoidable cost of opening a window.

## Reversal plan

Rebuild the window's content in AppKit: every binding `ContentView` owns (sessions, sheets, alerts, toolbar) moves.
