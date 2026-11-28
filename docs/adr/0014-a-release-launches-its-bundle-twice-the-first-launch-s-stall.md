# 0014. A release launches its bundle twice; the first launch's stall is the runner's

- Status: accepted
- Date: 2026-11-27

## Context and problem

**What happened.** v1.0.1 could not be published. Release runs 45921027714 and 45922511341 each
built, signed and launched it, recorded two `mainActorStall` faults (1.4 s), and refused.
`repeat-smoke.yml`, now able to launch the hardened Release bundle, found this:

| Runs | First launch on the runner | Later launches |
| --- | --- | --- |
| Release, the same copy (45923148087, 45923150495) | stalled, 2 of 2 | 12 passed |
| Release, a fresh copy at a new path each time (45923944905) | stalled | 7 passed |
| Release, first launch only (45924753146; 45924758118 under `spindump`) | stalled, 2 of 2 | not run |
| Release, `taskpolicy -d important` (45925257684, 45925260329) and its control (45925262536) | stalled, 3 of 3 | 5 passed, 1 `presentationRecovered` (below) |
| Release, first launch 45 s after the build (45924755511) | passed | 2 passed |
| Release, first launch after warming the profilers for several seconds (45923942236) | passed | 5 passed |
| Debug, as `check.sh` launches it (45922040268) | passed (11 s, the slowest) | 11 passed |

In all, the first launch shortly after the build stalled every time: 10 of 10, counting the two
release runs. None of the 43 later launches stalled. The `spindump` of the stalled first launch
in 45924758118 shows the cause. The machine had been up 239 s, and 12% of the shared cache was
resident. The main thread spent 294 of its 546 samples in one synchronous call:
`makeWindowControllers`, which lays out the first window, builds both editors, and runs AppKit's
first-use set-up (`NSSpellChecker`, the text-input cursor, ICU locale tables, the default font).
192 of those samples were asleep in the kernel's `throttle_lowpri_io`, with 4,644 page-ins, while
Spotlight indexed the build. What stalls is a cold virtual disk, read through a throttled I/O
policy, on a just-booted VM. A Mac that people use is not in that state.

**Also seen.** Control run 45925262536's second launch recorded `presentationRecovered`
(`patchUnprovable`, COR-71): a provisional WYSIWYG presentation disagreed with the authoritative
parse of the same revision. It was seen once in about 40 launches. It is an application fault,
and a release that hits it is still refused. It was two defects, both fixed the same day. The
check compared snapshot IDs, which always differ, so it fired on any second snapshot of a
revision, including after every WYSIWYG keystroke, where it also dropped the caret. And every
semantic edit's revision was parsed twice (`PresentationRecoveryTests`; architecture.md §7).

## Decision drivers

**Criteria** (vision.md's evaluation section):

1. Automated verification: the gate must keep failing for the app's defects.
2. Deterministic failure behaviour: a release must not depend on how warm the runner is.
3. Measured performance: a measurement describes only the input it was measured on (CLAUDE.md §3).
4. Maintenance cost.

## Considered options

| Option | 1 | 2 | 3 | 4 |
| --- | --- | --- | --- | --- |
| **Two launches; the first may stall (chosen)** | ✓ every check binds on a launch of the exact bundle, and every check but one on its first | ✓ no stall in 43 later launches | ✓ the stall is asserted on a warm launch, as `check.sh`'s already is | ✓ one script, an existing verifier flag |
| Wait a fixed time after the build | ✓ | ~ 45 s worked once; nothing says how long is enough | ✓ | ✓ |
| Launch with unthrottled I/O (`taskpolicy -d important`) | ✓ | ✗ tried: the first launch still stalled, 2 of 2 | — | ✓ |
| Allow `mainActorStall` on every release launch | ✗ a stall the app causes would ship | ✓ | ✗ | ✓ |
| Do nothing | ✓ | ✗ no release can publish | ✓ | ✓ |

## Decision

**Decision.** `Scripts/release.sh` launches the signed bundle twice. The first launch passes every
smoke check except `mainActorStall`, which it is allowed. The bundle must start, open the
fixture, take both edits, and exit cleanly with no other fault. The second launch is held to every
check, stalls included.

## Consequences

**Where it is worse.** A stall that only the very first launch on a machine shows, and that the
app causes, no longer stops a release. `check.sh`'s smoke launch could not catch one either: it
comes after the test suite has warmed the runner. The 2.9 s first-window cost on a cold machine
is real work, though. Building the Source editor only when Source is first shown is one way to
cut it, and it is recorded as open in roadmap.md.

**Also changed: a docs-only push no longer publishes an app that `main` has not built.** v1.0.1
was published from #91, a documentation change. #90's own `main` run had failed two timing-bound
tests, and its re-run was cancelled when #91 landed. #91's CI skipped macOS, because its diff was
documentation, and passed, and Release then published the app #90 had changed. That tree had
passed `check.sh` as pull request #90, and both of the release's launches passed, so v1.0.1 is
the tree that was tested. Even so, nothing on `main` had required it. CI's `changes` job now also
asks, on a push to `main`, whether the app (`Scripts/lib/app-paths.sh`, the list `release.sh`
publishes by) differs from the newest release. If it does, the macOS job runs.

## Confirmation

`Scripts/release.sh` launches the signed bundle twice through `Scripts/smoke-test.sh` and refuses to publish on any fault but the first launch's `mainActorStall`; `Scripts/test-verify-smoke-log.sh` proves the verifier's discrimination.

## Retirement proof

Runners whose first launch after a build no longer stalls, shown by `repeat-smoke.yml` over several runs.

## Reversal plan

Hold the first launch to every check again (one flag in `Scripts/release.sh`).
