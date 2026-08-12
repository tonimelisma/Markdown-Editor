# COR-58 — Coverage by observed emission

- **Status:** Approved; not implemented
- **Delivers:** REQ-099, REQ-135
- **Requirements:** REQ-099, REQ-135 (new, `Planned`)
- **ARC invariants:** ARC-027 (strengthened); ARC-Q10 unchanged
- **Executor:** any agent. Shell and test authoring; no production behaviour changes.
- **Scope is discovered, not declared.** Phase 1 runs the new gate and records which cases fail.
  That list is the increment's real size and is unknown until it is run — it is what the old gate
  was hiding. If it is large, say so and re-plan with the user rather than quietly exempting.

## Context

`Scripts/check-instrumentation-coverage.sh` requires every `EditorTraceEvent` case to have a
production call site. It answers that question by **reading source text**, and it has now been
defeated twice by two different mechanisms:

- **2026-07-28, PR #20 review (COR-12).** The script's substring match reported
  `EditorTraceEvent.mainActorStall` covered because an unrelated `DiagnosticEventName.mainActorStall`
  — a different type, passed directly to `DiagnosticLog.record` — happens to share its name. The case
  was never constructed anywhere. The instance was fixed. The class was not.
- **2026-08-10 (COR-44).** Three new cases were "covered" by call sites of the form

  ```swift
  let trace: (any EditorTraceSink)? = nil
  trace?.record(.workLedger(...))
  ```

  bound to `nil` in the same scope and optional-chained, so they can never execute. The comment above
  one of them names the script it exists to satisfy. `instrumentation-coverage: PASS`.

Two defeats of one gate is one unfixed design, and `CLAUDE.md` §6 requires an increment that finds a
defect *class* to close the class or record why it cannot. The class here is not "clever developers";
it is that **the gate asks a question about text, and text is the cheapest thing to produce**.

## Architecture impact

`ARC-027` strengthened: trace-vocabulary coverage becomes a property of a run, not of the source.
No change to the trace vocabulary itself, to `ARC-Q10`'s privacy contract, or to any production
route.

## Production changes

No application code, except deletions that fall out of the new gate (§4).

### 1. `Scripts/check-instrumentation-coverage.sh` — rewritten, not extended

Delete the substring scan entirely. Do not keep it alongside the new check: two gates where one is
known-defeatable is the "individually sound and jointly blind" shape that `CLAUDE.md` §6 already
records as the cause of COR-25 and the four silently refusing commands.

The rewritten gate:

1. reads the union of `name` fields from the JSON Lines diagnostics of the run's own artefacts —
   the test suite's per-run log directory, `Scripts/smoke-test.sh`'s log, and
   `Scripts/smoke-screenshot.sh`'s log;
2. extracts the `EditorTraceEvent` case list from `EditorTrace.swift` (the closed set the
   requirement quantifies over);
3. requires every case to appear in the emitted union;
4. fails closed on an absent or unparseable log, zero emitted names, or zero extracted cases.

### 2. `docs/trace-coverage-exemptions.md` — new

Some cases are genuinely unreachable from an automated run: terminal-fault records emitted on paths
that abort the process, for instance. Each exemption names the case, the reason it cannot be
emitted under test, and the increment expected to remove it. The list is reviewed, small, and
required to shrink — an exemption added without a removal plan fails review, and the gate prints the
current count so growth is visible in every run.

### 3. `EditorTraceSink` test double

Emission under test already flows through the JSON Lines sink used by `DiagnosticLogTests`. Where a
case is reachable in production but no existing test drives its route, the increment adds the
**behavioural** test that drives it — not a synthetic `record` call. A test whose only purpose is to
emit an event satisfies the letter of the new gate and none of its intent; such a test is itself the
defect, and review rejects it.

### 4. Deletions

Every construct written to satisfy the old gate is deleted in this change: the `nil`-bound trace
receivers, `_coverTrace()` on `FrameObserver` and `MemoryFootprint`, and
`EditorSession._coverWorkScopes()`. If COR-56 has already reverted COR-44, this is a no-op and the
conformance gate below confirms it.

## Phases

1. Rewrite the gate; run it against current `main` and record which cases fail. That list is the
   increment's real scope and is not known in advance — it is what the old gate was hiding.
2. For each failing case: drive it from a behavioural test, or exempt it with a stated reason.
3. Delete the displaced scan and every coverage-only construct.
4. Rehearse: confirm the gate goes red when a case's emission site is commented out.

## Automated proof

- `Scripts/test-check-instrumentation-coverage.sh` (new, fixture-based, run by `fast-check.sh`):
  a fixture log missing one case fails; a complete fixture log passes; an empty log fails; a log
  with a case not in the enumeration fails; an exempted case absent from the log passes and prints
  the exemption.
- **Rehearsal against the real defect (REQ-135, `CLAUDE.md` §9):** apply the COR-44 pattern — add a
  `let trace: (any EditorTraceSink)? = nil; trace?.record(...)` site for a case that nothing emits —
  and confirm the new gate **fails** where the old one passed. This rehearsal is the proof that the
  class is closed, and it belongs in the PR description.

## Instrumentation and performance evidence

The gate consumes existing diagnostics; it adds no event and no sampling. Run cost is one extra pass
over log files already written, measured in milliseconds.

## Failure and rollback

The likely failure is over-strictness: a case reachable only under a condition the suite does not
create fails the gate and pressures the increment toward a synthetic emission test — the exact
defect being removed. The exemption file is the designed relief valve, and using it honestly is a
success. If the exemption list would exceed roughly a quarter of the vocabulary, stop: that is
evidence the vocabulary contains dead cases, and `CLAUDE.md` §2 requires deleting them instead.

## Deletion and conformance gate

- `rg -F 'EditorTraceSink)? = nil'`, `rg -F '_coverTrace'`, `rg -F '_coverWorkScopes'` return no
  matches under `Markdown Editor/`.
- The substring-scanning implementation is gone from `check-instrumentation-coverage.sh`; no second
  coverage path exists.
- Every `EditorTraceEvent` case appears in an observed run log or in the exemption file, and in
  exactly one of the two.
