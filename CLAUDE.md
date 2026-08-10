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
| --- | --- |
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
  coexist. **Deletion is a consequence of delivery, never evidence of it.** A plan's absence proves
  nothing about whether anything was built; only its requirements being `Done` on proofs observed
  passing does. On 2026-08-10 ten increments were marked delivered by reading the arrow backwards —
  ten commits containing one comment line each deleted their plans, and a reconcile commit inferred
  delivery from the missing files. Restoring a plan from Git is the correct response to discovering
  it was deleted without being built.
- Research may remain when facts are still valid, useful, and expensive to reproduce. Each
  research file states evidence-only authority, first-researched/last-verified dates, environment,
  reproducible method, and refresh triggers.
- Refresh or delete research when a dependency, SDK, requirement, or architectural assumption
  invalidates material findings.
- Historical rationale, completed plans, and displaced architecture remain available through Git.
- Run `Scripts/check-documentation-authority.sh` before every commit.
- Run `Scripts/check-instrumentation-coverage.sh` before every commit that touches
  `EditorTraceEvent`: every case must have a real production call site outside
  `EditorTrace.swift`/`JSONLinesEditorTrace.swift`, or it is deleted in the same change.

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
8. Run documentation-authority, instrumentation-coverage, and architecture-conformance gates.
9. Open a PR and obtain separate-agent code review.
10. Triage review comments, squash-merge, and clean every artifact created by the unit.

Discovery and build never mix. Spike code is throwaway and is never merged. If implementation
contradicts ENGINEERING, stop the build and return to a separately approved discovery unit.

### Embedded discovery

A build unit may open with a **Stage 0 POC** when the approved plan states, *before execution*: the
exact probes, a decision table mapping every plausible outcome to a branch, and the full content of
every branch. The unit then runs without stopping to ask: it executes the probes, applies the
decision table mechanically, writes the findings to `docs/research/`, deletes the POC code, rewrites
the plan's remaining stages (and any downstream plan the outcome changes) in place, commits that
rewrite on the branch before any production code, and continues.

The rule being preserved is *no unresearched decision reaches production*, not *research and building
happen in different weeks*. Two constraints keep it honest:

- A plan whose decision table does not cover an observed outcome **fails the increment** and returns
  to a separate discovery unit. Every such plan must therefore contain an explicit "no branch
  applies" row, and taking it is a success of the process rather than a failure of the increment.
- POC code is still throwaway and is still never merged. Its findings are the deliverable.

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
7. Run `Scripts/smoke-screenshot.sh`, review the resulting screenshot for anything that looks
   wrong, and send it to the user.
8. Produce the Definition-of-Done report.

For docs/config only: commit and push directly on `main`, then run stale-work sweep and DoD.

## 4. Traceability and proof

- Each requirement row names current production types/routes and verification.
- Local production comments such as `// REQ-012: ...` are optional cross-references for important
  or cross-cutting contracts.
- A test comment `// Verifies: REQ-012` is **not** optional: it is how REQ-118 maps a test to what
  it proves. Every test carries one unless a `Done` row cites the test or its suite by name, or it
  is one of the stated exemptions in `Scripts/check-proof-results.sh`. Keeping the mapping beside
  the test rather than in a registry means a new test fails the gate until it names its
  requirement.
- Every `REQ-###` comment that exists in code/tests resolves to a current requirement.
- Every `Done` requirement has automated test evidence or a precise construction/framework proof.
- Every `Done` requirement's cited proof must be **observed to pass** in the run that closes the increment; a suite that does not complete leaves every requirement citing it unproven, not proven. `Scripts/check-proof-results.sh` enforces this and also ensures no test fails unnoticed because nothing cites it (REQ-117/118).
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
- **Narrow exception — process-level screenshot verification (`ARC-Q13`; REQ-104):** at the close
  of every app-code increment, capturing exactly one screenshot of the built application's own
  on-screen window over a rich fixture (`Scripts/smoke-screenshot.sh`) is permitted and required.
  Passive capture only — it must not click, type, or otherwise drive the UI, and must never
  capture the full screen (only the application's own window, so no other on-screen content is
  captured). It is mandatory visual-review evidence for the agent and the user, never the sole or
  a partial substitute for a requirement's `test`/`inherent` proof. XCUITest and screen automation
  remain forbidden.

A green existing suite is not proof of a new claim. Tests must fail for the relevant defective
behavior before the fix or otherwise discriminate the required invariant.

### Liveness, not only safety

A requirement that promises a capability needs a proof that the capability *works*, not only
proofs that it refuses when it should. A refusal-only proof set does not discharge such a
requirement: REQ-058 promised formatting commands in both modes and was satisfied for months by
a build in which four of them reported `enabled` and silently refused, because every cited proof
asserted availability, window scoping, or refusal.

- Every user-invocable action carries at least one automated proof that it succeeds on its
  ordinary input, in every mode it is offered in.
- Where the set of actions is closed (`EditorCommand.allCases`, `EditorTraceEvent`), the proof is
  a structural matrix over that set, so a newly added member fails the build until its behavior
  is declared. A hand-written list of examples silently omits the case nobody thought of.

### A proof's inputs are part of the proof

A measurement is evidence only for the input it was measured on. Any requirement that quantifies over
a class of inputs — "a document", "any command", "every block kind", "either appearance" — is proved
by a **structural enumeration of that class**, not by one representative the author chose.

REQ-090 promised a p95 under 8 ms "on the approved performance corpus" and was satisfied for months
by a corpus of `String(repeating: "word ", count: 20_000)`: 100,000 UTF-16 units containing no
newline, no heading, no list and no table, which cmark parses as a single paragraph and the projection
compiles into one block and one run. The number was real. It described a document nobody has, while a
sibling proof measured the same work on structured text at three times the cost.

