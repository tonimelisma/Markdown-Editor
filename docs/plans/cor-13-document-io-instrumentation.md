# COR-13 — Document save, load, and revert outcome instrumentation

- **Status:** Approved; not implemented
- **Requirements:** REQ-100
- **Architecture impact:** none.

Today a log cannot answer "did the save work?". For a local-first editor whose first architecture
driver is source fidelity, that is the wrong thing to be missing.

## Requirement

- **REQ-100** — The system shall record the outcome of every document load, save, autosave, and
  revert, including failures, without recording file names, paths, or contents.

## Events to add

Follow the shared recipe (`EditorTraceEvent` → `DiagnosticSymbol` → `DiagnosticEventName`/
`DiagnosticField` → `JSONLinesEditorTrace.map` → real call site → extend
`everyTraceEventMapsToSymbolicPayload`).

| Event | Payload | Level |
|---|---|---|
| `documentLoaded(utf16Count:sourceRevision:)` | counts only | `info` |
| `documentLoadFailed(reason:)` | `DocumentIOFailure` symbol | `error` |
| `documentSaveStarted(utf16Count:)` | counts only | `debug` |
| `documentSaveSucceeded(utf16Count:sourceRevision:durationNanos:)` | counts, timing | `info` |
| `documentSaveFailed(reason:)` | `DocumentIOFailure` symbol | `error` |
| `documentReverted(sourceRevision:utf16Count:)` | counts only | `info` |

Add `nonisolated enum DocumentIOFailure: Sendable, Equatable` with cases covering what the code
can actually distinguish — start from `MarkdownDocumentData.init(data:)`'s throw sites and
`DocumentSaveBridge`. Do not invent cases the code cannot produce.

## Where to wire

- `MarkdownDocument.read(from:ofType:)` — success and the `MarkdownDocumentData` throw.
- `MarkdownDocument.data(ofType:)` — snapshot size and failures.
- `MarkdownDocument.installLoadedText` — `documentLoaded` / `documentReverted`. Distinguish the
  two by whether `fileURL` was already set.
- `DocumentSaveBridge.save(_:)` and `didSave(_:didSaveSuccessfully:contextInfo:)` — this is where
  save success/failure is actually known.

**Privacy check before committing:** the only strings anywhere near this code are file paths. None
of them may reach a payload (`ARC-016`). If a `String` case on `DiagnosticValue` seems necessary,
stop — the answer is a symbol or a count.

## Files

**Modify:** `Markdown Editor/EditorTrace.swift`, `Markdown Editor/DiagnosticValue.swift`,
`Markdown Editor/DiagnosticRecord.swift`, `Markdown Editor/JSONLinesEditorTrace.swift`,
`Markdown Editor/MarkdownDocument.swift`, `Markdown Editor/DocumentSaveBridge.swift`,
`docs/REQUIREMENTS.md` (REQ-100 → Done).

**Add:** `documentSaveFailureIsRecorded`, `documentLoadFailureIsRecorded`,
`documentIOTraceOmitsPaths` in `Markdown EditorTests/DiagnosticLogTests.swift` (or the relevant
document test suite).

## Proof

- `documentSaveFailureIsRecorded` — inject a failing `saveExecutorOverride` (the seam already
  exists on `MarkdownDocument`) and assert an `error`-level record.
- `documentLoadFailureIsRecorded` — feed invalid UTF-8 through `read(from:ofType:)`.
- `documentIOTraceOmitsPaths` — assert no emitted line contains the fixture's filename. Write this
  one first; it is the actual privacy guarantee.
- Extend the smoke test (COR-11): assert exactly one `documentLoaded`.
- Run `Scripts/check-instrumentation-coverage.sh` (from COR-12).

## Rollback

Self-contained. Reverting the wiring restores prior behavior; no other subsystem depends on these
events existing.
