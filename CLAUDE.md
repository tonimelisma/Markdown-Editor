# CLAUDE.md — Operating Manual

How to work in this repository. `AGENTS.md` is a symlink to this file.

Product direction is in `docs/VISION.md`, architecture in `docs/ENGINEERING.md`, behavior in
`docs/REQUIREMENTS.md`, sequence in `docs/ROADMAP.md`, decisions in `docs/DECISIONS.md` (read
"Why the gates were removed" before adding a gate), and environments, CI, releases and the
owner's setup in `docs/DEVELOPMENT.md`.

## 1. Product

A native macOS Markdown editor: pure Swift, SwiftUI-first with narrow AppKit adapters,
local-first, no accounts, no lock-in, ordinary Markdown files. It updates itself with Sparkle
from GitHub Releases; that update check is its only network access (REQ-030, REQ-033).

## 2. The loop

```bash
Scripts/check.sh
```

Build, test, smoke. That is the gate, and the only thing that has to pass.

- **On a Mac**, it runs everything and ends `check: PASS` (exit 0) or `check: FAILED` (exit 1).
- **Without Xcode**, it runs the portable steps (release-script tests, verifier fixtures,
  markdownlint) and ends `check: INCOMPLETE` (exit 3). That is not a pass: the build, the tests and
  the smoke run are then CI's job `Build, test and smoke (Xcode 27)`, on the pull request's last
  commit.
- **Five minutes per commit**, local and CI together, from the moment a commit is ready to the
  moment `CI gate` reports (owner, 2026-11-26). `check.sh` prints its `duration:`, and CI keeps
  the compilation cache between runs (`Scripts/lib/build-settings.sh`). A run over budget is a
  defect to fix, not a number to note.
