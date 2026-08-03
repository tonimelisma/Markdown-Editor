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

## Discovery findings (2026-08-02)

The original reproduction stands, but investigation changed the picture materially. **There are
two independent defects here, not one**, and neither is a regression from COR-26..COR-31.

**Finding 1 — moved to COR-34.** Four tests in this suite fail, all on attribute-refresh scope.
That is a product defect in `PresentationPatch`, not a harness hang, so it is planned separately.
Summarised here only because it is why this suite looked like it "hung" in the first place.
**Finding 2 — a genuine hang, separate from those failures.** Running the suite with the failing
tests skipped still hangs with zero cases reported, so the hang is not the failures.

**Localised by bisection.** Each group below was run with explicit per-test `-only-testing`
filters against warm derived data:

| Group | Result |
| --- | --- |
| Any single test (7 tried) | completes |
| Two individually-passing tests together | completes |
| Tests 1–9 of the file | completes (9 cases, 1 failure) |
| Tests 10–19 of the file | **hangs, 0 cases** |
| Tests 10–14 of the file | completes (5 cases, 3 failures) |

By elimination the hang lives in the **last five tests of the file**:
`tableCellEditUsesOneBoundedPatch`, `committedCompositionUsesBoundedPatch`,
`newerSnapshotWithUnchangedTextReplacesNothing`,
`forcedCurrentSnapshotDoesNotRecoverWithoutStorageDrift`, and
`driftedStorageOnNewerSnapshotIsRecorded` — and, since each passes alone, in an *interaction*
among them rather than in any one.

**What is now excluded as a cause:**

- Not a COR-26..COR-31 regression — reproduces at `a4e170b` and `24341da`.
- Not `-only-testing` — `-only-testing` on `ProjectionCharacterizationTests` completes (19 cases),
  and a single named test inside `PerformanceBoundaryTests` completes.
- Not a cold build — reproduces against warm derived data that other suites build and run from.
- Not any single test tested so far — six run individually to completion (five pass, one fails).

**Therefore the hang is an interaction *between* tests in this suite**, not any one of them. The
unfiltered full run reaches `Testing started`, executes 110 cases, and then stalls, while
`-skip-testing` for the whole suite completes 354 — consistent with the suite blocking the run
once reached.

`Testing started: 0` in the filtered runs is an output-buffering artefact of hanging early, not
evidence that testing never began; that misread cost real time and is recorded so it is not
repeated.

**Next experiment:** bisect those five into pairs, then triples. Prime suspect is cross-test
residue: `EditorHarness` never calls `session.detach()`, so every test leaves a live
`EditorSession`, its `PerformanceSampler`, and a 60-second repeating `Timer` registered with
`DiagnosticRunCoordinator.shared`. Three of the five drive the recovery/drift paths, which is
where a `presentationRecovered` fault and a terminal diagnostic flush can meet an undetached
sink — `DiagnosticLog.finishSynchronously` waits for durability, and REQ-110/ARC-021 exist
precisely because that wait once depended on a main-actor hop.

Note `committedCompositionUsesBoundedPatch` drives real marked-text/IME through `NSTextView`,
which runs its own input-context machinery; an IME test left mid-composition is a credible way to
block a subsequent test that also touches marked text.

## Working notes for whoever continues this

Each of these cost real time during the investigation and none is obvious.

- **`-only-testing` needs the parentheses.** `…/PerformanceBoundaryTests/someTest` matches nothing
  and exits **0**; `…/PerformanceBoundaryTests/someTest()` runs it. A filter that matches nothing
  is indistinguishable from a passing run — always confirm a nonzero case count before believing
  a green result.
- **Quote the filter.** The target name contains a space, so building filters in a shell variable
  and expanding it unquoted splits them and yields `rc=65, cases=0`. Use a bash array:
  `A+=(-only-testing:"Markdown EditorTests/PerformanceBoundaryTests/$t()")`.
- **`Testing started: 0` does not mean testing never began.** When a run hangs early, xcodebuild's
  output is still buffered, so that marker never flushes. Reading it literally sent this
  investigation down a "the build is stuck" path for some time. Judge by the test host process,
  not by the log.
- **A fresh `-derivedDataPath` rebuilds cmark-gfm and everything else**, which takes minutes and
  looks exactly like a hang. Reuse a warm directory when bisecting; every timing quoted above is
  warm.
- **Killing a run leaves the test host alive.** Run `pkill -f "Markdown Editor.app/Contents/MacOS"`
  between attempts, or a stale host can hold state into the next run and corrupt the result.
- **macOS has no `timeout(1)`.** Run in the background and poll with a bounded loop instead.

## Requirements and invariants

- REQ-090 → `Correction`: its p95 gates cannot currently be executed.
- REQ-109 → `Correction`: its cited proofs fail — planned in COR-34, not here.
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
