# ADR-0002 — SwiftUI-first; AppKit only where SwiftUI can't reach

- **Status:** Accepted
- **Date:** 2026-07-21; revised 2026-07-25
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
SwiftUI genuinely can't reach, and wrap those pieces behind clean, testable seams. SPIKE-01
selected TextKit 1 for Source/WYSIWYG editing. SPIKE-02 selected `NSDocument` for document,
window, Save, URL, and undo ownership while retaining SwiftUI-hosted editor content.

## Consequences

- **Positive:** modern, low-boilerplate UI; system behaviors (document handling, menus) come
  largely for free; AppKit complexity is contained.
- **Negative / costs:** the SwiftUI⇄AppKit bridge is a known source of friction (focus, undo,
  first-responder, layout) that we must engineer carefully.
- **Follow-ups:** ADR-0008 records TextKit 1. ADR-0006 and COR-04 record the `NSDocument` boundary.

## Alternatives considered

- **All-AppKit:** rejected — heavier, less idiomatic for a greenfield 2026 app.
- **All-SwiftUI (stock `TextEditor`):** rejected — cannot do syntax styling or the control a
  Markdown editor needs.
