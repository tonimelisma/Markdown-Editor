# COR-18 — Restore the proof floor

- **Status:** Approved; not implemented
- **Kind:** App-code/test/script correction; one worktree, branch, PR, and squash merge
- **Requirements:** REQ-088, REQ-090, REQ-098, REQ-104
- **Architecture:** Conforms to ARC-014, ARC-Q05, ARC-Q12, ARC-Q13; establishes usable proof for
  later ARC-020 work without changing production editor architecture
- **Depends on:** none
- **Must finish before:** COR-19, INC-05, COR-20, COR-21, INC-06

## Goal

Make the repository's gates capable of disproving the rewrite's claims. Debug and Release tests
must compile and execute, performance tests must fail when they execute zero samples, and both
smoke scripts must use one strict structured-log verifier. This increment does not fix production
performance or typography.

## Baseline defects to reproduce

1. A Release `xcodebuild test` fails because
   `ReconciliationInvariantTests` assigns `EditorSession.trapsOnReconciliationViolation`, which
   exists only under `#if DEBUG`.
2. The Release performance tests compile all test sources even when `-only-testing` selects three
   tests, so the failure prevents every Release metric.
3. The old smoke implementations duplicate verifier logic.
4. A direct-only `hostUpdateEnded` count understates rate-collapsed `repeated` events.
5. A sorted sequence comparison permits duplicate sequence numbers.
6. The rich fixture does not expose paragraph spacing or soft-versus-hard break typography.
7. Fixed repository DerivedData creates `.smoke-build`; coverage builds create `default.profraw`.

Record exact failing command output in the PR before changing code.

## Files

### Modify

- `Markdown Editor/EditorSession.swift`
- `Markdown EditorTests/ReconciliationInvariantTests.swift`
- `Markdown EditorTests/PersistentEditorCharacterizationTests.swift`
- `Markdown EditorTests/ProjectionCharacterizationTests.swift`
- `Markdown EditorTests/DiagnosticLogTests.swift`
- `Scripts/smoke-test.sh`
- `Scripts/smoke-screenshot.sh`
- `Scripts/Fixtures/smoke-rich.md`
- `.gitignore` only if a tool necessarily writes a repository-local artifact after the temporary
  path changes; do not use ignore rules to conceal avoidable artifacts
- `docs/REQUIREMENTS.md`
- `docs/ROADMAP.md`

### Add

- `Scripts/verify-smoke-log.py`
- `Scripts/Fixtures/SmokeLogs/valid.jsonl`
- `Scripts/Fixtures/SmokeLogs/duplicate-sequence.jsonl`
- `Scripts/Fixtures/SmokeLogs/collapsed-storm.jsonl`
- `Scripts/Fixtures/SmokeLogs/two-documents.jsonl`
- `Scripts/Fixtures/SmokeLogs/no-reconciliation.jsonl`
- `Scripts/Fixtures/SmokeLogs/no-performance-samples.jsonl`
- `Scripts/Fixtures/SmokeLogs/fault.jsonl`
- `Scripts/Fixtures/SmokeLogs/no-run-end.jsonl`
- `Scripts/test-verify-smoke-log.sh`

### Delete

- Both embedded Python verifier blocks from the shell scripts.
- Any repository-local `.smoke-build`, `default.profraw`, or `__pycache__` created by this unit
  after provenance is confirmed.
- This plan after implementation.

## Implementation

1. Make the intentional reconciliation-violation control testable in Release without weakening
   production behavior.
   - Prefer an internal initializer/test seam that defaults to trapping in Debug and never traps
     in Release.
   - Do not expose mutable production policy publicly.
   - Remove conditional API shape that makes the test bundle compile differently by configuration.
2. Add one shared performance-evidence helper returning an explicit result:
   `PerformanceEvidence { warmups, samples, median, p95, failures }`.
   - Require `samples.count > 0`.
   - Make a zero-sample evidence assertion fail in both Debug harness tests and Release gates.
   - Do not label output `config=Release` by hard-coded text; derive build configuration or accept
     an explicit compiler-defined value.
3. Preserve the three approved thresholds but rename no production metrics here:
   - existing keystroke translation <8 ms;
   - mode toggle <16 ms;
   - parse/index/projection <100 ms.
   COR-20 changes the metric boundary and names.
4. Implement `verify-smoke-log.py` as the single verifier. It must assert:
   - parseable non-empty JSON Lines;
   - schema version 1 and production host;
   - pairwise strictly increasing event sequence;
   - exactly one `documentOpened` and one `documentLoaded`;
   - one non-null document handle used consistently;
   - direct plus `repeated(of: hostUpdateEnded).data.count` update total at/below threshold;
   - editable availability for that document;
   - exactly one `reconciliationApplied` for that document;
   - a later direct `hostUpdateEnded`;
   - exactly one reconciliation `performanceSummary` with count at least one;
   - no `error` or `fault`; and
   - `runEnd` as the final event.
5. Make malformed-log fixtures discriminate each assertion. `test-verify-smoke-log.sh` must
   require the valid fixture to pass and every invalid fixture to fail for its named reason.
6. Make both smoke scripts call the shared verifier.
7. Use `mktemp -d` DerivedData by default; preserve `SMOKE_DERIVED_DATA` as an explicit override.
   Clean only directories the script created.
8. Keep screenshot capture passive and window-only.
   - Wait for editable availability, applied reconciliation, and a later host update.
   - Retry a discovered window's capture for a bounded interval while the exact PID remains alive.
   - Require a non-empty image file; do not trust `screencapture` exit status alone.
   - Report capture/environment failure separately from application diagnostic failure.
9. Keep the rich fixture within one default screenshot while covering two paragraphs, a soft
   break, a formal hard break, headings, all inline styles, image, nested lists, task states,
   quote, code, table, thematic break, and literal HTML.
10. Reconcile REQ-088/090/104 only for evidence actually restored. REQ-090 remains `Correction`
    because the metric boundary is still incomplete until COR-20.

## Automated proof

- `Scripts/test-verify-smoke-log.sh`
- Full Debug test suite in isolated DerivedData.
- Full Release test suite with `ENABLE_TESTABILITY=YES` in isolated DerivedData.
- Focused Release performance tests, with output retaining corpus identity and nonzero samples.
- `Scripts/smoke-test.sh`
- `Scripts/smoke-screenshot.sh` when Screen Recording permission is available.
- A lowered host-update threshold rehearsal must fail.

No XCUITest, Accessibility inspection, click, typing, or UI assertion is permitted.

## Failure and rollback

- A capture-environment failure does not turn into an application pass; report it distinctly.
- If Release performance is unstable, preserve raw evidence and return to discovery before
  changing thresholds.
- Do not weaken or skip an unrelated Release test to make the selected tests compile.
- Revert the whole branch if the shared verifier cannot discriminate all malformed fixtures.

## Conformance and completion gates

- `rg` finds exactly one implementation of each smoke assertion.
- `git status --short` contains no generated build/profile/bytecode artifact.
- Debug and Release targets compile without concurrency warnings.
- Documentation-authority and instrumentation-coverage scripts pass.
- Separate-agent review is complete.
- Last-10-PR comment triage and stale-work sweep are complete.
- Capture and review one rich screenshot if the environment permits; otherwise the increment
  remains incomplete.
- Delete this plan in the implementing branch.
