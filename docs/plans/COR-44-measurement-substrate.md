# COR-44 — Measurement substrate: count work, not only duration

- **Status:** Approved; not implemented
- **Requirements:** new REQ-123 (work ledger), REQ-124 (main-actor responsiveness), REQ-125 (frame statistics), REQ-126 (memory footprint)
- **Delivers:** REQ-123, REQ-124, REQ-125, REQ-126
- **ARC invariants:** new ARC-026 (work per unit of user intent is counted, attributed to a closed scope set, and bounded); ARC-016 (payloads cannot represent content) unchanged and reused; ARC-020 (samples lifetime-owned, bounded, honestly named) extended to the new metrics

## Context

Three of the four critical findings in the August whole-application review were invisible to a green
368-test suite with every gate passing. Not because the tests were weak, but because **nothing in the
app counts work**.

Duration metrics answer "was it slow". They never answer "why", and they never catch amplification.
They cannot distinguish "this document is large" from "this keystroke parsed the document four
times". A single ledger would have made all three findings self-reporting:

| Finding | Field that names it |
| --- | --- |
| 2–4 whole-document parses per inserted character (`SemanticEditEngine.plan` → `literalCandidatePreservesPresentation` → `contextualLiteralMutation` → `planAuthoritativeTransition`) | `documentParses` per `.acceptedEdit` |
| Every referenced image re-read, re-hashed and re-decoded per reconciliation (`ParseCoordinator.scheduleParse` → `LocalImageDecoder.decode`) | `fileBytesRead` per `.reconciliation` |
| `AttributedPresentationBuilder.buildScoped` iterating every run and sorting every block inside the "bounded" patch path | `attributedCharactersWritten` versus edit length |
| `EditorSemanticWorker.sync` blocking the main thread on a semaphore while satisfying ARC-Q06's wording | `mainThreadBlockedNanos` |

`MainActorWatchdog` fires at one second: it is a hang detector, not a responsiveness detector. A p99
main-actor latency of 40 ms — visible, unpleasant jank — never trips it and is recorded nowhere.
Nothing measures dropped frames, which is what "janky" actually means. Nothing measures memory, which
is half of VISION objective 7 ("fast and **light**").

This increment adds the instruments. COR-45 adds the harness that drives them. Every increment after
those two is diagnosable from evidence instead of from reading code.

## Production changes

### 1. New `Markdown Editor/WorkLedger.swift`

```swift
nonisolated struct WorkLedger: Sendable, Equatable {
    var documentParses = 0
    var projectionCompiles = 0
    var oracleValidations = 0
    var attributedBuilds = 0
    var attributedCharactersWritten = 0
    var storageFullReplacements = 0
    var imageDecodes = 0
    var fileBytesRead = 0
    var mainThreadBlockedNanos: UInt64 = 0
}

nonisolated enum WorkScope: String, Sendable, CaseIterable {
    case acceptedEdit, reconciliation, documentOpen, modeTransition, semanticCommand
}

nonisolated enum WorkLedgerRecorder {
    private static let state = Mutex<[(scope: WorkScope, ledger: WorkLedger)]>([])
    static func scope<T>(_ scope: WorkScope, _ body: () throws -> T) rethrows -> T
    static func add(_ mutate: (inout WorkLedger) -> Void)
    static func currentForTesting() -> WorkLedger?
}
```

Lock-guarded rather than actor-isolated: increments arrive from the main actor, from
`Task.detached` reconciliation, and from the `EditorSemanticWorker` queue. Scopes nest, and an inner
scope's work also counts toward its enclosing scope — the question being answered is "how much work
did this keystroke cause", not "how much happened inside this function". `scope` pushes, runs, pops,
records the trace event, and merges into the parent when one exists.

### 2. Instrumentation points — all of them, no partial landing

