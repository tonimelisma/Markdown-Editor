# COR-66 — Leak-free process verification

- **Status:** Approved; not implemented
- **Requirements:** new REQ-142 (process-level verification shall reject a run that leaks memory)
- **Delivers:** REQ-142
- **ARC invariants:** new ARC-Q26 (a process-level verification run reports zero leaked allocations
  or the run is a failure), sibling to `ARC-Q12`/`ARC-Q13`/`ARC-Q21`, added rather than redefining
  `ARC-Q12` — no architecture change, no `ENGINEERING.md` §15 argument required.
- **Executor:** any agent. Opens with a Stage 0 POC per `CLAUDE.md`'s embedded-discovery rule: the
  exact behavior of `leaks -atExit --` wrapping this app's own smoke launch is not provable from
  documentation alone and must be observed against the real binary before Phases 1–2 are written.

## Context

`ARC-Q12` already launches the built application as a real subprocess (`Scripts/smoke-test.sh`) and
asserts only on structured diagnostic records — the narrow, approved carve-out for process-level
verification. Apple's `leaks` tool (`man leaks`) can wrap a launched command with `-atExit --
<command>`, running its leak check automatically at the wrapped process's exit and exiting 0 (no
leaks), 1 (leaks found), or >1 (tool error). This is a natural extension of the same carve-out:
nothing is driven or read from the UI; the assertion is a leak count from a command-line tool
against a process the app already launches for other reasons.

What is **not** known without running it: whether wrapping the launch in `leaks -atExit --`
preserves the wrapper's exit code as the *app's own* exit status (which `smoke-test.sh` currently
uses to detect a crash) or replaces it with `leaks`'s own 0/1/>1 leak-result code, whether the
polling loop that waits for the JSON Lines run file still meets its timing budget under the
`MallocStackLogging=lite` overhead `-atExit` documents itself as adding automatically, and whether
`leaks`'s report text is stable enough to parse. These are exactly the empirical questions
`CLAUDE.md`'s Stage 0 POC mechanism exists for.

## Phase 0 — POC: what does `leaks -atExit --` actually do to this script?

Throwaway target: run the existing built smoke binary through
`leaks -atExit -- "$binary" -ApplePersistenceIgnoreState YES --diagnostic-smoke-exit "$fixture"` with
the same environment `smoke-test.sh` already sets, and observe:

| # | Probe |
| --- | --- |
| X1 | Does the wrapper's own exit code (`$?` after `wait`) equal the wrapped app's real exit status, or `leaks`'s own 0/1/>1 leak-result code? |
| X2 | Does the JSON Lines run file still appear within the existing 10 s poll budget (100 × 0.1 s)? |
| X3 | Is `leaks`'s report line machine-parseable in a stable format (e.g. `Process 1234: 0 leaks for 0 total leaked bytes`) on stdout? |
| X4 | Does wall-clock time for the whole smoke run increase measurably (report the delta) under `MallocStackLogging=lite`? |
| X5 | Does `$!` captured immediately after `leaks -atExit -- "$binary" ... &` refer to a PID that supports the existing `kill -0 "$app_pid"` polling loop, or does it need to change to track `leaks`'s own PID instead of the app's? |

### Decision table — applied mechanically

| Observation | Branch |
| --- | --- |
| X1: wrapper exit code == app's real exit status | Keep `smoke-test.sh`'s existing `if [[ "$app_exit_code" -ne 0 ]]` crash check unchanged; add a **separate** parse of X3's report line for the leak count |
| X1: wrapper exit code == `leaks`'s own 0/1/>1 | The existing crash check is now shadowed. Rely instead on `verify-smoke-log.py`'s existing requirement for a terminating JSON Lines record (a crash before that record already fails today, independent of exit code) for crash detection, and use the wrapper's exit code **directly** as the leak result: `0` → zero leaks (continue), `1` → leaks found (fail REQ-142 with the parsed count), `>1` → tool error (fail as inconclusive, never silently treated as a pass) |
| X2: run file still appears within 10 s | No change to the poll budget |
| X2: run file takes measurably longer | Widen the poll budget specifically for the leak-checked path and record the measured delta in this plan's Phase 1 rewrite, rather than silently loosening the ordinary (non-leak) smoke path |
| X3: report line format matches `\bleaks? for \d+ total leaked bytes\b` | Parse it with that pattern |
| X3: format differs from the man page's documented example | Record the actual observed format and use it; do not assume |
| X4: wall-clock overhead ≤ 20% of the unwrapped run | Wire leak-checking into `smoke-test.sh` directly, so it runs in `fast-check.sh` (the PR-triggered inner loop) as today |
| X4: wall-clock overhead > 20% | Gate leak-checking behind `SMOKE_CHECK_LEAKS=1`, set only by `full-check.sh` (the closing-sequence/pre-merge gate), and leave the ordinary `fast-check.sh` smoke run unwrapped — record the measured overhead as the reason |
| X5: `$!` after the wrapped launch supports the existing polling loop unchanged | No change |
| X5: it does not (e.g. `leaks` forks and `$!` is unusable for `kill -0`) | Poll for the app's PID a different way — `pgrep -x` against the binary's basename scoped to the smoke run's own temp `workdir`, recorded exactly, since a fixture-scoped match is required to avoid matching an unrelated running instance of the app on the developer's own machine |
| No branch above applies (`leaks -atExit` fails outright against a SwiftUI/AppKit `NSApplication` process, or its overhead exceeds the existing `SMOKE_EXIT_SECONDS` budget by more than the app's own exit timer can absorb) | **The increment fails as designed.** Do not weaken `ARC-Q12`, do not silently skip leak-checking, and do not merge a leak check that sometimes runs. Return to a separate discovery unit to evaluate `MALLOC_STACK_LOGGING=1` plus a separate `leaks <pid>` call as a non-`-atExit` fallback, and record why `-atExit` itself did not work |

**Then, without stopping:** write `docs/research/DISC-09-leaks-atexit-behavior.md` (evidence-only
authority, dates, macOS/Xcode versions, method, the five probe outputs, the branch taken per
probe), delete the POC, rewrite Phases 1–2 below to match the observed branches, commit, and
continue.

## Phase 1 — wire the check into the smoke script (shape depends on Phase 0's X1/X4/X5 branches)

`Scripts/smoke-test.sh` launches through the `leaks -atExit --` wrapper (or the POC's recorded
fallback), captures the leak result via whichever mechanism X1's branch selected, and fails the
script with a clear message (`smoke: N leaks detected, M bytes — see <log path>`) rather than a
bare nonzero exit, matching the existing script's style for its other failure messages (`smoke: no
run file appeared…`, `smoke: app did not exit in time`).

## Phase 2 — the requirement and gate wiring

`REQUIREMENTS.md` gains REQ-142; `full-check.sh` (and `fast-check.sh` if X4's branch keeps it
there) calls the leak-checked smoke path. If X4 gated it to `full-check.sh` only, `fast-check.sh`
keeps calling the ordinary unwrapped `smoke-test.sh`, and this plan records that as the accepted
cost of keeping the inner loop short — the same trade-off `COR-31`'s header comment already states
for excluding the performance corpus from `fast-check.sh`.

## Proof

- `Scripts/test-smoke-leak-detection.sh` (new, fixture-based, in the shape of
  `Scripts/test-verify-smoke-log.sh`): a fixture wrapping a deliberately leaking scratch binary (a
  minimal `NSObject` subclass retained in a global array and never released, built as a throwaway
  Debug target or a `#if SMOKE_LEAK_FIXTURE` branch removed after the rehearsal) must be observed
  to fail the leak check before this gate is trusted — this **is** the `CLAUDE.md` §9 rehearsal,
  not a separate step, because a leak check that has never been observed to catch a real leak is
  exactly the tautology-shaped defect `COR-61` exists to prevent.
- The ordinary (non-leaking) smoke run continues to pass, proving the gate does not cry wolf.

## Instrumentation and performance evidence

Record the wall-clock delta from Phase 0's X4 in this plan before deleting the POC. If leak
checking is gated to `full-check.sh` only, no `fast-check.sh` regression exists by construction.

## Failure / rollback

Additive to a verification script; no production runtime path changes. If the leak check proves
flaky in practice (a false positive from a known-benign one-time system-framework allocation),
record the specific allocation as a documented, named exemption in the script — never as a blanket
`|| true` that silences the whole gate, which is the exact shape of defeat `CLAUDE.md` §4 already
records for the instrumentation-coverage gate's two prior defeats.

## Deletion / conformance gate

- The Phase 0 POC code is deleted; its findings live only in `DISC-09` and this plan's rewritten
  phases.
- No leak exemption is a blanket suppression; each is a named, dated, single allocation.
- `Scripts/check-documentation-authority.sh` and `Scripts/check-proof-results.sh` pass.
