# COR-69 — Intent measurement and honest benchmark

- **Status:** Approved; not implemented
- **Delivers:** REQ-123, REQ-125, REQ-128
Architecture impact: none; realizes ARC-020 and the reserved ARC-026 contract
Blockers: COR-68
Executor: A junior developer may implement this plan in order. Request senior review before committing the identity/clock seam, and stop if an intent cannot be carried explicitly through an existing API.

## Outcome

Measure one user intent across actor, task, and GCD boundaries; observe main-thread stalls rather
than display-link callback arithmetic; and produce a reproducible baseline by driving real shipping
routes with structurally declared corpora.

## Files and ownership

- Replace task-local ownership in `Markdown Editor/WorkLedger.swift` with sendable `IntentID`,
  `IntentContext`, and one `IntentRecorder` owned by `EditorSession`.
- Thread the context through `EditorCommandController`, `WYSIWYGEditor.Coordinator`,
  `SourceEditor.Coordinator`, `EditorSemanticWorker`, `ParseCoordinator`, image display/placement,
  and storage application. No global current intent.
- Refactor `FrameObserver.swift` behind `FrameClock`/`MainActorClock`; use monotonic callback arrival
  and main-actor acknowledgement to measure delay. Keep a production display-link implementation and
  deterministic controlled-clock tests.
- Make `BenchmarkDriver` the sole corpus/action authority. `Scripts/benchmark.sh` passes a manifest;
  it does not rebuild corpus text or action loops.
- Add machine-written `docs/research/performance-baseline.md` with the provenance REQ-137 requires.

## Implementation

1. Write adversarial red tests showing GCD work is lost, a 200 ms main-actor stall looks smooth, an
   action refusal is ignored, and a scroll iteration makes no progress.
2. Introduce explicit intent identity at every user entry point. Child asynchronous work retains the
   ID; terminal completion closes exactly once; late work records a typed orphan fault.
3. Record ledger overhead against an identical no-recorder control with fixed seeds and Release
   samples; remove the self-referential “under one percent” assertion.
4. Implement controlled-clock frame tests for normal cadence, dropped callbacks, queued callbacks,
   main-actor stalls, refresh-rate changes, and stop/restart.
5. Drive typing, table editing, every command, mode toggles, scroll progress, undo/redo storms, and
   soak through production controllers. Require accepted/refused counts and the declared expected
   outcome for every action.
6. Run Release benchmark on every `PerformanceCorpus` case, write the baseline atomically, validate
   digests/sample counts/commit, and reconcile budgets only from observed data.

## Proof and failure behavior

- One accepted insertion crossing `EditorSemanticWorker.sync` produces one ledger with downstream
  parse/build/apply counts; nested and concurrent intents never merge.
- A controlled 200 ms main-actor stall increases hitch duration even if display callbacks retain
  ideal timestamps.
- Every benchmark action reports progress and the expected outcome; zero samples, no-op scroll,
  refusal, timeout, unknown action, or duplicate corpus authority fails the run.
- Cancellation closes the recorder, discards late state application, and retains a typed diagnostic.

## Deletion/conformance gate

No `@TaskLocal` ledger owner, shell corpus builder, unchecked benchmark action, or frame proof based
only on timestamp-delta arithmetic remains. Full Release evidence and the generated baseline pass
provenance, proof-result, and falsification gates.
