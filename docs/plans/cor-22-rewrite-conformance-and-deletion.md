# COR-22 — Rewrite conformance and deletion sweep

- **Status:** Approved; not implemented
- **Kind:** App-code/docs correction; one worktree, branch, PR, and squash merge
- **Requirements:** REQ-058, REQ-081, REQ-088, REQ-090, REQ-096, REQ-103–112
- **Architecture:** Final proof of ARC-018–024 and ARC-Q05/Q14–Q20; no new architecture
- **Depends on:** COR-18, COR-19, INC-05, COR-20, COR-21, INC-06
- **Must be last:** yes

## Goal

Close the editor foundation rewrite only after the merged implementation has one route per
concern, every corrected/planned requirement has current executable evidence, every displaced
path is deleted, and the final rich screenshot has been reviewed.

This is not a place to implement deferred feature work or relax a failing requirement.

## Files

Inspect all production/test/script/docs files. Expected documentation edits:

- `docs/VISION.md`
- `docs/ENGINEERING.md`
- `docs/REQUIREMENTS.md`
- `docs/ROADMAP.md`
- `docs/research/macos-editor-platform.md`
- `docs/research/native-markdown-typography.md`
- `docs/research/markdown-projection-and-compatibility.md`
- `docs/research/image-portability-and-safety.md`
- `CLAUDE.md` / `AGENTS.md` self-check only; edit solely for an actual user process correction

Delete:

- this plan and every implemented COR-18/COR-19/INC-05/COR-20/COR-21/INC-06 plan;
- obsolete test helpers, fixtures, event cases, comments, files, and compatibility adapters proven
  displaced;
- generated artifacts created by the rewrite.

## Required conformance inventory

Build a temporary review checklist in the PR description, not a retained repository document,
mapping each item to code and proof:

1. Canonical document/source/undo owner.
2. Window/session ownership and detach.
3. Semantic presentation and typography tokens.
4. Soft/hard/paragraph semantics.
5. Incremental attributed patch route.
6. Full-replacement allowlist.
7. Parser scheduler and cmark critical section.
8. Image encoded/decode/cache bounds.
9. Canonical asset references.
10. Command/menu/toolbar/sheet route.
11. Diagnostic sink, watchdog, sampler, and shutdown.
12. Debug/Release performance evidence.
13. Process smoke and screenshot evidence.

## Implementation

1. Rebase onto current `main`.
2. Run the full Debug and Release suites before changing anything. Treat failures as rewrite
   defects unless comparison with the pre-rewrite base proves an unrelated baseline issue.
3. Search for every displaced symbol named in the six implementing plans.
4. Search for duplicate ownership/routes:
   - attributed builders/storage mutation;
   - parser demand;
   - raw Markdown asset scanning;
   - sampler registries/timers;
   - watchdog write routes;
   - semantic command execution;
   - toolbars/link dialogs;
   - typography numeric constants.
5. Delete confirmed remnants and update tests to assert the single remaining API boundary.
6. Audit every `EditorTraceEvent`:
   - real reachable production call;
   - accurate name/category/level/payload key;
   - no private content;
   - no duplicate event for the same transition.
7. Audit every `Done`, `Correction`, and `Planned` requirement.
   - `Done` only with current production owner and discriminating proof.
   - No rewrite row remains `Correction` or `Planned` if the program is declared complete.
   - If any remains incomplete, ROADMAP stays Active and this plan cannot close.
8. Reconcile ENGINEERING to code and remove temporary transition wording.
9. Refresh research last-verified dates only for evidence actually rerun.
10. Delete all implemented plan files in the branch.

## Required full proof

### Builds/tests

- Full Debug application and non-UI tests.
- Full Release application and non-UI tests with `ENABLE_TESTABILITY=YES`.
- Swift 6 complete concurrency: zero warnings.
- Formal GFM and pathological parser suites.
- Complete projection oracle and semantic edit suites.
- Typography semantic/attribute/geometry/appearance/accessibility suites.
- Incremental-storage and rapid-input suites.
- Diagnostic lifetime/watchdog/shutdown suites.
- Scheduler/resource/reference suites.
- Native command/window-isolation suites.

### Release performance

Retain exact output in the PR:

- complete native-input callback at 100k: p95 <8 ms;
- complete mode transition: p95 <16 ms;
- parse/index/semantic projection at 100k: p95 <100 ms;
- nonzero warmup/sample counts;
- zero failures/dropped accepted inputs/stale applications;
- non-gating 1M characterization.

### Gates and smoke

- `Scripts/check-documentation-authority.sh`
- `Scripts/check-instrumentation-coverage.sh`
- any architecture/source-conformance scripts added by implementing increments
- `Scripts/test-verify-smoke-log.sh`
- `Scripts/smoke-test.sh`
- `Scripts/smoke-screenshot.sh`
- lowered-threshold smoke rehearsal fails
- exact one window-only screenshot reviewed for:
  - paragraph and heading rhythm;
  - soft/hard breaks;
  - reading measure/insets;
  - list nesting/task alignment;
  - quote/code/table/separator/image/raw-HTML treatment;
  - unclipped native toolbar;
  - status chrome and Light/Dark adaptation visible in the selected run

## PR and repository closure

1. Obtain separate-agent whole-program review against VISION, ENGINEERING, REQUIREMENTS, ROADMAP,
   research, and every affected invariant.
2. Before merge, inspect the last 10 PRs and claim/fix every unclaimed actionable comment
   according to `CLAUDE.md`.
3. Squash merge.
4. Post merge-commit confirmation to every claimed review thread.
5. Remove branch locally/remotely, worktree, WIP, and stashes created by the increment.
6. Sweep all branches, PRs, stashes, worktrees, docs, symbols, links, and research for stale work.
7. Run documentation authority again on clean `main`.

## Failure and rollback

- Any failed invariant keeps the relevant requirement in `Correction`/`Planned`, ROADMAP Active,
  and this plan present.
- Do not mark the program complete because only Debug or only the screenshot looks correct.
- Do not weaken thresholds, delete failing fixtures, or retain old routes as fallbacks.
- Separate genuinely unrelated baseline failures into their own scoped work only after proving
  them against the pre-rewrite base.

## Completion gate

The rewrite is complete only when every item above is green, the final screenshot has been sent to
the user, all implemented plans including this one are deleted, and the Definition-of-Done report
contains no unexplained ❌.
