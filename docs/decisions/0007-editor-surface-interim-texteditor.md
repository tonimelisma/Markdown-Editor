# ADR-0007 — Editor surface: stock SwiftUI TextEditor (interim, INC-01 only)

- **Status:** Superseded by ADR-0008 (implemented in INC-02)
- **Date:** 2026-07-22
- **Deciders:** Toni Melisma
- **Related:** [ADR-0002](0002-swiftui-first-appkit-where-needed.md), [ADR-0006](0006-document-model-filedocument.md); [RESEARCH-0001](../research/0001-inc01-editor-foundation.md); INC-01, SPIKE-01, INC-02

> Historical decision — **interim by design.** SPIKE-01 selected TextKit 1 and INC-02 replaced
> this surface with `MarkdownTextView`; see [ADR-0008](0008-textkit1-nstextview-editor-engine.md).

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
- **Outcome:** SPIKE-01 selected TextKit 1 and INC-02 swapped the surface as planned. This ADR
  is superseded and retained only as the INC-01 historical record.

## Alternatives considered

- **`NSTextView` wrapper now** — rejected for INC-01: pre-empts SPIKE-01 and adds complexity
  before it's needed.
- **Third-party text view (e.g. STTextView)** — a SPIKE-01 candidate, not an INC-01 choice.
