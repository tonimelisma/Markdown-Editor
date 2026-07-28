# COR-15 — Production performance sampling

- **Status:** Approved; not implemented
- **Requirements:** REQ-103
- **Architecture impact:** none. Reads existing timing computations; does not change the
  measured paths.

REQ-090 defines budgets (keystroke translation p95 < 8 ms, mode toggle p95 < 16 ms, off-main
parse p95 < 100 ms) that are measured only in tests. A real session reports nothing, so a user's
"it got slow" is unfalsifiable.

## Requirement

- **REQ-103** — The system shall record periodic summary statistics for keystroke translation,
  mode toggle, and reconciliation durations during ordinary use, without recording per-keystroke
  events.

## Design

Per-keystroke records would be both noisy and a weak privacy signal (keystroke timing is
behavioral data). Aggregate instead.

Add `Markdown Editor/PerformanceSampler.swift`:

```swift
/// Fixed-capacity duration reservoir producing count/p50/p95/max summaries.
///
/// REQ-103: aggregate only. Per-keystroke timing is never recorded — it is noise, and its
/// shape is behavioral data the user did not ask us to keep.
@MainActor
final class PerformanceSampler {
    enum Metric: Sendable { case keystrokeTranslation, modeToggle, reconciliation }
    func record(_ metric: Metric, durationNanos: UInt64)
    func drainSummaries() -> [(metric: Metric, count: Int, p50: UInt64, p95: UInt64, max: UInt64)]
}
```

Emit `performanceSummary(metric:count:p50Nanos:p95Nanos:maxNanos:)` at `info` on a 60-second timer
and once at `runEnd`. Add `budgetExceeded(metric:p95Nanos:budgetNanos:)` at `warn` when a window's
p95 exceeds the REQ-090 budget — that is the record that makes a slowness report actionable.

Call sites: `EditorSession.perform` already computes `planningStart`; `applyMode` in
`EditorHost.swift`; `scheduleParse` already computes `reconciliationStart`. All three timings
exist — this is routing them, not adding measurement.

## Files

**Modify:** `Markdown Editor/EditorTrace.swift`, `Markdown Editor/DiagnosticValue.swift`,
`Markdown Editor/DiagnosticRecord.swift`, `Markdown Editor/JSONLinesEditorTrace.swift`,
`Markdown Editor/EditorSession.swift`, `Markdown Editor/EditorHost.swift`,
`docs/REQUIREMENTS.md` (REQ-103 → Done).

**Add:** `Markdown Editor/PerformanceSampler.swift`,
`samplerComputesPercentilesFromKnownDistribution`, `budgetExceededIsRecordedWhenP95OverBudget`,
`performanceSummaryOmitsPerEventTimings` in a new or existing performance test suite.

## Proof

- `samplerComputesPercentilesFromKnownDistribution` — feed 1…100 ms, assert p50/p95.
- `budgetExceededIsRecordedWhenP95OverBudget`.
- `performanceSummaryOmitsPerEventTimings` — assert no `keystroke`-level event is emitted.
- `Scripts/check-instrumentation-coverage.sh` passes.

## Rollback

Self-contained. Deleting `PerformanceSampler.swift` and reverting the three call-site edits
restores prior behavior; REQ-090's existing test-only proofs are unaffected.