- A documentation-only diff (the paths in `ci.yml`'s `changes` job) skips the macOS job, which
  builds nothing such a diff could change.

## 2a. Two ways to work

Everything in this file applies to both. The SessionStart hook (`Scripts/cloud-setup.sh`) says
which one a session is in.

- **Cloud session: the default.** Claude Code on the web or phone. `CLAUDE_CODE_REMOTE=true`, an
  Ubuntu VM with no macOS or Xcode, reclaimed when idle.
  - Edit, run `Scripts/check.sh` (its portable steps), commit, and push early: an unpushed commit
    dies with the VM.
  - GitHub's macOS runner builds, tests and smokes the pushed branch. That run is the change's
    verification.
  - Read CI with the GitHub MCP tools: `actions_list` (runs and jobs), `get_job_logs`, and
    `actions_get` with `download_workflow_run_artifact` for the window screenshot. The proxy
    refuses GraphQL (`gh pr …`), tag pushes and release writes; releases happen in workflows.
  - A cloud session never uses the owner's machines, the MacBook or any server Latchkey or Remote
    Control reaches, for development or routine work: no builds, tests, screenshots, CI
    investigation or setup through them. Use GitHub's tools instead. The one exception is a
    specific action the owner asks for in that session, and it covers only that action
    (owner, 2026-11-26).
- **Local session: optional.** Claude Code the owner started on the Mac.
  - `Scripts/check.sh` runs the full gate natively, so there is no wait for CI before pushing.
  - Work in a worktree or branch, never on the main checkout's `main`.
  - Run `Scripts/smoke-screenshot.sh` after a visual change, look at it, and send it to the user.
  - Never install a build over `/Applications`. The installed app is always one CI published,
    which Sparkle keeps current.

Nothing waits for a local session, and nothing needs the owner's Mac: not development, not
releases, not setup (owner, 2026-11-26). Signing and the update key come from GitHub secrets the
owner sets in a browser. A script or procedure that needs the Mac is a defect.

## 2b. Git and pull requests

`main` changes only through a pull request whose `CI gate` passed.

- One session, one branch, one pull request. Use the branch the session was given, push early
  and often, and open the pull request at the first commit, ready for review, so other sessions
  see what is taken.
- A pull request's branch is never replaced. Fixes, review changes and catching up with `main` go
  on as new commits (`git fetch origin main && git merge origin/main`). Never rebase a pushed
  branch, force-push, or close a pull request to redo it elsewhere.
- Merge by squash. Once CI is green, merge it, or turn on auto-merge (`enable_pr_auto_merge`,
  method squash). Get a review when the change is subtle or you are unsure, not as a ritual.
- Stage files by name, never `git add -A`. Never stash: set work aside with a commit on the branch.
- End each turn with finished work merged and unfinished work pushed to its branch. The reply
  says in a line what is still open.
- Commit and pull request attribution: the trailer lines the harness supplies, as given.

## 2c. Merging ships

`.github/workflows/release.yml` runs after CI passes on a push to `main`. When the app changed, it
builds Release, signs it ad hoc (there is no Apple Developer account, so no notarization), and publishes
`v<x.y.z>`: the disk image, the Sparkle archive and `appcast.xml`. Installed copies update within
the hour.

- Never write a version number by hand. The patch comes from the published releases, a new
  series from a commit that changes `MARKETING_VERSION`, and `CFBundleVersion` is the commit count.
- Watch the `Release` run until it ends, and report its outcome.

## 3. Honesty

These are the rules that were worth keeping. They cost nothing and they are the reason the test
suite is trustworthy.

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
  unbounded measurement is not evidence — it is the *appearance* of evidence, which is worse than
  none, because it makes the area look examined. If a number is worth computing at runtime, it is
  worth a threshold; if no threshold can be named, do not compute it.
- **A proof is cheaper than the thing it proves.** `ProjectionOracle.validate` cost 3.5× the cmark
  parse it validated, on the main actor, on every formatting command — a property about a few
  thousand segment boundaries proved with a 100,000-element array. When a check is asymptotically
  more expensive than its subject, suspect the check of being badly posed before concluding that
  correctness is expensive. The repair was a *stronger* proof that cost 1% as much.
- **A measurement describes only the input it was measured on.** REQ-090 promised a p95 under
  8 ms and was satisfied by a corpus of one repeated word — 100,000 characters containing no
  heading, list, or table, which parses as a single paragraph. The number was real and described
  a document nobody has.
- **Rendered geometry is proved by forcing layout**, not by reading `NSParagraphStyle` fields.
  Constructing AppKit objects directly and asserting on `NSLayoutManager` line-fragment rects is
  a component test, not a UI test.

## 4. No UI tests

No XCUITest target, no UI-driving test, no accessibility-inspection assertions. Automated
verification, the gate and every requirement's proof, is unit and component tests; constructing
AppKit components directly is fine.

Three passive exceptions, and one instrument that drives:

- `Scripts/smoke-test.sh` launches the built app on a fixture and asserts only on the structured
  diagnostic records it writes. It never drives or reads the UI.
- `Scripts/smoke-screenshot.sh` captures one screenshot of the app's own window (never the full
  screen) over a rich fixture. Run it when you have changed anything visual, look at the result,
  and send it to the user. It is evidence for human eyes, never a requirement's proof. CI's macOS
  job runs it too and uploads the PNG as the run's `screenshot-<run id>` artifact, which is how a
  cloud session looks.
- `Scripts/screenshots.sh` does the same capture once per screen and commits the results to
  `docs/screenshots/`. A local session runs it when it has changed how the product looks, or when
  the user asks for screenshots; it needs a Mac, so a cloud session leaves the gallery as it is. A screen an ordinary launch does not reach is *named at launch*
  (`MARKDOWN_EDITOR_SMOKE_SCENE`) and presented by the app through its own command routes — never
  by clicking. Each image is committed only if that run's structured log passes.
- `.github/workflows/agent-drive.yml` is an agent's hands and eyes. It runs a scenario of real
  clicks, keys, menu choices and accessibility presses (`Scripts/agent-drive.swift`) against the
  app on a GitHub Mac runner, and uploads a screenshot, tree or value after each step. Use it to
  try a change the way a person would, then look at every image. It is never a gate and never a
  proof: a defect it finds is fixed with a unit or component test that fails for it
  (`docs/DECISIONS.md`, 2026-11-27).

## 5. Documentation

Code and tests are canonical. The specs describe current intent.

