# ADR-0007 — Editor surface: stock SwiftUI TextEditor (interim, INC-01 only)

- **Status:** Accepted (interim)
- **Date:** 2026-07-22
- **Deciders:** Toni Melisma
- **Related:** [ADR-0002](0002-swiftui-first-appkit-where-needed.md), [ADR-0006](0006-document-model-filedocument.md); [RESEARCH-0001](../research/0001-inc01-editor-foundation.md); INC-01, SPIKE-01, INC-02

> Living decision — **interim by design.** SPIKE-01 owns the definitive text-engine choice;
> this ADR will be updated/superseded when INC-02 adopts it.

## Context

INC-01 is a plain-text editor foundation, and the discovery/build separation
([ADR-0005](0005-discovery-and-build-are-separate-units.md)) places the text-engine spike
(**SPIKE-01**) *after* INC-01. So INC-01's editor must **not** pre-decide the engine.

- **Stock `TextEditor`** — plain-text editing with ~zero code; undo/redo + spell-check come
  free; but no syntax styling and no reliable system Find bar; gained rich text in macOS 26.
- **`NSTextView` via `NSViewRepresentable`** — native find/spell-check/undo and full control,
  but state-sync pitfalls, and choosing it now pre-empts SPIKE-01 (TextKit 1 vs 2 vs a
  third-party view).

## Decision

Use the **stock SwiftUI `TextEditor`** for INC-01. It keeps the increment tiny and commits to
no text engine, leaving that choice entirely to SPIKE-01.

## Consequences

- **Positive:** minimal, idiomatic; undo/redo + spell-check inherited; no premature engine lock-in.
- **Negative / costs:** no syntax styling; **find/replace deferred to INC-02**; the `TextEditor`
  is largely **throwaway** — INC-02 replaces it with the SPIKE-01-chosen `NSTextView`-based
  surface.
- **Revisit trigger:** SPIKE-01 selects the engine; **INC-02** swaps the surface and this ADR
  is updated/superseded accordingly.

## Alternatives considered

- **`NSTextView` wrapper now** — rejected for INC-01: pre-empts SPIKE-01 and adds complexity
  before it's needed.
- **Third-party text view (e.g. STTextView)** — a SPIKE-01 candidate, not an INC-01 choice.
