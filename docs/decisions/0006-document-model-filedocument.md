# ADR-0006 — Document model: FileDocument (for now)

- **Status:** Accepted
- **Date:** 2026-07-22
- **Deciders:** Toni Melisma
- **Related:** [ADR-0002](0002-swiftui-first-appkit-where-needed.md), [ADR-0007](0007-editor-surface-interim-texteditor.md); [RESEARCH-0001](../research/0001-inc01-editor-foundation.md); INC-01

> Living decision — reassessed during INC-02; `FileDocument` remains adequate for the current
> single-document, local-first editor (see "Revisit trigger").

## Context

A SwiftUI document-based app can back its documents with one of three models. For a plain-text
Markdown editor the differences that matter are undo fidelity, autosave control, large-file
handling, and how much boilerplate we take on. (Full comparison: RESEARCH-0001.)

| Option | Type | Undo / autosave | Large files | Cost |
|---|---|---|---|---|
| **`FileDocument`** | value (struct) | autosave + Versions free; undo tracking awkward; no autosave-timing control | whole file in memory | lowest |
| **`ReferenceFileDocument`** | class | background autosave tied to `UndoManager` | `FileWrapper`-based | medium |
| **`NSDocument`** | class (AppKit) | full control | URL access, streamable | highest |

Autosave in all three is the standard macOS **Auto Save + Versions** (the TextEdit experience).

## Decision

Use **`FileDocument`** for INC-01. It is the simplest, most idiomatic SwiftUI choice, pairs
naturally with the interim `TextEditor` surface ([ADR-0007](0007-editor-surface-interim-texteditor.md)),
and gives autosave + Versions for free.

## Consequences

- **Positive:** minimal code; standard document lifecycle, tabs, Recents, and Versions inherited.
- **Negative / costs (accepted for now):** awkward undo tracking, no control over autosave
  timing, and the whole file lives in memory (fine for typical Markdown, not for huge files).
- **Revisit outcome / trigger:** INC-02 retained `FileDocument`; the TextKit 1 wrapper binds the
  same string-backed document model and did not require a model change. Re-evaluate if undo
  fidelity (INV-1 no data loss), large files, or external-change handling prove inadequate —
  likely moving to `ReferenceFileDocument` or `NSDocument`.

## Alternatives considered

- **`ReferenceFileDocument`** — better undo/autosave story; deferred as unnecessary complexity
  while the editor is a plain `TextEditor`.
- **`NSDocument`** — most control and real large-file support; rejected for now as heavy and
  least SwiftUI-idiomatic.
