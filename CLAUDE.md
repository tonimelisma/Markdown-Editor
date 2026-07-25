# CLAUDE.md — Operating Manual

This file is auto-loaded by Claude Code. It defines **how we work** in this repo.
`docs/VISION.md` defines **what is true** about the product and architecture.
Keep the split clean: *process* lives here, *durable truths* live in VISION.

> **This file is self-maintaining.** Whenever the working process changes — including
> a correction from the user — update this file in the *same* change, and re-verify it
> in the Definition-of-Done report (§9). If a rule here ever stops matching reality, the
> file is stale and must be fixed before the task is "done".

> ## ⛔ PRIME DIRECTIVE — informed consent
>
> **Nothing is written into the specs without the user's explicit, informed approval first.**
> "The specs" = everything under `docs/**` — VISION, REQUIREMENTS, ROADMAP, ADRs, plans, and
> any research doc that asserts a decision.
>
> - The agent **does not invent** requirements, roadmap items, ADRs, invariants, or decisions
>   on the user's behalf. Ever.
> - The order is always: **research → present findings → ask questions → get an explicit yes →
>   only then write.**
> - Approval is **per item and specific**. Answering one question does not authorize the agent
>   to extrapolate a dozen related decisions into the docs.
> - When unsure whether something is approved, **propose it in chat and wait.** Silence is not
>   consent.

---

## 1. What this project is

