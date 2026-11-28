# CLAUDE.md

How to work in this repository. `AGENTS.md` is a symlink to this file. The `§` marks on some
headings are stable: code, tests and docs cite them.

## What this is (§1)

A native macOS Markdown editor: pure Swift 6, SwiftUI-first with narrow AppKit adapters,
local-first, no accounts, no lock-in, ordinary Markdown files. It ships as an ad hoc signed app,
published on GitHub Releases as a disk image and a Sparkle update feed, and updates itself with
Sparkle; that update check is its only network access (REQ-030, REQ-033). Built with Xcode 27 for
macOS 27 only.

## Working style

- When it is clear what is wanted, do it. Ask only for what only the user can do, or for a real
  product choice nobody has made yet.
- Don't end a turn with a summary announcing the next step, an offer to continue, or a list of
  decisions that block nothing: take the next step.
- Stop only when nothing can move forward without the user, or when what blocks you is
  deliberately protected (a permission, a ruleset, a secret). Then say exactly what is needed.
- Still confirm destructive or irreversible actions outside the normal flow (deleting data,
  rewriting history, changing settings); the normal flow (branch, commit, PR, merge, release) is
  not one of them.

## Product invariants

- Documents are ordinary UTF-8 Markdown files; formal GFM is the only generated dialect, and bytes
  the person did not edit are never changed (REQ-007; `docs/architecture.md` §1). The app is an
  editor, not a renderer. ([ADR 0002](docs/adr/0002-the-spec-corpus-excludes-the-specifications-expected-html.md))
- Local-first: the only network access is the Sparkle update check, bounded to the one file that
  imports Sparkle. ([ADR 0010](docs/adr/0010-cloud-first-development-ci-is-the-mac-sparkle-is-the.md))
- macOS 27 only. ([ADR 0005](docs/adr/0005-the-deployment-target-is-the-current-macos-and-only-it.md))
- Releases are signed ad hoc; there is no Apple Developer account and no notarization.
  ([ADR 0015](docs/adr/0015-no-apple-developer-account-releases-are-ad-hoc-for-good.md))
- The update key is derived from one seed and is never changed: changing it strands every
  installed copy. ([ADR 0011](docs/adr/0011-no-mac-not-even-once-the-update-key-comes-from-a-secret-and.md))
- No release is published until its exact signed bundle has launched and passed the smoke
  assertions. ([ADR 0012](docs/adr/0012-an-ad-hoc-app-needs-the-library-validation-exception-and-a.md),
  [ADR 0014](docs/adr/0014-a-release-launches-its-bundle-twice-the-first-launch-s-stall.md))
- Saves never block typing: they write in the background from bytes taken as the save begins,
  and the document's state stays the main actor's. ([ADR 0023](docs/adr/0023-saves-write-in-the-background-from-bytes-taken-as-the-save.md))
- Performance budgets bind on real document shapes; declared stress shapes carry recorded bounds.
  ([ADR 0006](docs/adr/0006-the-interactive-budget-binds-on-real-document-shapes-not-on.md))
- A document window's content stays SwiftUI. ([ADR 0029](docs/adr/0029-a-document-window-s-content-stays-swiftui.md))

## Engineering philosophy

- No compatibility shims. When a structure is wrong, replace it and migrate its callers in the
  same change.
- The smallest correct design. Simplicity first; measure before optimizing, never optimize on a
  hunch.
- One owner per fact, per mutation and per side effect. Two places that know the same thing will
  disagree.
- Abstractions only at real boundaries (a process, a network, a storage format, a platform), not
  in anticipation.
- Don't guess and don't fabricate: an unknown API, path, value or result is looked up, measured or
  reported as unknown.
- You own the repository. Nothing is "pre-existing" or someone else's problem, and red CI is never
  waived: it is fixed first.
- Comments and docs describe current behavior and why it is that way, never its history.
- Code and tests are canonical; the docs describe current intent.
- One gate. Before adding a gate, ask what someone will write to satisfy it cheaply, and whether
  that is worse than the defect. ([ADR 0001](docs/adr/0001-the-verification-apparatus-was-removed.md))

### §6 Architecture changes

An implementation plan cannot redefine architecture. Changing an `ARC-###` invariant needs a
reproduced counterexample or a new constraint, real API evidence where behavior is not documented,
an ADR written by the §7 method, an atomic update to `docs/architecture.md` and the affected
requirements, a test that discriminates the new contract, and deletion of the displaced path in
the same change. No supersession documents, no indefinite migrations, no compatibility layers.

