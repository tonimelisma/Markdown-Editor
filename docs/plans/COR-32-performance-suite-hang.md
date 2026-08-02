# COR-32 — PerformanceBoundaryTests hangs before executing

- **Status:** Approved; not implemented

## Scope

`PerformanceBoundaryTests` does not run. Restore it, and with it REQ-090's ability to regenerate
its own Release evidence. Nothing else in the suite is affected.

## Reproduction

Reproduced on `main` @`24341da` — with no code from the COR-26..COR-31 branch — and identically
on that branch:

```bash
xcodebuild test -configuration Debug -destination 'platform=macOS' \
  -only-testing:"Markdown EditorTests/PerformanceBoundaryTests"
```

- 0 `Test case` lines after 4+ minutes; the suite's tests are ordinary patch-boundary tests that
  should complete in seconds.
- The test host process is alive and **idle at 0% CPU**, main thread parked in
  `NSApplicationMain → _DPSNextEvent → mach_msg2_trap`. Five threads total; the XCTest and
  Swift Testing frameworks are loaded but **no thread is executing a test**.
- `Scripts/fast-check.sh`, which passes `-skip-testing` for this suite, runs **350 tests, 0
  failures** in the same host. Host startup is therefore not the problem.
- A full unified `xcodebuild test` stalls partway (observed ~112 cases), consistent with hanging
  when it reaches this suite.
- A focused Release run was left executing for **3 h 45 m** in this state before being killed.

This is why no run in the closing sequence of the COR-26..COR-31 increment could produce Release
performance evidence, and why that increment's REQ-090 row is `Correction`.

## Requirements and invariants

- REQ-090 → `Correction`: its p95 gates cannot currently be executed.
- REQ-103, ARC-020: sampler lifetime and boundary honesty are unaffected; the metrics themselves
  still work (`Scripts/smoke-test.sh` reports real `performanceSummary` records).
- ARC-014: the fix must not introduce any UI-driven verification.
- **Architecture impact: none expected.** If the cause turns out to be an architectural
  interaction rather than a test-harness defect, stop and open a discovery unit.

## Investigation order

Cheapest discriminating experiment first; stop as soon as one reproduces.

1. **Bisect the suite, not the code.** Run each `@Test` in the file individually via
   `-only-testing:` at test granularity to find whether one test hangs or the suite never starts
   at all. The distinction decides everything that follows. (Note: `-only-testing` with a Swift
   Testing *function* name silently matches nothing and exits 0 — verify the filter selected a
   case before trusting a green result.)
2. **Bisect history.** The suite passed as recently as PR #29 ("Debug 328 passed / 0 failed").
   `git bisect` between that commit and `24341da` over the single command above.
3. If the suite never starts: inspect `EditorHarness` construction and any suite-level shared
   state — `DiagnosticLog.startShared`, `DiagnosticRunCoordinator.shared`, the
   `PerformanceSampler` 60 s `Timer` — for a main-actor await that cannot be serviced when this
   suite runs first, since it runs *after* other suites in the full run and hangs there too.
4. If one test hangs: sample the host at that moment and read the stack rather than inferring.

## Automated non-UI proof

The proof is the suite executing: `-only-testing:"Markdown EditorTests/PerformanceBoundaryTests"`
completes with a nonzero case count and zero failures, and a full unified run reaches the end.
Record the wall-clock time of both, so a future regression to "hangs" is visibly distinct from
"is slow".

Add a guard so this cannot recur silently: the suite must complete within a bounded wall-clock
time, asserted by the runner rather than by a human noticing a run has been going for hours.

## Instrumentation and performance evidence

Once the suite runs, re-record the REQ-090 Release evidence in full — configuration, corpus
identity and SHA-256, warmups, sample count, median, p95 — and return REQ-090 to `Done`. Zero
executed samples remains a failing proof, and a suite that never executes is the strongest form
of zero.

## Failure and rollback behavior

If the cause is environmental (this Xcode beta, this macOS build) rather than a repository
defect, that finding is recorded in REQUIREMENTS against REQ-090 with the version evidence, and
the requirement stays `Correction` until it can be executed somewhere. An environmental cause is
not a reason to mark it `Done`.

## Deletion and conformance gate

- No verification may be deleted or skipped to make this pass; `Scripts/fast-check.sh` keeps its
  explicit "not a release gate" banner.
- Both gate scripts and both smoke scripts pass; delete this plan in the implementing change.
