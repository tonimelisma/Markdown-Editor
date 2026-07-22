# ADR-0002 — SwiftUI-first; AppKit only where SwiftUI can't reach

- **Status:** Accepted
- **Date:** 2026-07-21
- **Deciders:** Toni Melisma
- **Related:** [VISION §6](../VISION.md); SPIKE-01 (text engine) will refine the AppKit boundary

## Context

The app is pure Swift and aims to be as idiomatic and modern as possible. SwiftUI is the
native-first UI framework; AppKit is the mature, lower-level toolkit. Some capabilities a
Markdown editor needs — most notably a real text-editing surface with live syntax styling —
are not reachable from pure SwiftUI today and require `NSTextView`/TextKit via
`NSViewRepresentable`.

## Decision

**SwiftUI-first.** Build UI in SwiftUI wherever it can deliver. Drop to AppKit only where
SwiftUI genuinely can't reach, and wrap those pieces behind clean, testable seams. The primary
expected AppKit surface is the text editor; the specific engine (TextKit 1 vs 2 vs a
third-party view) is **not decided here** — it is the subject of SPIKE-01.

## Consequences

- **Positive:** modern, low-boilerplate UI; system behaviors (document handling, menus) come
  largely for free; AppKit complexity is contained.
- **Negative / costs:** the SwiftUI⇄AppKit bridge is a known source of friction (focus, undo,
  first-responder, layout) that we must engineer carefully.
- **Follow-ups:** SPIKE-01 decides the text engine and the exact bridge; record it as an ADR.

## Alternatives considered

- **All-AppKit:** rejected — heavier, less idiomatic for a greenfield 2026 app.
- **All-SwiftUI (stock `TextEditor`):** rejected — cannot do syntax styling or the control a
  Markdown editor needs.
