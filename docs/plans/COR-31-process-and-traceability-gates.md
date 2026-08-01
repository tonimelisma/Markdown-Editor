# COR-31 — Process and traceability gates

- **Status:** Approved; not implemented

## Scope

The working process catches serious defects — the PR history shows a dead trace-event vocabulary,
a machine-dependent restoration veto, a screenshot that could have captured the user's own
document, and a fourth full-replacement route all found and fixed by review. What it does not do
is **close classes**. The same blindness that produced the COR-23 full-replacement defect was
correctly diagnosed in PR #28's own review comment — "each suite is individually sound and
jointly blind" — and then recurred three PRs later as COR-25, and again as the four commands
COR-26 fixes.

This increment converts the recurring diagnoses into mechanisms, and closes the gaps in the
existing gate scripts.

### 1. Traceability is enforced backward but not forward

`Scripts/check-documentation-authority.sh` proves every `REQ-###` appearing in code exists in
REQUIREMENTS, and that `Done` rows have non-empty "Implemented in" and "Verified by" columns. It
does **not** prove the contents of those columns name anything real — the column is free prose. A
renamed or deleted test leaves the gate green.

A manual extraction over all 96 rows at `88b7bd3` found zero stale references, so this is a
missing guard rather than an existing rot: 72 rows name a real test function, 9 are `inherent`,
and 14 name a real suite type. The gate should keep it that way without a human re-checking.

### 2. A `Done` requirement can contradict a known open defect

Before `88b7bd3`, REQ-058 was `Done` while ROADMAP carried a reproduced defect against it and the
row's own "Inc" column named the in-flight correction `COR-25`. REQUIREMENTS' own convention says
that state is `Correction`. PR #28 handled the analogous case correctly by returning REQ-109 to
`Correction`, so the habit exists — it just is not enforced.

### 3. The requirement set has almost no liveness properties

Six of the seven ENGINEERING §1 architecture drivers are safety properties. REQ-058 reads
"…unsafe or ambiguous commands shall be disabled or refused without changing source", which a
build where **every** formatting command silently does nothing would satisfy. Four commands did
exactly that, and no requirement was violated. `CLAUDE.md` §4 requires proof that a defect fails
before a fix, but nothing requires that a user-invocable action has a proof it *succeeds*.

### 4. The inner loop is slow enough to discourage running it

A full Debug `xcodebuild test` under ordinary contention spent 26 minutes without reaching
execution during this review. REQ-090 already records that the latency gate must be run *focused*
or it measures main-actor contention instead of the edit path. A quality system with a 25-minute
inner loop is run less often than one with a short one.

## Requirements and invariants

- REQ-113 (introduced by COR-26): enabled implies performable — the first liveness requirement.
- ARC-014: no production or verification claim depends on manual or UI testing; unchanged.
- **Architecture impact: none.** This increment changes `CLAUDE.md`, the gate scripts, and
  REQUIREMENTS statuses. It defines no new runtime behavior.

## Production route

This is a process and tooling increment; it touches no application source.

Modify:

- `Scripts/check-documentation-authority.sh`
  - **Forward traceability:** for each `Done` row, extract every backticked identifier from
    "Verified by" and require each to resolve to a declared `func`, `struct`, `final class`, or
    `enum` in `Markdown EditorTests`, or to an existing path under `Scripts/`. A row whose only
    verification is `inherent (...)` is accepted and must say so explicitly.
  - **Status consistency:** fail when a `Done` row's "Inc" column names an increment that ROADMAP
    still lists as active (🔵), or when ROADMAP contains an "Open defect" section naming a `Done`
    requirement.
  - **Plan freshness:** fail when a plan file has existed on `main` for more than a stated number
    of commits without being implemented or re-approved, so an approved plan cannot quietly
    become stale architecture.
- `CLAUDE.md`
  - §4: add that a user-invocable action requires a **liveness** proof — an automated test that
    the action succeeds on its ordinary input — in addition to its refusal proofs. State that a
    refusal-only proof set does not satisfy a requirement that promises a capability.
  - §4: add that a proof asserting a model or attribute value does not discharge a requirement
    about rendered geometry; where a requirement is about what the user sees, the proof asserts
    laid-out geometry from directly constructed AppKit objects.
  - §6: add that when a review identifies a defect **class**, the increment closes the class with
    a structural gate, or records explicitly why it cannot and what remains open. Fixing only the
    reported instance is not sufficient triage.
  - §9: add Definition-of-Done rows for "Liveness proofs present for every user-invocable action
    touched" and "Gate scripts rehearsed failing".
- `docs/REQUIREMENTS.md` — conventions section: state that a requirement promising a capability
  carries at least one liveness proof, and that `Correction` is mandatory, not optional, once a
  defect against a `Done` row is reproduced.

Add:

- `Scripts/fast-check.sh` — the short inner loop: both gate scripts plus the non-performance test
  suites, excluding the 100,000-corpus performance gates, which stay in the full run and in the
  Release proof. Document that a green fast check is not a release gate.

## Implementation phases

1. Add forward traceability to the documentation gate; rehearse it failing by renaming a cited
   test in a scratch copy.
2. Add status consistency; rehearse it failing by marking a requirement `Done` while ROADMAP
   lists its increment active.
3. Add plan freshness; rehearse failing.
4. Add `Scripts/fast-check.sh` and measure both loop times; record them in ROADMAP.
5. Update `CLAUDE.md` §4, §6, §9 and the REQUIREMENTS conventions.
6. Delete this plan.

## Automated non-UI proof

Gate scripts are proven by rehearsed failure, which is this repository's established standard —
`check-instrumentation-coverage.sh` was rehearsed against a deliberately unwired event including
one referenced only inside a nested block comment, and REQ-098's threshold was rehearsed failing
at a lowered value. Each new check here is rehearsed the same way, against a scratch copy so the
working tree is never left in a failing state.

No application behavior changes, so no runtime proof, instrumentation, or performance evidence is
required beyond confirming the existing suites and both smoke scripts still pass.

## Failure and rollback behavior

If forward traceability cannot be made reliable for prose-heavy rows without unacceptable false
positives, the check is narrowed to backticked identifiers only — which is where the risk of
silent rot actually lives — and the narrowing is documented in the script rather than the check
being dropped. A gate that is wrong is worse than a gate that is narrow.

## Deletion and conformance gate

- Every new check rehearsed failing before it is trusted.
- `CLAUDE.md` and `AGENTS.md` remain the same file (symlink check already enforced).
- Both gate scripts pass on the final tree; both smoke scripts pass; delete this plan in the
  implementing change.
