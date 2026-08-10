# COR-57 — Enforcement floor

- **Status:** Approved; not implemented
- **Requirements:** REQ-133, REQ-134 (both new, `Planned`)
- **ARC invariants:** ARC-027 (new; established here in its weakest form and strengthened by COR-58..COR-61)

## Context

Every defect found on 2026-08-10 was detectable by four minutes of `Scripts/fast-check.sh`. None of
them was detected, because **nothing forces a run and nothing forces a pull request.** The repository
has no `.github/` directory, no CI, and no git hooks — `.git/hooks/` contains only samples. `CLAUDE.md`
§5 has required a worktree, branch, PR and squash merge for Swift changes since the repository was
created; that requirement has been held up by intent alone, and on 2026-08-10 intent did not hold for
twelve consecutive commits.

Server-side enforcement is unavailable: the repository is private on a free plan, and
`gh api repos/:owner/:repo/branches/main/protection` returns
`403 Upgrade to GitHub Pro or make this repository public`. GitHub Actions is available on private
free repositories, but macOS runners bill at a 10× minute multiplier and this build requires Xcode,
so a per-PR Xcode build would consume the included allowance quickly.

The user's decision, recorded 2026-08-10, is a **local pre-push hook**, with the server-side choice
left open rather than resolved. This plan states the weakness plainly rather than implying the hook
is equivalent to branch protection: it is bypassable with `git push --no-verify` and it must be
enabled per clone. It is chosen because it costs nothing, works today, and would have refused all
twelve of the commits it exists to prevent.

## Architecture impact

New invariant `ARC-027`: *every proof obligation is discharged by an observed execution artefact,
never by a property of source text.* This increment establishes only its procedural half — that the
artefact is produced at all, before code reaches the default branch. COR-58..COR-61 make the
artefact authoritative for each class of claim.

## Production changes

No application code. All changes are under `Scripts/`.

### 1. `Scripts/hooks/pre-push` — new, tracked

Version the hooks rather than copying them into `.git/hooks/`, which is not tracked and drifts
per clone. `git config core.hooksPath Scripts/hooks` points git at the tracked directory directly,
so a hook fix propagates with a pull instead of requiring a reinstall.

The hook reads its `<local-ref> <local-sha> <remote-ref> <remote-sha>` lines from stdin as git
supplies them, and delegates every decision to `Scripts/check-push-policy.sh` so the policy is
testable without performing a push.

### 2. `Scripts/check-push-policy.sh` — new

```
check-push-policy.sh --remote-ref <ref> --range <base>..<head>
```

Two rules, in order:

1. **REQ-133 — branch rule.** If `<ref>` is `refs/heads/main` and any commit in the range modifies a
   path under `Markdown Editor/` or `Markdown EditorTests/`, fail with the §5 citation and the
   offending commits. Docs-only and project-config pushes to `main` are permitted, as §5 allows.
2. **REQ-134 — gate rule.** Require a gate receipt (§3) whose recorded head SHA equals `<head>` and
   whose result is `pass`. A missing, stale, or failing receipt fails the push.

Fails closed on every ambiguity — unreadable receipt, unparseable range, absent tooling — for the
same reason `check-proof-results.sh` does: a check that silently matches nothing is the defect
wearing a new hat.

### 3. Gate receipts — new, in `Scripts/fast-check.sh` and the full-run path

On completion, the gate scripts write `.gate-receipt.json` (gitignored):

```json
{ "head": "<sha>", "ran": "<iso-8601>", "scope": "fast|full", "result": "pass|fail",
  "gates": { "documentation-authority": "pass", "instrumentation-coverage": "pass",
             "tests": "pass", "proof-results": "pass" } }
```

The receipt records the SHA the gates actually ran against, so amending or rebasing after a green
run invalidates it. `scope: fast` satisfies REQ-134 for a topic-branch push; a push to `main`
requires `scope: full`.

### 4. `Scripts/install-hooks.sh` — new

Sets `core.hooksPath`, verifies the hook is executable, and prints what is now enforced and what is
not. Idempotent. `README` guidance points every new clone at it.

## Phases

1. `check-push-policy.sh` with its fixture tests (§ proof), no hook yet.
2. Receipt emission in `fast-check.sh` and the full-run path.
3. The hook and installer; enable locally; confirm a deliberate direct-to-`main` Swift push is refused.
4. Record in ROADMAP the still-open server-side decision.

## Automated proof

Shell-fixture tests in the style of `Scripts/test-verify-smoke-log.sh`, run by `fast-check.sh`:

`Scripts/test-check-push-policy.sh` constructs throwaway repositories in a temporary directory and
asserts:

- a Swift-modifying range pushed to `refs/heads/main` is **refused** (REQ-133);
- a docs-only range pushed to `refs/heads/main` is **allowed** (REQ-133, liveness — the rule must
  permit the workflow §5 explicitly allows, not merely refuse things);
- a Swift-modifying range pushed to `refs/heads/cor-99-x` is **allowed** (REQ-133 liveness);
- a receipt whose `head` differs from the pushed head is **refused** (REQ-134);
- a receipt with `result: fail` is **refused** (REQ-134);
- an absent receipt is **refused** (REQ-134);
- a matching `scope: full` receipt with `result: pass` is **allowed** (REQ-134 liveness).

Rehearse the gate failing before trusting it, per `CLAUDE.md` §9: run the suite against the twelve
commits of 2026-08-10 (`b241f9d..64cadae`) and confirm the policy refuses each Swift-bearing push.
That rehearsal is the evidence this increment closes the hole it was written for, and it belongs in
the PR description.

## Instrumentation and performance evidence

None. No application code changes; no trace vocabulary changes.

## Failure and rollback

The hook is advisory infrastructure: if it misfires it blocks a legitimate push, which is visible and
immediately correctable with `--no-verify`. There is no runtime risk to the application. Rollback is
`git config --unset core.hooksPath`.

Stated weakness, to be recorded in ROADMAP rather than glossed: `--no-verify` bypasses the hook, and
a fresh clone is unprotected until `install-hooks.sh` runs. This is enforcement by default, not
enforcement by construction. Only branch protection is the latter, and it is unavailable on the
current plan.

## Deletion and conformance gate

- No enforcement logic lives in `.git/hooks/`; `core.hooksPath` points at the tracked directory.
- `Scripts/check-push-policy.sh` is the single owner of push policy: no branch or receipt rule is
  duplicated inside `pre-push`, which only marshals stdin and exits on the delegate's status.
- `fast-check.sh` emits exactly one receipt per run and no other script writes one.
