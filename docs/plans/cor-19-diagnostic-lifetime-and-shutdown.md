# COR-19 — Diagnostic lifetime and shutdown

- **Status:** Approved; not implemented
- **Kind:** App-code correction; one worktree, branch, PR, and squash merge
- **Requirements:** REQ-095, REQ-096, REQ-103, REQ-110
- **Architecture:** Implements ARC-020, ARC-021, ARC-Q17; preserves ARC-016 and ARC-017
- **Depends on:** COR-18
- **Must finish before:** COR-20 final performance instrumentation

## Goal

Make diagnostics lifetime-correct and capable of reporting the failures they claim to observe:
no leaked session samplers or timers, no weak-sink evidence loss, no watchdog report routed
through the stalled main actor, and no terminal flush waiting on its own main-actor cleanup.

## Baseline defects to reproduce

1. Construct and release many `EditorSession` instances; show
   `PerformanceSamplerRegistry.samplers` retains every sampler and timer.
2. Show `flushAll()` executes `removeAll { _ in false }`.
3. Release a trace sink before the sampler flushes; show samples drain without a record.
4. Block the main actor beyond the watchdog threshold; show the production callback queues
   `DiagnosticLog.record` back to the blocked actor.
5. Call `finishSynchronously` on the main actor; show its detached task cannot complete until the
   timeout because it awaits `MainActor.run`.

## Files

### Modify

- `Markdown Editor/PerformanceSampler.swift`
- `Markdown Editor/DiagnosticLog.swift`
- `Markdown Editor/MainActorWatchdog.swift`
- `Markdown Editor/Markdown_EditorApp.swift`
- `Markdown Editor/EditorSession.swift`
- `Markdown Editor/JSONLinesEditorTrace.swift`
- `Markdown Editor/DiagnosticRecord.swift`
- `Markdown Editor/DiagnosticValue.swift` only if the existing closed values cannot encode the
  approved lifecycle fields
- `Markdown EditorTests/DiagnosticLogTests.swift`
- `Markdown EditorTests/EditorIntegrationTests.swift`
- `docs/ENGINEERING.md`
- `docs/REQUIREMENTS.md`
- `docs/ROADMAP.md`

### Add

- `Markdown Editor/DiagnosticRunCoordinator.swift`
- `Markdown EditorTests/DiagnosticLifetimeTests.swift`

### Delete

- `PerformanceSamplerRegistry`
- `flushPerformanceSamplingAtRunEnd()`
- any main-actor watchdog reporting closure
- any shutdown wait whose awaited task includes `MainActor.run`
- this plan after implementation

## Target ownership

- `EditorSession` owns exactly one optional `PerformanceSampler`.
- `PerformanceSampler` owns its bounded samples and periodic timer.
- `DiagnosticRunCoordinator` weakly registers live sampler identities and coordinates a terminal
  flush; it never strongly owns a sampler or session.
- `DiagnosticLog` remains the one schema/retention facade.
- The serialized file-appender actor owns ordering and durable file close.
- `MainActorWatchdog` owns only its probe task and a `Sendable` non-main fault reporter.

## Implementation

1. Give `PerformanceSampler` explicit `start`, `flush`, and idempotent `invalidate`.
   - `invalidate` stops the timer, flushes once if the sink remains available, unregisters, and
     clears samples.
   - `deinit` invalidates defensively but tests must prove normal explicit detach.
2. Give `EditorSession` an explicit detach path invoked when its document/window lifetime ends.
   - cancel parse/publication subscriptions;
   - invalidate sampler;
   - clear document and router references;
   - make repeated detach a no-op.
3. Implement weak run coordination.
   - Registration token or weak box must not retain the sampler.
   - Terminal flush snapshots only live samplers.
   - No repeating global timer exists.
4. Keep trace ownership strong for the sampler's valid session lifetime, or route through the run
   coordinator. Do not silently drain samples into `nil`.
5. Expose one `Sendable` process-fault recording closure that enqueues directly to the serialized
   diagnostic sink without a main-actor hop.
   - Preserve closed privacy-safe payloads.
   - Preserve global sequence ordering through the one sink.
6. Make the watchdog record:
   - threshold crossing while main remains blocked; and
   - recovery duration only if recovery occurs.
7. Split terminal close into two completions:
   - durable sink completion, usable from the termination callback; and
   - main-actor sudden-termination cleanup.
   `finishSynchronously` waits only for durability.
8. Rename performance payload key `mode` to `metric` and increment the diagnostic schema version
   if compatibility cannot be maintained honestly. If the schema changes, update smoke fixtures
   and verifier atomically.
9. Preserve event collapse, file-size cap, retention, clean `runEnd`, and privacy restrictions.

## Automated proof

- Create/attach/detach/release 100 sessions under an autorelease pool:
  - weak session and sampler references become nil;
  - live registration count returns to zero;
  - no timer callback occurs after detach.
- Invalidate twice: exactly one final summary, no crash, no remaining registration.
- Force a sink close after samples: summary precedes `runEnd`.
- Hold the main actor behind a controlled semaphore:
  - threshold fault reaches a test sink before release;
  - recovery event appears afterward;
  - permanent-test variant cancels without requiring recovery.
- Invoke terminal close from the main actor:
  - durable completion occurs below the approved bounded test timeout;
  - the test does not wait for main-actor cleanup.
- Existing JSON ordering, retention, collapse, privacy, and mapping suites remain green.
- Process smoke retains one performance summary and clean termination.

## Instrumentation

Instrumentation must not instrument itself recursively. Sampler registration/invalidation counts
may be exposed to tests through an internal snapshot, not recorded per session in production.
Watchdog and run-end records use existing privacy-safe symbols and numbers only.

## Failure and rollback

- If ordering cannot be preserved through a non-main watchdog route, stop and return to
  architecture discovery; do not introduce a second log file or `os_log`.
- If AppKit termination cannot wait for the durable sink within the bounded callback, preserve
  `runEnd` durability and present measured options before changing the requirement.
- The old registry and new coordinator must never coexist in production.

## Conformance and completion gates

- `rg "PerformanceSamplerRegistry|flushPerformanceSamplingAtRunEnd"` returns no production match.
- `rg` proves the watchdog reporter contains no `Task { @MainActor`.
- No synchronous durability wait transitively awaits `MainActor.run`.
- Swift 6 Debug and Release builds/tests pass without warnings.
- Documentation-authority and instrumentation-coverage checks pass.
- Separate-agent review, PR-comment triage, smoke, screenshot review, and stale-work sweep pass.
- Delete this plan in the implementing branch.
