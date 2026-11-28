# 0025. The tour drives the Release bundle

- Status: accepted
- Date: 2026-11-27

## Context and problem

**Why.** Every tour until now ran the unoptimised Debug build. Its budget records (a
`nativeInputCallback` p95 of 10 ms against 8, a first `parseProjection` of 655 ms, a
`layoutApplication` p95 of 41 ms) described code nobody runs, so the tour could neither show the
app within its budgets nor show it outside them. Its behavioural checks are the same in either
build: the one Debug-only code, ARC-015's assertion, also writes a fault record, which
`expect-no-faults` reads.

## Decision drivers

**Criteria:** evidence describes the shipping binary (vision.md, Evaluation: "Performance evidence
records … build configuration"); the tour still catches every behavioural defect; profiling stays
possible.

## Considered options

| Option | Timings describe the shipping app | Behaviour checked | Profilable |
| --- | --- | --- | --- |
| **Release by default, Debug on request (chosen)** | ✓ | ✓ | ✓ with `configuration: Debug` |
| Debug, and disregard its budget records | ✗ | ✓ | ✓ |
| Both builds every run | ✓ | ✓ | ✓ but twice the runner time for one verdict |

## Decision

**Decision.** `agent-drive.yml` builds Release by default, hardened ad hoc as
`repeat-smoke.yml` hardens it. It has no update key, so it never checks for updates, and it
differs from the bundle `Scripts/release.sh` publishes only in that key, its version numbers and
its signature's timestamp.
`configuration: Debug` remains for a probe that profiles with `sample`, which cannot attach to a
hardened app.

## Consequences

**Where it is worse.** A cold Release build takes longer than Debug, whose compilation cache CI
keeps warm. A Release tour cannot be profiled, so a stall it finds is chased with a Debug probe,
where the timings are larger than the ones that were found.

## Confirmation

`agent-drive.yml` defaults to `configuration: Release` and hardens the bundle with `Scripts/adhoc-harden.sh`.

## Retirement proof

A Debug build whose timings match Release's.

## Reversal plan

Change the workflow's default input to Debug.