| Field | Call site |
| --- | --- |
| `documentParses` | `MarkdownParser.parse`, inside the lock, after the cancellation recheck |
| `projectionCompiles` | `MarkdownProjectionModel.build` |
| `oracleValidations` | `ProjectionOracle.validate(snapshot:)` and `validate(model:)` |
| `attributedBuilds`, `attributedCharactersWritten` | `AttributedPresentationBuilder.buildScoped` (`+= scope.length`) |
| `storageFullReplacements` | `TextStorageApplier.applyInitialPresentation`, `applyRecoveryPresentation` |
| `imageDecodes`, `fileBytesRead` | `LocalImageDecoder.decode` (bytes = the mapped file size) |
| `mainThreadBlockedNanos` | `EditorSemanticWorker.sync`, around `completion.wait()`, only when `Thread.isMainThread` |

| Scope | Opened in |
| --- | --- |
| `.acceptedEdit` | `EditorSession.perform`, wrapping the whole body |
| `.semanticCommand` | `EditorCommandController.route` |
| `.reconciliation` | the detached task body in `ParseCoordinator.scheduleParse` |
| `.documentOpen` | `MarkdownDocument.installLoadedText` |
| `.modeTransition` | `EditorHostView.HostCoordinator.applyMode`, only when `modeChanged` |

### 3. `EditorTraceEvent.workLedger(scope:ledger:)`

All integers plus one `DiagnosticSymbol` for the scope, so it is representable under the existing
closed `DiagnosticValue` type with **no new case** — ARC-016 holds by construction rather than by
review. Five real production call sites satisfy `Scripts/check-instrumentation-coverage.sh`.

### 4. Collapse must carry sum and max — `Markdown Editor/DiagnosticLog.swift`

`.acceptedEdit` fires per keystroke, so it collapses under the existing repeated-event rule. A
collapsed record that keeps only a count discards exactly the information this event exists to carry.
Extend the collapse to accumulate **sum and max per numeric field**. This is a real change to
`DiagnosticLog`'s collapse path, not a configuration flag; it is not optional and it has its own
proof below.

### 5. New `Markdown Editor/MainActorResponsivenessProbe.swift`

A background `DispatchSourceTimer` at a 100 ms cadence captures `t0`, hops to `MainActor`, captures
`t1`, and records `t1 - t0` as a new `PerformanceSampler.Metric.mainActorLatency` with a **16 ms p95
budget**. Frequent enough to catch a stall inside one typing burst; sparse enough that the probe is
not itself the load. Started in `applicationDidFinishLaunching` beside the watchdog, stopped in
`applicationWillTerminate`. `PerformanceBudgetTests` fails until the budget is declared, which is the
intended forcing function.

`MainActorWatchdog` is retained unchanged: hang detection and responsiveness distribution are
different questions and must not be conflated into one threshold.

### 6. New `Markdown Editor/FrameObserver.swift`

Records inter-frame intervals from the display link and derives hitch statistics — milliseconds of
hitch per observed second, plus longest frame. `layoutApplication` measures how long the app spent
laying out; this measures whether the display actually received a frame, which is what the user
perceives and which can be bad for reasons the app's own timers never see.

The frame budget is read from the display link's real cadence (`targetTimestamp` delta), **never a
hardcoded 16.67 ms** — ProMotion and external displays differ, and a constant would report phantom
hitches on a 120 Hz panel.

Emits `EditorTraceEvent.frameStatistics(hitchMillisPerSecond:longestFrameNanos:framesObserved:)` on
the sampler's periodic flush.

Gated behind `MARKDOWN_EDITOR_FRAME_OBSERVER=1`, always set by COR-45's benchmark harness and off by
default in shipping builds: a display link fires 60–120 times per second whether or not anything is
happening, and an always-on diagnostic must never itself become the regression. That the metric has
an opt-in hole is stated in `ENGINEERING.md` §12 rather than left implicit.

### 7. New `Markdown Editor/MemoryFootprint.swift`

