# ADR-0006 — Document model: NSDocument

- **Status:** Accepted
- **Date:** 2026-07-22; revised 2026-07-25
- **Deciders:** Toni Melisma
- **Related:** [ADR-0002](0002-swiftui-first-appkit-where-needed.md), [ADR-0007](0007-editor-surface-interim-texteditor.md); [RESEARCH-0001](../research/0001-inc01-editor-foundation.md); INC-01

> Living decision. `FileDocument` delivered INC-01/INC-02 and has been replaced by `NSDocument`
> in COR-04 (2026-07-25). The shipped owner is `MarkdownDocument`.

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

Use **`NSDocument`** as the document owner before WYSIWYG:

- one reference-owned canonical Markdown source;
- one document-owned `UndoManager`;
- direct `fileURL` and location-change observation;
- completion-bearing Save for dependent image actions;
- standard autosave in place, Versions, tabs, Recents, Open, New, Save, and Save As;
- immutable byte/parse/projection snapshots crossing background boundaries; and
- SwiftUI editor content hosted behind a narrow AppKit document/window adapter.

`FileDocument` was the correct low-cost INC-01 choice, but COR-04 replaces it rather than
retaining a second value/document authority or view-derived ownership.

## Consequences

- **Positive:** document identity, source, URL, Save completion, undo, and Versions have one
  native owner shared by both editor modes and COR-02.
- **Negative / costs:** explicit `NSDocumentController`/window-controller plumbing and SwiftUI
  hosting replace the smaller `DocumentGroup` scene.
- **Migration:** COR-04 is a separate reversible build before INC-04. It preserves the existing
  byte contract and adapts COR-02's document seam without rewriting storage.

### SPIKE-02 reassessment

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
therefore recommended `NSDocument`. The user accepted that recommendation on 2026-07-25.
COR-04 requirements and PLAN-0008 define the separate migration; no WYSIWYG code is part of it.

## Alternatives considered

- **`ReferenceFileDocument`** — originally deferred as unnecessary complexity; now deprecated by
  Apple for new macOS 27 document types and not a migration candidate.
- **Retain `FileDocument`** — rejected for the two-editor architecture because value rebinding,
  view-owned undo, and the dependent-Save bridge would become permanent infrastructure.
- **`NSDocument`** — selected after strict Swift 6 and byte/undo probes.
- **macOS 27 SwiftUI `Document`** — unavailable when this ADR was accepted. SPIKE-02 proved the
  API but does not recommend migration while it remains beta and lacks an operation-scoped Save
  result.