### §7 Deciding

Decide, do not ask. When a decision arises — including one that changes the product, changes the
architecture, or widens the scope — work it out and make it:

1. **State the criteria** the decision turns on, derived from `docs/vision.md`'s objective
   ordering and evaluation section rather than invented for the occasion.
2. **List the real alternatives**, including the one you expect to reject and "do nothing".
3. **Rank them against the criteria**, explicitly, including where the ranking is close.
4. **Choose**, and record the choice as an ADR in `docs/adr/` (`docs/adr/0000-template.md`), with
   the reasoning — especially any respect in which the chosen option is worse than a rejected one.

A decision that turns out badly is recoverable; the ADRs say what was believed at the time.
Stopping to ask stalls the work and pushes judgement onto someone who asked for the work so they
would not have to make it. A correction from the user is durable: update this file or the
authoritative doc in the same change, and sweep the docs it contradicts.

## Engineering practices

- Test first. A change in behavior starts with a test that fails without it.
- Every bug, CI failure and review finding gets a regression test, seen failing before the fix;
  quote its red output in the PR.
- The instrumentation flywheel, every increment:
  - Never guess a bug's cause. If the logs and metrics can't explain it, add the instrumentation
    first, so this occurrence or the next one is diagnosable, then fix.
  - Never guess at performance: measure, keep a baseline, optimize, and report before and after.
  - Even when nothing is blocked, review the instrumentation on every path you touched: add what
    was missing, remove what is noise.
- Tests are hermetic: temporary directories and fixtures, never the developer's real data, config
  or accounts.
- Tests carry `// Validates: REQ-###` for the requirements they prove and `// Verifies: ARC-###`
  for architecture invariants. Swift Testing (`@Test`) throughout; tests construct AppKit
  components directly, never drive the UI (§4).
- Stage files by name, never `git add -A`. Never stash: set work aside with a commit on the branch.

### §3 Honesty

These rules cost nothing and are the reason the test suite is trustworthy.

- **Never mark work delivered that you have not observed pass.** Report the gate output, not the
  intention. If tests fail, say so and paste it. If you skipped something, say that.
- **A green existing suite is not proof of a new claim.** A new test must fail for the defect it
  is about. Before you trust a test, know the answer to: *what change to production code makes
  this go red?* If the answer is "none", it proves nothing — delete it or fix it.
- **Test behavior, not source text.** Assert on what the code does, not on what it contains.
  Grepping source is legitimate only to prove an *absence* (no networking, no UI-test target),
  and such a check should verify its own detector works.
- **A capability needs a proof that it works**, not only proofs that it refuses when it should.
  REQ-058 was satisfied for months by a build in which four formatting commands reported
  `enabled` and silently refused, because every cited proof asserted availability or refusal.
- **A filtered test run that matches nothing reports success.**
  `xcodebuild test -only-testing:"Target/SuiteName/functionName"` silently selects zero tests for
  a Swift Testing `@Test` function and then prints `** TEST SUCCEEDED **`. A falsification run
  that "passes" after a mutation is therefore ambiguous: either the test does not discriminate, or
  it never ran. Filter to the **suite**, and confirm individual `Test case … passed/failed` lines
  appear before believing either outcome.
- **Where a set is closed** (`EditorCommand.allCases`, `EditorTraceEvent`), prefer a test that
  iterates it, so a new member fails the build until its behavior is declared. A hand-written
  list of examples omits the case nobody thought of.
- **Every recorded measurement carries a bound.** `WorkLedger.mainThreadBlockedNanos` was
  computed, serialized and written to every run log for months, and compared against nothing. An
  unbounded measurement is the *appearance* of evidence, which is worse than none, because it
  makes the area look examined. If a number is worth computing at runtime, it is worth a
  threshold; if no threshold can be named, do not compute it.
- **A proof is cheaper than the thing it proves.** `ProjectionOracle.validate` cost 3.5× the cmark
  parse it validated, on the main actor, on every formatting command. When a check is
  asymptotically more expensive than its subject, suspect the check of being badly posed before
  concluding that correctness is expensive. The repair was a *stronger* proof that cost 1% as much.
