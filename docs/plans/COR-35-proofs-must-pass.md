# COR-35 — A cited proof must pass, not merely exist

- **Status:** Approved; not implemented
- **Delivers:** REQ-117, REQ-118

## Scope

Close the gap that let REQ-109 stay `Done` for months while the test it cites was failing. This
is the systemic finding of the whole August–August programme and it outranks any individual
defect: without it, the next COR-34 goes unnoticed the same way.

## The gap, stated exactly

`Scripts/check-documentation-authority.sh` (COR-31) resolves every backticked identifier in a
`Done` row's **Verified by** column to a real test symbol, script, or an explicit `inherent`
justification. That closed the "cited test does not exist" hole.

It does not check that the cited test **passes**. Nothing does. `CLAUDE.md` §4 says every `Done`
requirement "records at least one automated test or justified construction/framework proof" —
which a *failing* test satisfies. The convention describes an artefact, not an outcome.

Three independent failures compounded it:

1. `PerformanceBoundaryTests` never completes (COR-32), so every failure inside it is invisible.
2. No gate correlates requirement rows with test results, so a suite that never runs is
   indistinguishable from a suite that runs green.
3. **No gate requires a test to be cited at all.** `resolvedImageRefreshesItsAttachmentOnly-`
   `WhenDisplayIdentityChanges` is failing and *no requirement references it*, so even a working
   proof-result gate would not have reported it. Forward traceability was added by COR-31 and
   this plan strengthens it; the backward direction — every test earns its place by proving
   something named — has never existed.

The consequence was concrete: REQ-109 was `Done`, its cited proof
`hiddenDelimiterCommandRefreshesAttributesWithoutReplacing` was red at `a4e170b`, `24341da`, and
`c90db74`, and PR #29's description reported *"Debug 328 passed / 0 failed"*.

This is the same shape as the defect the conformance-and-liveness programme was created to fix.
REQ-058 was satisfiable by a build where every command refused; "records a test" is satisfiable
by a test that fails. In both cases the contract checked the existence of a thing rather than the
property that thing was supposed to guarantee.

## Requirements and invariants

- **REQ-117 (new):** WHEN verification runs, the system shall prove that every test cited by a
  `Done` requirement executed and passed in that run.
- **REQ-118 (new):** The system shall map every automated test to at least one requirement or to
  a stated exemption, so that no test can fail unnoticed because nothing refers to it.
- REQ-088: Debug and Release suites compile and execute — this extends it from *compile and
  execute* to *and were observed to pass, per requirement*.
- ARC-014: no UI or manual verification is introduced; this reads structured test results.
- **Architecture impact: none.** No runtime behaviour changes; this is tooling plus a `CLAUDE.md`
  and REQUIREMENTS convention change.

## Dependency

**This plan cannot be completed before COR-32.** A gate that asserts "every cited proof passed in
this run" cannot be satisfied while a suite hangs, because the run never produces results for it.
COR-32 is therefore a hard prerequisite, not merely a related item.

It is still written now, and deliberately: the ordering exists because the gap is understood, not
because the gap is unimportant.

## Production route

This is a tooling and process increment; no application source changes.

Add:

- `Scripts/check-proof-results.sh` — takes an `.xcresult` bundle, extracts the executed test
  identifiers and their outcomes (`xcrun xcresulttool get test-results tests --format json`),
  parses `docs/REQUIREMENTS.md`, and fails when:
  - any `Done` row cites a test symbol that did not execute or did not pass (REQ-117); or
  - any executed test is referenced by no requirement row and appears in no exemption list
    (REQ-118). Exemptions are declared in the script with a reason — structural gates that
    guard an absence, and harness self-checks, are the legitimate cases.

  A cited **suite** is satisfied when every test in it passed. Rows justified as `inherent`, or
  citing only a `Scripts/` path, are exempt from REQ-117 and must say so.

  `xcresulttool`'s JSON shape is version-dependent; the extraction was verified working against
  the Xcode in use during COR-32's investigation via
  `xcrun xcresulttool get test-results tests --path <bundle> --format json`, walking nodes for
  `nodeType == "Test Case"` and `result`. Pin that shape in a fixture so a future Xcode change
  fails the check loudly rather than silently matching nothing.

Modify:

- `Scripts/fast-check.sh` — run the new check against its own result bundle, and stop reporting
  only "N passed, M failed". A count is not a mapping: 354 passing tests tells you nothing about
  *which* requirement is unproven.
- `CLAUDE.md` §4 — state that a `Done` requirement's proof must be **observed to pass** in the
  run that closes the increment, and that a suite which does not complete leaves every
  requirement citing it unproven, not proven.
- `CLAUDE.md` §9 — add a Definition-of-Done row: "Every `Done` requirement's cited proof observed
  passing in this run."
- `docs/REQUIREMENTS.md` conventions — state the same, alongside the existing forward/liveness
  rules.

## Implementation phases

1. Land COR-32 so a complete result bundle exists.
2. Write `check-proof-results.sh` against a known-good bundle; confirm it reports zero problems.
3. Rehearse it failing four ways, each of which actually happened: a cited test that fails
   (`hiddenDelimiterCommandRefreshesAttributesWithoutReplacing`); a cited test that never
   executed because its suite hung (any test in `PerformanceBoundaryTests` before COR-32); an
   uncited test that fails (`resolvedImageRefreshesItsAttachmentOnlyWhenDisplayIdentityChanges`);
   and a cited symbol that no longer exists (COR-31's check, re-asserted here so the two are
   known to compose).
4. Wire it into `fast-check.sh` and the closing sequence.
5. Update `CLAUDE.md` and the REQUIREMENTS conventions.
6. Delete this plan.

## Automated non-UI proof

Gate scripts are proven by rehearsed failure, this repository's established standard. The four
rehearsals above are the proof. Additionally assert that the check is not vacuous: it must report
a nonzero number of *verified* rows, so a parsing bug that matches nothing cannot pass as
success — the same trap that made an early COR-28 rehearsal exit 0 having run no tests.

## Instrumentation and performance evidence

None; no runtime behaviour changes. Record the added wall-clock cost of the check so it does not
quietly turn the short loop back into a long one.

## Failure and rollback behavior

If a requirement's proof cannot be mapped to a test identifier automatically — prose citations,
suite-level citations with no stable identifier — the check reports it as **unmapped** and fails,
rather than passing it silently. Unmapped is a documentation defect to fix in REQUIREMENTS, not a
tolerance to build into the tool. If the volume of unmapped rows makes that impractical at first,
the mapping is completed as part of this increment; it is not deferred by weakening the check.

## Deletion and conformance gate

- No requirement may be moved to `inherent` merely to escape this check; every such change needs
  its justification written in the row.
- `fast-check.sh` keeps its "not a release gate" banner.
- Both gate scripts pass; delete this plan in the implementing change.
