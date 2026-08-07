# COR-42 — Extract ParseCoordinator from EditorSession

- **Status:** Approved; not implemented
- **Requirements:** REQ-085/091/093 (off-main parse, synchronous edit, availability), REQ-111 (latest-parse scheduling) — no new REQ
- **ARC invariants:** ARC-003/005/006/011 (snapshot identity, synchronous edit, reconciliation guard, concurrency) unchanged; extraction only

## Context

`EditorSession` (`Markdown Editor/EditorSession.swift:34`, 746 lines) owns 6 subsystems: `@Published` presentation/mode, `LatestParseScheduler` + `Task` parse pipeline (`:398-595`), synchronous edit dispatch (`:599-677`), image-picker intent, `PerformanceSampler`, and reconciliation-violation counts. Every scheduling or metrics change touches the same `@MainActor` type, and off-main publishing must hop through it. This is the top structural risk from the 8-item triage (god object). Extracting one coordinator now makes the next product increment (table creation / outline) reviewable without re-introducing a mutex mirror (forbidden by ENGINEERING §9).

## Production changes

### 1. New `ParseCoordinator` (new file `Markdown Editor/ParseCoordinator.swift`)

- `@MainActor final class ParseCoordinator: ObservableObject` or `actor` + `@MainActor` hop — owns:
  - `LatestParseScheduler`
  - `Task<Void, Never>? parseTask`
  - `operationGeneration: UInt64`
  - `func scheduleParse(for document: MarkdownDocument, session: EditorSession)` — moved from `EditorSession.scheduleParse`
  - `func cancel()` — called from `EditorSession.detach`
- Takes `EditorSession` weakly for reconciliation gates (`sourceVersion`, `locationGeneration`, `presentation.id`) and for `EditorSemanticWorker` callbacks.
- No new concurrency: reuses existing `Task.detached` + `MainActor.assumeIsolated` pattern; `EditorSemanticWorker.sync` stays off-main immutable snapshot.
- `EditorSession` keeps `authoritativeTree`, `presentation`, and `resolvedImages` as `@Published`; delegates scheduling to `parseCoordinator.scheduleParse()`.

### 2. `EditorSession.swift` — delegate

- Replace inline `parseScheduler`/`parseTask`/`operationGeneration`/`scheduleParse`/`cancelParse` with `let parseCoordinator = ParseCoordinator()`.
- `scheduleParse()` becomes `parseCoordinator.scheduleParse(for: document, session: self)`.
- `detach()` calls `parseCoordinator.cancel()` plus existing sampler/image cleanup.
- No change to `WYSIWYGAvailability`, `PendingSelectionRestoration`, or `SourceMutation` path.

### 3. No new `try!`, no new `force: Bool`, no new mutex mirror

## Proof

- `Scripts/fast-check.sh` 368 passed / 0 failed (excludes PerformanceBoundaryTests per fast-check)
- Full `xcodebuild test` — all suites, including `ParseSchedulingTests` / `ReconciliationInvariantTests` / `PerformanceBoundaryTests` at 100k corpus — must pass
- `Scripts/check-documentation-authority.sh` PASS
- `Scripts/check-instrumentation-coverage.sh` PASS
- `Scripts/check-proof-results.sh` PASS against `.xcresult`
- Existing `LatestParseScheduler` unit tests remain the direct proof for REQ-111; no new REQ-118 anchor needed if helper stays internal, otherwise `// Verifies: REQ-111` on new test

## Failure / rollback

Pure extraction with identical observable behavior. If any parse/reconciliation test fails, revert the single extracting commit; no file format, undo-history, or diagnostic schema change.

## Deletion / conformance gate

- No `LatestParseScheduler` + `parseTask` + `operationGeneration` trio remains inside `EditorSession.swift` — grep must be empty for that trio inside `EditorSession`.
- `ParseCoordinator` is the single owner for `scheduleParse`/`cancel` — `EditorSession` contains only delegation calls.
- `git log --oneline` shows one squashed commit for COR-42; `docs/plans/COR-42-*.md` deleted in same commit as code.
