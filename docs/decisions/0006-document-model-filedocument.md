# ADR-0006 — Document model: FileDocument (for now)

- **Status:** Accepted
- **Date:** 2026-07-22
- **Deciders:** Toni Melisma
- **Related:** [ADR-0002](0002-swiftui-first-appkit-where-needed.md), [ADR-0007](0007-editor-surface-interim-texteditor.md); [RESEARCH-0001](../research/0001-inc01-editor-foundation.md); INC-01

> Living decision — reassessed during INC-02 and SPIKE-02. `FileDocument` remains the accepted
> implementation until the user explicitly approves a replacement. SPIKE-02's executable evidence
> recommends `NSDocument` before INC-04; no migration has been accepted or started.

## Context

A document-based app can back its documents with one of the following models. For a plain-text
Markdown editor the differences that matter are undo fidelity, autosave control, large-file
handling, SDK stability, and how much boilerplate we take on. (Original comparison:
RESEARCH-0001; current investigation: RESEARCH-0007.)

| Option | Type | Undo / autosave | Large files | Cost |
|---|---|---|---|---|
| **`FileDocument`** | value (struct) | autosave + Versions free; undo tracking awkward; no autosave-timing control | whole file in memory | lowest |
| **macOS 27 SwiftUI `Document`** | reference (`@Observable`) | explicit undo; coordinated async URL I/O | direct URL access | medium; beta API |
| **`ReferenceFileDocument`** | class | background autosave tied to `UndoManager` | `FileWrapper`-based | deprecated for new types |
| **`NSDocument`** | class (AppKit) | full control | URL access, streamable | highest |

The framework-backed options are evaluated against standard macOS **Auto Save + Versions**
(the TextEdit experience).

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
  the current candidates are macOS 27 SwiftUI `Document` and `NSDocument`.

### Scheduled reassessment for SPIKE-02

COR-02 needed an operation-scoped Save bridge because the value-type SwiftUI document surface
does not directly expose the owning Save operation. INC-04 adds two editable surfaces, semantic
source transactions, cross-mode undo, parser snapshots, and editor-neutral image selection/commit.
Those are concrete revisit signals under this ADR.

macOS 27 also introduces a reference-based SwiftUI `Document` protocol with direct coordinated
URL access, async reading/writing, Observation integration, and explicit undo registration.
Apple deprecates `ReferenceFileDocument` for new macOS 27 document types. SPIKE-02 compared the
new `Document` API, stable `NSDocument`, and retaining `FileDocument` on the real toolchain. Both
reference models compiled under strict Swift 6. The new SwiftUI API did not expose an
operation-scoped Save result and did not remove COR-02's hardest bridge; `NSDocument` directly
provided file URL, Save completion, document-owned undo, autosave, and Versions. The spike
therefore recommends `NSDocument`. The spike does not itself change this decision; any migration
requires a revised ADR, approved requirements, and a separate build plan.

## Alternatives considered

- **`ReferenceFileDocument`** — originally deferred as unnecessary complexity; now deprecated by
  Apple for new macOS 27 document types and not a migration candidate.
- **`NSDocument`** — most control and real large-file support; originally rejected as heavy and
  least SwiftUI-idiomatic. SPIKE-02 now recommends it, subject to explicit approval.
- **macOS 27 SwiftUI `Document`** — unavailable when this ADR was accepted. SPIKE-02 proved the
  API but does not recommend migration while it remains beta and lacks an operation-scoped Save
  result.