This is the same shape as the two rules above, one level further out. Each time, a proof obligation
was discharged by a property of the artifact — a command *reports* enabled, a proof *exists*, a p95
*is measured* — rather than by the behaviour the requirement is about. When a requirement quantifies,
the enumeration is the proof, and adding a member of the class must fail the build until its
behaviour is declared.

### A gate that reads text is satisfied by text

The three rules above each fixed an instance. On 2026-08-10 the same pattern arrived three more
times in one day, and the common mechanism finally became legible: **every gate in this repository
asked a question about source text, and source text is the cheapest thing to produce.** Each gate was
quietly teaching the shape of its own defeat.

- `check-instrumentation-coverage.sh` asked whether a `record` call *appears in source*. It was
  satisfied by `let trace: (any EditorTraceSink)? = nil; trace?.record(...)` — a receiver bound to
  `nil` in the same scope, so the call can never execute — with a comment naming the script it
  existed to satisfy. This was the gate's **second** defeat; the first, in July (PR #20), was a
  same-named unrelated symbol, and it was fixed as an instance rather than as a class.
- `check-documentation-authority.sh` and `check-proof-results.sh` together asked whether a cited
  proof *exists* and *passes*. Both are perfectly satisfied by `#expect(Bool(true))`. Three of six
  proofs cited by new `Done` rows were literal tautologies.
- The increment lifecycle asked whether a plan file was *absent*. It was satisfied by deleting it.

The rule, which supersedes nothing above but sits underneath all of it:

> **A proof obligation is discharged by an observed execution, never by a property of the source
> text.** Coverage means a run emitted the record. Delivery means a requirement is `Done` on proofs
> that executed. Discrimination means a recorded, compiling mutation of production source turns a
> cited proof red.

The last clause is the operative one, because it is the only mechanical difference between a real
proof and a tautology: *under what change to production code does this test fail?* If the answer is
"none", it proves nothing. Every `Done` requirement therefore carries a recorded falsifying mutation
(REQ-138), and a requirement whose proofs cannot be made to fail cannot be `Done`.

When a gate is found defeated, replace the question it asks — do not add a second gate beside it.
Two gates where one is known-defeatable is the "individually sound and jointly blind" shape §6
already records as the cause of COR-25 and four silently refusing commands.

### Proofs must assert the thing the requirement is about

A proof asserting a model value or an attribute value does not discharge a requirement about
what the user sees. Where a requirement is about rendered geometry, the proof forces real layout
on directly constructed AppKit objects and asserts on the result — `NSLayoutManager`
line-fragment rectangles rather than `NSParagraphStyle` fields. REQ-106 was `Done` on a proof
that the rendered *string* differed while a hard break laid out identically to a paragraph
boundary. This is not a licence for UI testing: constructing components directly and forcing
layout remains a component test.

## 5. Git workflow

- Docs-only and project-config changes commit directly to `main`; no branch, worktree, or PR.
- Swift application/test changes use a worktree, branch, PR, and squash merge. **This is enforced,
  not merely expected.** `Scripts/hooks/pre-push` (enabled by `Scripts/install-hooks.sh`, which sets
  `core.hooksPath`) refuses a push that carries Swift changes to `main`, and refuses any push without
  a gate receipt recording a passing run at the pushed head. Run the installer in every clone. On
  2026-08-10, twelve Swift-bearing commits reached `main` with no branch, no PR and no gate run,
  because this rule had only ever been enforced by intent. `--no-verify` still bypasses the hook and
  a fresh clone is unprotected until the installer runs; server-side branch protection needs GitHub
  Pro or a public repository and is an open decision recorded in ROADMAP.
- Never mark work delivered that you have not observed pass. If an increment cannot be completed,
  leave its row ⚪ and its plan in place; a stub commit is not a delivery and must not be committed
  as one.
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

Before every squash merge — not only the first PR of a session, every one:

1. Rebase if `main` advanced.
2. Review the last 10 PRs on GitHub (not just the PR being merged) and their comments.
3. For each unclaimed actionable comment found anywhere in that review:
   - reply to claim it (e.g. `to fix`), so another pass does not duplicate the work;
   - design and implement the root-cause correction — no band-aids;
   - keep that correction in one commit as part of the PR being merged; and
   - reply on that same comment with the fixing commit SHA.
4. Merge only after every comment found in the sweep is resolved.
   When a review identifies a defect *class* rather than a single instance, the increment closes
   the class with a structural gate, or records explicitly why it cannot and what remains open.
   Fixing only the reported instance is not sufficient triage: the COR-23 full-replacement defect
   was correctly diagnosed as "two proof suites individually sound and jointly blind", the
   instance was fixed, no gate was added, and the same blindness produced COR-25 and then four
   more silently refusing commands.
5. After the merge lands on `main`, return to each comment claimed in step 3 and post a
   follow-up reply confirming it is fixed on `main` (name the merge commit). A comment is not
   closed out until this confirmation is posted — the fixing commit alone is not enough, since
   it lived on a branch until the merge.

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
- Every `Done` requirement's cited proof observed passing in this run
- Liveness proofs present for every user-invocable action touched
- Falsifying mutation recorded for every requirement moved to `Done`, and observed turning a cited
  proof red
- Gate scripts rehearsed failing before being trusted — and, where a gate was found defeated,
  rehearsed against the artifact that defeated it
- Every ROADMAP status change derived from requirements, never asserted
- Build actually compiles, tests actually ran: report the gate output, not the intention
- Code-smell/quality analysis reported

Any ❌ means the task is not complete and must be explained plainly.