- **A measurement describes only the input it was measured on.** REQ-090 promised a p95 under
  8 ms and was satisfied by a corpus of one repeated word — 100,000 characters containing no
  heading, list, or table. The number was real and described a document nobody has.
- **Rendered geometry is proved by forcing layout**, not by reading `NSParagraphStyle` fields.
  Constructing AppKit objects directly and asserting on `NSLayoutManager` line-fragment rects is
  a component test, not a UI test.

### §4 No UI tests

No XCUITest target, no UI-driving test, no accessibility-inspection assertions. Automated
verification, the gate and every requirement's proof, is unit and component tests; constructing
AppKit components directly is fine. Three passive exceptions, and one instrument that drives:

- `Scripts/smoke-test.sh` launches the built app on a fixture and asserts only on the structured
  diagnostic records it writes. It never drives or reads the UI.
- `Scripts/smoke-screenshot.sh` captures one screenshot of the app's own window (never the full
  screen) over a rich fixture. Run it when you have changed anything visual, look at the result,
  and send it to the user. It is evidence for human eyes, never a requirement's proof. CI's macOS
  job runs it too and uploads the PNG as the run's `screenshot-<run id>` artifact, which is how a
  cloud session looks.
- `Scripts/screenshots.sh` does the same capture once per screen and commits the results to
  `docs/screenshots/`. A session on a Mac runs it when it has changed how the product looks, or
  when the user asks for screenshots; a cloud session leaves the gallery as it is. A screen an
  ordinary launch does not reach is *named at launch* (`MARKDOWN_EDITOR_SMOKE_SCENE`) and
  presented by the app through its own command routes — never by clicking. Each image is
  committed only if that run's structured log passes.
  ([ADR 0008](docs/adr/0008-the-product-is-photographed-by-naming-a-screen-at-launch-not.md))
- `.github/workflows/agent-drive.yml` is an agent's hands and eyes. It runs a scenario of real
  clicks, keys, menu choices and accessibility presses (`Scripts/agent-drive.swift`) against the
  app on a GitHub Mac runner, and uploads a screenshot, tree or value after each step. Use it to
  try a change the way a person would, then look at every image. It runs the whole tour weekly.
  It is never a gate and never a proof: a defect it finds is fixed with a unit or component test
  that fails for it. ([ADR 0017](docs/adr/0017-an-agent-drives-the-app-on-a-mac-runner-to-look-tests-still.md))

## Commands

```bash
script/verify                 # everything CI checks: process-check, then Scripts/check.sh
Scripts/check.sh              # the gate: build, test, smoke (PASS 0 / FAILED 1 / INCOMPLETE 3)
Scripts/check.sh --no-smoke   # build and test only
xcodebuild test -project "Markdown Editor.xcodeproj" -scheme "Markdown Editor" \
  -destination 'platform=macOS' -only-testing:"Markdown EditorTests/<SuiteName>"   # one suite
Scripts/smoke-screenshot.sh   # one window screenshot after a visual change
npx --yes markdownlint-cli2@0.24.2  # lints CLAUDE.md, README.md and docs/ (check.sh runs it)
script/process-check          # requirements, Validates tags and doc links agree
script/stage start | pre-merge <PR> | post-merge <PR>
```

There is no Swift formatter; follow the surrounding code. Filter a single test run to a suite,
never to a function (§3).

### §2 The loop

`Scripts/check.sh` builds, tests and smokes. That is the gate.

- **On a Mac with Xcode 27**, it runs everything and ends `check: PASS` (exit 0) or
  `check: FAILED` (exit 1).
- **Without Xcode**, it runs the portable steps (release-script tests, verifier fixtures,
  markdownlint) and ends `check: INCOMPLETE` (exit 3). That is not a pass: the build, the tests and
  the smoke run are then CI's job `Build, test and smoke (Xcode 27)`, on the pull request's last
  commit.
- **Five minutes per commit**, local and CI together, from the moment a commit is ready to the
  moment `CI gate` reports. `check.sh` prints its `duration:`, and CI keeps the compilation cache
  between runs (`Scripts/lib/build-settings.sh`). A run over budget is a defect to fix, not a
  number to note.
