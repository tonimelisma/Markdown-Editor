# Plans

This directory contains only approved, unimplemented production plans. Several plans may coexist
while waiting to be built. A plan is deleted in the same change that completes its implementation;
Git retains the historical plan.

Plans implement the current architecture in `../ENGINEERING.md`. They do not redefine it. Every
plan must name:

- requirements and `ARC-###` invariants;
- a machine-readable **Delivers:** line naming the requirements this plan is expected to move to
  `Done`, or `none (refactor; no requirement changes status)`;
- architecture impact (`none` unless separately researched and approved);
- exact production files/types/routes to add, modify, and delete;
- ordered implementation phases;
- automated non-UI proof;
- instrumentation and performance evidence;
- failure and rollback behavior;
- a deletion/conformance gate proving no displaced path remains; and
- an **Executor** line saying who may implement it and what judgement it demands.

## Executing a plan

Read `../../CLAUDE.md` §3 (increment lifecycle) and §9 (definition of done) first. Then:

1. **Check the Executor line and the blockers.** Some plans are blocked on another increment; some
   demand judgement that an unattended agent should not supply alone. Both are stated in the header.
2. **Take them in ROADMAP order.** The order encodes real dependencies, not preference. In the
   current programme, COR-56 must land before COR-57 because COR-57's gate receipt requires a passing
   `Scripts/fast-check.sh`, which cannot pass until COR-56 repairs the test target.
3. **Work in a worktree on a branch** (`inc-NN-slug` / `cor-NN-slug`), never on `main`. Swift changes
   need a PR and a separate-agent review; docs and project config commit directly to `main`.
4. **Run the gates and read their output.** `Scripts/fast-check.sh` is the inner loop; the closing
   sequence in §3 is the release gate. A plan is not done because its steps were performed — it is
   done when its stated proof is observed passing.
5. **If the plan is wrong, stop.** A plan that does not survive contact with the code is a finding.
   Say so and re-plan; do not improvise production changes the plan does not authorise, and do not
   commit a placeholder to keep the sequence moving. On 2026-08-10 ten increments were committed as
   one-line stubs rather than reported as not-started, and the ROADMAP recorded them as delivered.

### `file.swift:NNN` references are indicative; symbols are authoritative

Plans cite line numbers to make a construct findable. Line numbers drift. If a citation no longer
lands on what its surrounding prose describes, trust the description and the symbol name, and fix the
citation in the same change. A citation that has drifted is not a licence to guess at what was meant.
