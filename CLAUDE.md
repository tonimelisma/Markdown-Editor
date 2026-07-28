# CLAUDE.md — Operating Manual

This file defines how agents work in this repository. `AGENTS.md` is a symlink to this file.

Product truth lives in `docs/VISION.md`; current engineering architecture in
`docs/ENGINEERING.md`; behavior in `docs/REQUIREMENTS.md`.

This file is self-maintaining. A user correction to the working process is updated here in the
same change and verified in the Definition of Done.

> ## PRIME DIRECTIVE — informed consent
>
> Nothing is written into the specs without the user's explicit, informed approval first.
>
> “Specs” includes `VISION`, `ENGINEERING`, `REQUIREMENTS`, `ROADMAP`, plans, and research
> recommendations. The order is research → findings/options/questions → explicit approval →
> documentation. Approval is specific; silence is not consent.

## 1. Product

A native macOS Markdown editor: pure Swift, SwiftUI-first with narrow AppKit adapters, local-first,
no accounts, no lock-in, and ordinary Markdown files.

Read `docs/VISION.md`, `docs/ENGINEERING.md`, `docs/REQUIREMENTS.md`, and `docs/ROADMAP.md` before
planning or changing production code.

## 2. Documentation authority

Code and tests are canonical implementation. The specs are the synchronized current intent layer.
The working tree contains current truth and actionable work; Git is the archive.

| Path | Sole job |
|---|---|
| `docs/VISION.md` | Durable product direction, priorities, and product policies |
| `docs/ENGINEERING.md` | Authoritative current architecture, state ownership, runtime contracts, `ARC-###` invariants, quality scenarios, and risks |
| `docs/REQUIREMENTS.md` | Current numbered behavior requirements (`REQ-###`) with code/test traceability |
| `docs/ROADMAP.md` | Current delivery state, active sequence, and uncommitted backlog |
| `docs/research/` | Still-valid costly evidence; never architecture authority |
| `docs/plans/` | Approved and not-yet-implemented code plans |

There is no ADR system and no documentation archive.

### No stale documents

- Rewrite or delete stale text in the same change that makes it stale.
- Do not retain obsolete guidance behind “superseded”, “corrected by”, “historical”, or warning
  banners.
- Implemented plans are deleted in the implementing change. Multiple approved pending plans may
  coexist.
- Research may remain when facts are still valid, useful, and expensive to reproduce. Each
  research file states evidence-only authority, first-researched/last-verified dates, environment,
  reproducible method, and refresh triggers.
- Refresh or delete research when a dependency, SDK, requirement, or architectural assumption
  invalidates material findings.
- Historical rationale, completed plans, and displaced architecture remain available through Git.
- Run `Scripts/check-documentation-authority.sh` before every commit.

## 3. Increment lifecycle

### Discovery unit

1. Pick or define the next increment in ROADMAP.
2. Research every unknown online and against real macOS/Swift APIs. Use bounded throwaway POCs
   where documentation does not prove behavior.
3. Present findings, credible options, trade-offs, and open product/engineering questions.
4. Obtain explicit informed approval.
5. Update VISION/ENGINEERING only for approved current truths.
6. Add/update EARS requirements.
7. Write an approved, code-focused plan.
8. Reconcile all affected docs and remove stale material.
9. Commit doc/config work directly to `main`.

### Build unit

1. Start from an approved plan; do not mix new discovery or requirement-setting into the build.
2. Create an app-code worktree and branch.
3. Implement code and automated non-UI tests with `REQ-###` anchors.
4. Produce the plan's architecture proofs, traces, and measurements.
5. Delete displaced production paths; no compatibility shim remains.
6. Reconcile requirement status/anchors and ROADMAP on the branch.
7. Delete the implemented plan on the branch.
8. Run documentation-authority and architecture-conformance gates.
9. Open a PR and obtain separate-agent code review.
10. Triage review comments, squash-merge, and clean every artifact created by the unit.

Discovery and build never mix. Spike code is throwaway and is never merged. If implementation
contradicts ENGINEERING, stop the build and return to a separately approved discovery unit.

### Architecture change gate

An implementation plan cannot redefine architecture. Changing an `ARC-###` invariant requires:

1. a reproduced counterexample or new approved constraint;
2. fresh evidence and real API probes where applicable;
3. credible options evaluated against architecture drivers and quality scenarios;
4. explicit user approval;
5. an atomic update to ENGINEERING and affected requirements;
6. an executable proof that discriminates the new contract; and
7. deletion of the displaced production path in the same build.