- A documentation-only diff (the paths in `ci.yml`'s `changes` job) skips the macOS job, which
  builds nothing such a diff could change.

## Environments

Everything in this file applies to both. The SessionStart hook (`Scripts/cloud-setup.sh`) says
which one a session is in. Details are in `docs/development.md`.

- **Cloud session: the default, and CI is the verification.** `CLAUDE_CODE_REMOTE=true`, an
  Ubuntu VM with no macOS or Xcode, reclaimed when idle.
  - Edit, run `script/verify` (its portable steps), commit, and push early: an unpushed commit
    dies with the VM.
  - GitHub's macOS runner builds, tests and smokes the pushed branch. That run is the change's
    verification; its window screenshot is the run's `screenshot-<run id>` artifact.
  - Read CI with GitHub's tools (runs, jobs, logs, artifacts). The cloud proxy refuses GraphQL,
    tag pushes and release writes; releases happen in workflows.
- **Local session: any Mac with Xcode 27, optional.** It may also build, test, run the visual and
  end-to-end checks (`Scripts/smoke-screenshot.sh`, `Scripts/screenshots.sh`) and inspect the
  installed app read-only.
  - `Scripts/check.sh` runs the full gate natively, so there is no wait for CI before pushing;
    CI repeats it.
  - Work in a worktree or branch, never on the main checkout's `main`.
  - Never install a build over `/Applications`. The installed app is always one CI published,
    which Sparkle keeps current.
  - Live checks on real documents or accounts only when the person running the session asks.

Nothing waits for a local session, and nothing needs a particular Mac: not development, not
releases, not setup. Signing is ad hoc, and the update key's seed is fetched by the release job
from Azure Key Vault through GitHub's OIDC token; there is no GitHub secret and no signing
identity. The project names no Apple team: `DEVELOPMENT_TEAM` reads
`$(MARKDOWN_EDITOR_DEVELOPMENT_TEAM)` from the environment, and every script signs ad hoc. A script
or procedure that needs a Mac is a defect.

## Where docs live (§5)

- `docs/index.md` maps every doc. Requirements live in `docs/requirements.md`: stable IDs, one
  EARS sentence each, current behavior only, each `[verified]` by a test tagged
  `Validates: <ID>` or `unverified: <why>`. Future work lives in GitHub issues, not in docs.
- `docs/architecture.md` says how the code is built and why, with its `ARC-###` invariants;
  `docs/adr/NNNN-title.md` records each decision (superseded, never deleted); `docs/lessons.md`
  holds rules learned and open problems, and is pruned when they are resolved.
- `docs/vision.md` is product direction and its objective ordering; `docs/roadmap.md` the delivery
  history; `docs/development.md` environments, CI, releases and setup; `docs/research/` dated
  evidence (`YYYY-MM-DD-topic.md`), never architecture authority.
- Update the docs and this file in the same PR as the code they describe. Rewrite or delete stale
  text in the change that makes it stale; no "superseded" banners in living docs.

## Increment lifecycle

1. **Start**: `script/stage start`. Anything red on main or in the last scheduled run, and any
   unanswered review comment on recent PRs, is fixed before new work. Read the open issues.
2. **Ready**: write the Definition of Ready in the PR body: the problem, requirement IDs or
   issue, acceptance criteria, what is out of scope.
3. **Test first**, then implement with the instrumentation flywheel.
4. **Verify** with the one verify command; it must be green before pushing.
5. **Docs** (requirements, architecture, ADRs, lessons, this file) in the same PR.
6. **Land**: PR, wait for `CI gate`, squash-merge, which releases (see Git, CI and PRs).
7. **Report**: after the merge, one PR comment with the Definition of Done checklist and the final
   increment report (below).

A plan that spans several increments lives in a GitHub tracking issue with a checklist, never in
a file (`docs/development.md`, "Planning an increment"). Never committed: per-PR report or
readiness files, session state or resume files, ledgers of merged PRs. That information belongs
in the PR and its comments.

## Git, CI and PRs

- One branch per increment, cut from a fresh `origin/main`, named `feat/`, `fix/`, `docs/`,
  `chore/`, `refactor/` or `perf/` plus a short topic. Never reuse a branch after its PR merged;
  never name a branch for the tool that wrote it.
- Every change lands through a PR whose body fills `.github/pull_request_template.md`. CI checks
  the body, and that a PR titled `fix...` changes a test.
- A pull request's branch is never replaced: fixes, review changes and catching up with `main` go
  on as new commits (`git fetch origin main && git merge origin/main`). Never rebase a pushed
  branch, force-push, or close a pull request to redo it elsewhere.
- `CI gate` is the one required check: a job that needs every other job. Wait for it
  (`script/stage pre-merge <PR>`), and fix every failure; never bypass it.
- Squash-merge as soon as `CI gate` is green, without asking: in a cloud session with
  `gh api -X PUT repos/<owner>/<repo>/pulls/<N>/merge -f merge_method=squash -f sha=<head sha>`
  (`script/stage post-merge <PR>` does this); locally with `gh pr merge --auto --squash`.
- Merging to main releases; nobody tags or publishes by hand.
- The cloud sessions' GitHub proxy refuses tag pushes, branch deletion and GraphQL: use the REST
  API (`gh api`), and leave branch deletion to GitHub's delete-on-merge and the branch-cleanup
  workflow.
- Commit messages: an imperative subject saying what changed; the body says why.
- End each turn with finished work merged and unfinished work pushed to its branch.

**Release.** `.github/workflows/release.yml` runs after CI passes on a push to `main` (never for
pull requests or the weekly run). When the app changed since the newest release, it builds
Release, signs it ad hoc, launches the exact bundle twice, and publishes `v<x.y.z>`: the disk
image, the Sparkle archive and `appcast.xml`. Installed copies update within the hour.

- Never write a version number by hand. The patch is the next one after the published releases;
  a new series starts with a commit that changes `MARKETING_VERSION`; `CFBundleVersion` is the
  commit count (`Scripts/release-version.sh`).
- The `release` environment deploys only from `main` and holds the Key Vault variables.
- Watch the `Release` run until it ends, and report its outcome.

**CI.** `ci.yml` runs on pull requests (including description edits), pushes to `main`, weekly on
`main`, and by hand. `agent-drive.yml` runs the whole tour weekly and `repeat-smoke.yml` repeats
the Release smoke launch weekly; neither gates anything, and a red weekly run is fixed first like
any red CI.

## Privacy review

Before every commit, read your own staged diff (`git diff --cached`) and remove anything private
about the maintainer, their family or their computers: people's names, addresses, personal email
addresses and accounts, hostnames, home-directory paths, IP addresses, tenant, client or vault
IDs, real personal documents or photos. Use neutral stand-ins in tests and examples. There is no
list of private terms to check against: judge the diff.

## Definition of Done

An increment is done when every line holds; the final report marks each ✅ or ❌ with evidence:

- [ ] Start stage clean: main CI, the last scheduled run and recent review comments were green or
      fixed first.
- [ ] Tests first; the regression test's red output before the fix is quoted.
- [ ] The verify command is green, and CI is green on the final commit. In a cloud session that
      is CI's `Build, test and smoke (Xcode 27)` job on the final commit, quoted, plus the local
      `INCOMPLETE` line; never call a change verified on `INCOMPLETE` alone.
- [ ] Traceability and doc checks (`script/process-check`, `script/pr-check`) are green.
- [ ] Docs and CLAUDE.md are updated in the same PR.
- [ ] Instrumentation reviewed on touched paths: what was added, what removed, or why it is
      adequate.
- [ ] Privacy review done on every commit's staged diff.
- [ ] Every review thread is answered or resolved.
- [ ] Merged; main CI green; the release it produced is linked.
- [ ] Clean up: only main and open PRs' branches remain on the remote; the working tree is clean;
      worktrees and stashes you created are gone.

### Final increment report

One PR comment after the merge, with these parts:

1. **Done / not done**: what the increment delivered, and anything left out.
2. **Definition of Ready**: as written, and whether it held.
3. **Requirements, ADRs and docs**: IDs added, changed or retired; ADRs; docs touched.
4. **Design decisions**: each with the alternatives considered and why they lost.
5. **Verification evidence**: commands, CI run links and durations, release link.
6. **Regression test**: name and red output before the fix (or "no bug fixed").
7. **Diagnosis**: for a bug, the root cause and how it was established.
8. **Instrumentation**: added, removed, and gaps still open.
9. **Performance**: before and after numbers, or "not touched".
10. **Privacy review**: done on every commit; anything removed.
11. **Smells**: what looked wrong but was out of scope.
12. **Follow-ups**: each filed as an issue, linked.
13. **Definition of Done**: the checklist above, each line ✅ or ❌ with evidence.