`task_info(mach_task_self_, TASK_VM_INFO, …)` → `phys_footprint` and `ledger_phys_footprint_peak`,
sampled in `PerformanceSampler.flush`, emitted as
`EditorTraceEvent.memoryFootprint(bytes:peakBytes:)`. `phys_footprint` rather than `resident_size`
because it is the number the OS uses for memory-pressure and jetsam accounting and it includes
compressed pages — a document that is "small in RAM" only because it was compressed is not small.

### 8. `Scripts/verify-smoke-log.py` — `--fail-on-budget-exceeded`

`budgetExceeded` records already exist and nothing has ever failed on one. The flag is set by
COR-45's `Scripts/benchmark.sh` and deliberately **not** by `Scripts/smoke-test.sh`: a two-second
smoke run has too few samples for a p95 to mean anything. The asymmetry is explained in the script
rather than left for a reader to rediscover.

## Proof

All automated, non-UI, by direct construction.

- `acceptedEditRecordsItsWorkLedger` — an accepted insertion emits one `workLedger` record scoped
  `.acceptedEdit`.
- `nestedWorkScopesAccumulateIntoTheEnclosingScope` — work inside `.semanticCommand` also counts
  toward an enclosing `.acceptedEdit`.
- `collapsedWorkLedgerRecordsRetainSumAndMax` — 200 rapid edits collapse to a summary that still
  reports total parses and worst-case parses. Rehearsed failing against a count-only collapse.
- `responsivenessProbeRecordsLatencyDistribution` — the probe produces samples and percentiles.
- `aTwoHundredMillisecondMainActorBlockAppearsInTheLatencyDistribution` — block the main thread for
  200 ms inside a component test; assert the probe reports it and that `MainActorWatchdog` does not
  (proving the two instruments answer different questions). **Rehearsed failing** by stubbing the
  probe to record zero.
- `frameBudgetFollowsTheDisplayLinkCadenceRatherThanAConstant` — a simulated 120 Hz cadence yields no
  hitches for 8 ms frames. Rehearsed failing against a hardcoded 16.67 ms budget.
- `memoryFootprintRecordIsNumericOnly` — the emitted payload contains no string case (reuses
  `diagnosticPayloadHasNoStringCase`'s technique).
- `everyWorkScopeIsOpenedByProduction` — structural, in the shape of
  `Scripts/check-instrumentation-coverage.sh`: every `WorkScope` case has a real production
  `WorkLedgerRecorder.scope` call site. A new scope fails the build until it is opened.

## Instrumentation and performance evidence

This increment **is** instrumentation. Its own overhead must be bounded and measured, not assumed:

- `ledgerRecordingOverheadIsBelowOnePercent` — run `nativeInputCallbackP95Under8ms`'s existing corpus
  with recording enabled and disabled; assert the p95 delta is under 1 %. A measurement instrument
  that changes what it measures is worthless.
- Release evidence recorded for `mainActorLatency` on an idle document and during a typing burst.

## Failure / rollback

Additive. No existing route changes behaviour; the ledger is written and read by nothing but
diagnostics and tests. If overhead exceeds the 1 % gate, the increment fails rather than shipping:
reduce to `documentParses` + `fileBytesRead` + `mainThreadBlockedNanos` (the three fields that name
the known findings) and record which fields were dropped and why. Revert is one commit; no file
format, source route, or user-visible behaviour is touched.

The frame observer is the only component with a plausible steady-state cost, and it is off by default,
so a defect there cannot reach a user.

## Deletion / conformance gate

- No second work-counting route: `everyWorkScopeIsOpenedByProduction` plus
  `Scripts/check-instrumentation-coverage.sh` prove the ledger is the only one, and no `os_log` or
  ad-hoc counter is introduced (`ENGINEERING.md` §12: "There is no second instrumentation route").
- The `#if DEBUG` build counter contemplated during review is **not** added — the ledger subsumes it,
  and two counters for one fact is the duplication this architecture forbids.
- `Scripts/check-documentation-authority.sh`, `Scripts/check-instrumentation-coverage.sh`, and
  `Scripts/check-proof-results.sh` pass.