| Path | Job |
| --- | --- |
| `docs/VISION.md` | Product direction and priorities |
| `docs/ENGINEERING.md` | Current architecture, state ownership, runtime contracts, `ARC-###` invariants |
| `docs/REQUIREMENTS.md` | Numbered behavior requirements (`REQ-###`) |
| `docs/ROADMAP.md` | Delivery state and sequence |
| `docs/DECISIONS.md` | Decisions with consequences, including why the gates were removed |
| `docs/DEVELOPMENT.md` | Environments, CI, releases, and the owner's browser-only setup |
| `docs/research/` | Costly evidence still valid; never architecture authority |
| `docs/plans/` | Approved, not-yet-implemented plans |

Rewrite or delete stale text in the change that makes it stale. No "superseded" banners, no
archive — Git is the archive. Delete a plan when its work merges, **as tidying, never as
evidence**: delivery evidence is observed gate output, quoted. In August 2026 ten increments were
marked delivered by deleting their plans, having built one comment line each, which is why
deletion is no longer a signal at all.

Keep a `// Verifies: REQ-###` comment on tests that prove a specific requirement. **That comment
is the traceability mapping** — it lives next to the proof and survives refactoring. REQUIREMENTS
names tests as a convenience for the reader and deliberately does not name production types; a
hand-maintained second copy of the code rots silently. Nothing enforces this mechanically.

## 6. Architecture changes

An implementation plan cannot redefine architecture. Changing an `ARC-###` invariant needs a
reproduced counterexample or a new constraint, real API evidence where behavior is not documented,
a decision recorded in `docs/DECISIONS.md` by the §7 method, an atomic update to ENGINEERING and
affected requirements, a test that discriminates the new contract, and deletion of the displaced
path in the same change.

No supersession documents, no indefinite migrations, no compatibility layers.

## 7. Consent

Research, then present findings and options, then get explicit approval, then write it into the
specs. Approval is specific; silence is not consent.

An explicit request to implement an approved plan, or to repair something broken that you found
while doing it, authorizes the ordinary work: code, tests, the gate, branches, PRs, merges,
cleanup. Do not stop to re-ask.

**Decide, do not ask.** When a decision arises — including one that changes the product, changes
the architecture, or widens the scope — work it out and make it. Do not hand it back as a
question. The method:

1. **State the criteria** the decision turns on, derived from `docs/VISION.md`'s objective
   ordering and evaluation section rather than invented for the occasion.
2. **List the real alternatives**, including the one you expect to reject and the one that is
   simply "do nothing".
3. **Rank them against the criteria**, explicitly, including where the ranking is close.
4. **Choose**, and record the choice in `docs/DECISIONS.md` with the reasoning — especially any
   respect in which the chosen option is worse than a rejected one.

A decision that turns out badly is recoverable; Git is the archive and DECISIONS says what was
believed at the time. Stopping to ask is not free — it stalls the work and pushes judgement onto
someone who asked for the work precisely so they would not have to make it.

A user correction is durable: update this file or the authoritative doc in the same change,
sweep the docs it contradicts, and do not keep the displaced rule anywhere.

## 7a. The owner's standing rules

These are the owner's rules for every project. They are copied here because a cloud session never
reads `~/.claude/CLAUDE.md`.

- When it is already clear what the owner wants, do it. Never ask whether to do it, how, or which
  piece first, and never end a turn on a go-ahead question. Ask only for what only the owner can
  do (accounts, devices, approvals, publishing something), or for a real product choice not yet
  made (§7).
- Never end a turn while an item the owner asked for can still move forward without them. When
  one is blocked, go on to the next, and list only the owner-only steps at the end.

## 8. Before you say you are done

- The gate ran and you are reporting its actual output. In a cloud session that is CI's
  `Build, test and smoke` job on the final commit, quoted, plus the local `INCOMPLETE` line.
  Never call a change verified on `INCOMPLETE` alone.
- Docs that this change made wrong are fixed.
- Branches, worktrees, and stashes you created are gone or pushed (§2b).
- Anything you left undone is stated plainly, with the owner-only steps listed last.