There are no supersession documents, indefinite migrations, or architectural compatibility
layers.

### Closing sequence

For an app-code increment:

1. Rebase onto current `main` if needed.
2. Complete separate-agent review and PR-comment triage.
3. Squash-merge.
4. Remove the branch locally/remotely, worktree, WIP, and stashes created by the unit.
5. Run the stale-work sweep.
6. Run the documentation-authority check.
7. Produce the Definition-of-Done report.

For docs/config only: commit and push directly on `main`, then run stale-work sweep and DoD.

## 4. Traceability and proof

- Each requirement row names current production types/routes and verification.
- Local code comments such as `// REQ-012: ...` and test comments such as
  `// Verifies: REQ-012` are optional cross-references for important or cross-cutting contracts.
- Every `REQ-###` comment that exists in code/tests resolves to a current requirement.
- Every `Done` requirement has automated test evidence or a precise construction/framework proof.
- Every affected `ARC-###` invariant has the proof named in ENGINEERING and the active plan.
- Backward traceability: every `REQ-###` in code/tests exists in REQUIREMENTS.
- Forward traceability: every Done row identifies current production responsibility and at least
  one real verification.

### No manual or UI tests, ever

- Do not add, run, or cite an XCUITest/UI-test target.
- Do not use screen automation as verification.
- Automated verification uses unit or component/integration tests that do not require UI
  automation. Direct construction of AppKit components is allowed.
- “Inherent” applies only when a standard framework supplies the behavior without custom
  interception, or source inspection proves an absence such as no networking.
- **Narrow exception — process-level smoke verification (`ARC-Q12`):** launching the built
  application on a fixture and asserting only on structured diagnostic records it writes is
  permitted. It must not drive, read, or assert on any user interface, must not use screen
  automation or accessibility inspection, and must not be the sole proof of any requirement.
  XCUITest and screen automation remain forbidden.

A green existing suite is not proof of a new claim. Tests must fail for the relevant defective
behavior before the fix or otherwise discriminate the required invariant.

## 5. Git workflow

- Docs-only and project-config changes commit directly to `main`; no branch, worktree, or PR.
- Swift application/test changes use a worktree, branch, PR, and squash merge.
- Branch names: `inc-NN-slug`, `cor-NN-slug`, or `fix-slug`.
- Reconcile specs before opening the PR so code and current truth are reviewed together.
- Never destroy work. Resolve ownership and merged/obsolete status before cleanup.
- Remove local and remote branches, worktrees, stashes, and WIP created by the task after merge.
- Push doc/config commits to `origin/main`.
- Commit trailer:
  `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.

## 6. Code review and PR comments

Every code increment receives a separate-agent review against VISION, ENGINEERING, REQUIREMENTS,
and its approved plan before merge. Spawn the reviewer automatically. Doc-only changes do not
require a separate review.

Before squash merge:

1. Rebase if `main` advanced.
2. Review the last 10 PRs and their comments.
3. For each unclaimed actionable comment:
   - reply `to fix`;
   - design and implement the root-cause correction;
   - keep that correction in one commit; and
   - reply with the fixing commit SHA.
4. Merge only after every comment is resolved.

## 7. Stale-work sweep

Run after the task's own artifacts are gone and immediately before DoD.

Inspect local and remote branches, PRs, stashes, and worktrees:

- leave recent/active recognized work and report it;
- investigate old/unrecognized work;
- integrate valuable work or remove only material proven obsolete;
- never lose work whose provenance is unclear.

Also sweep documentation for obsolete symbols, links, implemented plans, invalidated research,
and claims that conflict with code or current specs.

## 8. User corrections

A user correction is durable:

1. update the authoritative current document or this manual;
2. sweep every affected doc and delete/rewrite stale statements;
3. update requirements and executable proof where behavior changes;
4. do not retain the displaced rule as an active document; and
5. confirm propagation in the DoD.

## 9. Definition of Done

Report ✅, ❌, or ➖ for:

- Docs reconciled: VISION / ENGINEERING / REQUIREMENTS / ROADMAP / research / plans
- Documentation-authority check passed
- Traceability intact: REQ anchors and affected ARC proofs
- Git workflow followed
- Branches, stashes, and worktrees cleaned locally/remotely
- Separate-agent code review completed (code only)
- Last-10-PR comment triage completed (code only)
- Stale-work and stale-document sweep completed
- CLAUDE.md/AGENTS.md self-check completed
- Informed consent honored
- User corrections propagated to durable current docs
- Code-smell/quality analysis reported

Any ❌ means the task is not complete and must be explained plainly.