A native **macOS Markdown editor** — pure Swift, SwiftUI-first (AppKit where SwiftUI
can't reach), local-first, no accounts, no lock-in. Idiomatic, HIG-faithful, "don't make
the user think." Full product & engineering vision: **[docs/VISION.md](docs/VISION.md)**.

---

## 2. Documentation model — spec-driven, conservative authority

**Code + tests are canonical. The docs are the synchronized intent layer.** (We did *not*
adopt the "spec is the sole source of truth" model — see
[ADR-0001](docs/decisions/0001-spec-driven-documentation-conservative-authority.md).)

Doc map (MECE — every doc has one job, no overlap):

| Doc | Job |
|---|---|
| `docs/VISION.md` | Durable product + engineering vision, principles, **invariants**, rules. |
| `docs/REQUIREMENTS.md` | Numbered requirements (`REQ-###`) in EARS, traced to code + tests. The single source of truth for **WHAT**. |
| `docs/ROADMAP.md` | Increments in logical order + status; backlog. Future vs. existing is explicit. |
| `docs/decisions/` | ADRs — one decision per file. **Living, not immutable** (§8). |
| `docs/research/` | Research docs: online research, native-API investigation, spikes/POCs. |
| `docs/plans/` | Per-increment implementation plans, approved before code. |

**Nothing stale.** Every change reconciles *all* affected docs in the same change. The
DoD checklist (§9) enforces it.

**Consent-gated & incremental.** These docs are populated only with the user's approval
(see the Prime Directive). They are created as the project earns them — so not every file
listed above exists at every point in time. An empty or absent doc is normal, not stale.

---

## 3. The increment lifecycle

Each roadmap increment is built the same way (the **full lane**):

1. **Pick** the next increment from `docs/ROADMAP.md`; mark it `Active`.
2. **Research** every unknown → `docs/research/NNNN-*.md`. Online research **and** probe
   the real macOS/Swift APIs, plus spikes/POCs. No plan until unknowns are resolved.
3. **Clarify** — surface open questions (product *and* engineering) to the user and get
   answers before planning.
4. **Specify** — add/update `REQ-###` entries in `docs/REQUIREMENTS.md` (EARS).
5. **Plan** — write `docs/plans/NNNN-*.md`, explain it to the user, get approval **before** code.
6. **Implement** — code + tests, each carrying `REQ-###` anchors (§4).
7. **Reconcile (on the branch, *before* opening the PR)** — update REQUIREMENTS status +
   traceability anchors, mark ROADMAP progress, write/update ADRs for decisions taken, touch
   VISION only if a principle actually changed. The PR carries the code **and** these spec
   updates, so the reviewer can verify traceability from the diff.
8. **Review** — a **separate agent** code-reviews the diff against plan + requirements (§6).
9. **Close** — mark the increment done in ROADMAP; add newly-found work to the backlog.

> **Discovery and build never mix.** Research, spikes, discovery, requirements-setting, and
> planning (steps 2–5) are completed and approved as their **own unit(s) — with no production
> code** — before any implementation. **Spikes are standalone units** (their POC code is
> throwaway, not merged). A **build unit** (step 6) implements an already-approved plan; it
> does not define new requirements or decisions. (Reconciling requirement *status* and
> traceability *after* coding — step 7 — is part of the build unit and is fine; *setting*
> requirements is discovery.)

### Closing sequence — order matters

Run these in order at the *end* of a task, once the work itself is finished:

**Code increment:**
1. **Rebase if needed** — if `main` advanced, rebase the branch onto it so the PR is current.
2. **PR-comment triage (§6a)** — review the last 10 PRs and their comments; claim, properly
   fix, and record the fixing commit for every unaddressed comment.
3. Squash-merge the PR → integrate into `main`.
4. Clean up **your own** artifacts — worktree, branch (local + remote), WIP, stashes.
5. **Stale-work sweep (§7)** — *only now*, after your own artifacts are gone, scan for any
   *other* unrecognized work. This ordering is deliberate: it guarantees what you find is
   never your own leftovers.
6. **DoD report (§9)** — including the code-smell / quality analysis.

**Doc-only or config-only increment:** commit straight to `main` — **no** worktree, PR,
review, or self-cleanup (there's nothing to clean; you never left `main`). Then the
stale-work sweep (§7) and DoD report (§9).

**Fast lane** (typos, one-liners, doc tweaks): skip lifecycle steps 2–5; still keep
traceability honest and still produce a DoD report.

---

## 4. Traceability rules (mechanical, not a promise)

- **Code anchor:** `// REQ-012: autosave 500ms after last keystroke`
- **Test anchor:** `// Verifies: REQ-012`
- Each requirement row in `REQUIREMENTS.md` lists its code + verification anchors.
- **No manual tests, ever.** Verification is **automated** (`test`) or **inherent** (satisfied
  by construction — adopting a standard framework component that provides the behavior, or code
  inspection such as "makes no network calls"). Never mark a requirement verified by hand.
- **No UI tests, ever.** Do not run, add, or rely on the UI-test target; automated verification
  uses unit/integration tests that do not require macOS UI automation.
- **Forward:** every requirement has ≥1 verification (a `test`, or a justified `inherent`).
  **Backward:** every `REQ-###` in code exists in REQUIREMENTS.md. A requirement with no
  verification, or a code anchor with no requirement, is a DoD failure.

---

## 5. Git & change workflow

- **Doc-only and project-config changes → commit straight to `main`.** No branch, no PR.
  *Project-config* = Xcode project files (`project.pbxproj`), build settings, entitlements.
- **App-code changes (Swift sources, logic, tests) → worktree + branch + PR + squash-merge:**
  1. Create a **git worktree** for the change (keeps `main` clean).
  2. Branch name: `inc-NN-slug` (increment) or `fix-slug` (fix).
  3. **Reconcile the specs on the branch *before* opening the PR** — REQUIREMENTS status +
     traceability anchors, ROADMAP, ADRs — so the PR carries code **and** its spec updates.
  4. Open a PR; **squash-merge**.
  5. After merge: delete the branch (**local + remote**), remove the worktree, drop any
     stashes you created. **Leave no trace you created.**
- **Never destroy work:** before deleting/cleaning anything, verify it is yours *and*
  merged or genuinely obsolete.
- Commit trailer: `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.

> A GitHub remote (`origin`, private) is configured. **Doc/config commits** are pushed to
> `origin/main`. **App-code changes** use `gh` for the PR (create + squash-merge), and remote
> branch cleanup (delete the branch on `origin` after merge) applies.

---

## 6. Code review

Every **code** increment is reviewed by a **separate agent** against the plan and the
requirements before merge. **Spawn this review subagent automatically — do not ask the user
first.** The reviewer posts its findings as comments on the PR. Doc-only changes don't require
a separate review pass.

## 6a. PR-comment triage (end of each build increment, before the DoD)

After the separate-agent review has posted its findings, and before squash-merge:

1. **Rebase** the branch onto `main` if `main` has advanced.
2. **Review the last 10 PRs and their comments** (this PR and recent ones) — nothing rots.
3. For every **unclaimed** comment (a finding not yet addressed):
   - **Claim it** by replying `to fix`.
   - **Design a proper, root-cause fix — never a bandaid.**
   - Apply it and commit; keep a comment's fix in **one commit**.
   - After committing, **reply to the comment with the fixing commit SHA**.
4. Squash-merge only once every comment is claimed and fixed.

---

## 7. Stale-work sweep (run right before the DoD — *after* your own cleanup)

**Timing:** this runs at the very end of a task, *after* you've merged your PR into `main`
and removed your own worktree/branch/WIP/stashes (see the closing sequence in §3). Not at
the start of an increment. By running it last, anything you find is genuinely *other* work,
not your own leftovers.

Check **branches, PRs, stashes, worktrees — local and remote** — for anything unrecognized:

- **Recent/active** → leave it, note it in the DoD.
- **Old/forgotten** → investigate. **Ensure no work is ever lost.** Integrate cleanly to
  `main` unless genuinely obsolete; then clean it up. Suggest deeper investigation if the
  provenance is unclear.

---

## 8. On user correction

When the user corrects something, treat it as **durable**, not conversational:

1. Apply the correction where it belongs (VISION / REQUIREMENTS / ADR / this file / …).
2. **Sweep all docs for staleness** related to the correction and fix them comprehensively.
3. If it changes a past decision, **update** the relevant ADR (ADRs are living, not immutable).
4. Confirm in the DoD that the correction is now recorded in durable repo state.

---

## 9. Definition of Done (DoD) — end every task with this

Report a red/green checklist confirming each applicable step was followed (or ❌ + why):

- Docs reconciled (VISION / REQUIREMENTS / ROADMAP / ADRs / research / plans, as affected)
- Traceability intact (REQ anchors ↔ code ↔ tests)
- Git workflow followed (doc/config→`main`, or app-code→worktree/PR/squash)
- Branches / stashes / worktrees cleaned (local + remote)
- Code review done (code changes only) — review subagent spawned automatically
- PR-comment triage done — last 10 PRs' comments reviewed; unclaimed ones claimed, properly fixed, fixing commit noted (code increments)
- Stale-work sweep done + reported
- **CLAUDE.md self-check** — updated if the process changed, still matches reality
- **Informed consent** — everything written to `docs/**` this task was shown to and approved by the user first
- User corrections propagated to durable docs
- **Code-smell / quality scan** — remaining code smells or quality issues analyzed and reported (every DoD)

Use ✅ / ❌ (and ➖ for N/A). If any box is ❌, say so plainly and explain.
