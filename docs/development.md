# Development

Where the work runs, what CI does, how a release is made, and the maintainer's one-time setup,
which is done in a browser and never needs a Mac. The rules for a session are in
[`CLAUDE.md`](../CLAUDE.md) (§2 and "Environments"). The reasoning behind this layout is in
[ADR 0010](adr/0010-cloud-first-development-ci-is-the-mac-sparkle-is-the.md).

## Environments

| | Cloud session (default) | Local session (optional) | GitHub Actions |
| --- | --- | --- | --- |
| Started by | claude.ai/code, the phone, `claude --cloud` | Claude Code on any Mac with Xcode 27 | a push, a pull request, a merge |
| Machine | Ubuntu VM, no Xcode | the Mac | `ubuntu-24.04` and `xcode-27` (macOS 27, Xcode 27) |
| `Scripts/check.sh` | portable steps → `INCOMPLETE` (exit 3) | everything → `PASS`/`FAILED` | both, as two jobs |
| Verifies a change by | CI's macOS job | its own run (CI repeats it) | — |

The repository's `.claude/settings.json` runs `Scripts/cloud-setup.sh` at session start. In the
cloud it makes sure `python3` and `npx` exist. In every session it prints one line naming the
environment. The cloud environment needs no extra network hosts: npm (markdownlint) and GitHub
are reachable by default.

Moving between the two: `claude --teleport` pulls a cloud session into the Mac's terminal; it needs
a clean tree and a pushed branch. The Desktop app's **Open in** sends a local session to the cloud.

## CI (`.github/workflows/ci.yml`)

| Job | Runner | What it does |
| --- | --- | --- |
| `Does it need macOS?` | Linux | A diff confined to `docs/`, top-level `*.md`, `.claude/`, `.gitignore` or the markdownlint config needs no Mac. A push to `main` also needs one whenever the app (`Scripts/lib/app-paths.sh`) differs from the newest release, because Release would publish it |
| `Portable steps (Linux)` | Linux | `Scripts/check.sh`, expecting exit 3 |
| `Build, test and smoke (Xcode 27)` | `xcode-27` | `Scripts/check.sh` in full, then one window screenshot uploaded as `screenshot-<run id>` (never gating) |
| `Process` | Linux | `script/process-check` (requirement IDs, `Validates:` tags and doc links agree) and, on a pull request, `script/pr-check` (the description has every template section; a `fix` PR changes a test) |
| `CI gate` | Linux | the one check the ruleset requires: every job passed, or macOS was rightly skipped |

CI runs on every pull request (including a description edit, which `script/pr-check` reads), every
push to `main`, weekly on Tuesdays at 06:23 UTC on `main`, and by hand.

The macOS job restores Xcode's compilation cache and the Swift packages from `main`'s newest
run, and only a push to `main` saves them. A failed run uploads `check-logs-<run id>-<attempt>`.

More workflows serve CI without gating anything:

- **`branch-cleanup.yml`**: deletes the branch of a pull request closed without merging (merged
  ones GitHub deletes itself), when one closes and daily.
- **`repeat-smoke.yml`**: weekly (Wednesdays 05:47 UTC, twelve Release launches) and started by hand (`actions_run_trigger`, `run_workflow`). It runs the
  smoke test `count` times on one runner and uploads every run's diagnostics as
  `repeat-smoke-<run id>`. `configuration: Release` launches the hardened Release bundle,
  `fresh` a new copy each time, `settle` waits after the build, and `sample` takes a `spindump` of
  each launch. Use it to chase a failure that comes and goes, instead of re-running CI.
- **`agent-drive.yml`**: weekly (Wednesdays 04:37 UTC, the whole `tour.txt` on `main`), started by
  hand (`run_workflow`, `ref` the branch to build), and on a pull request that changes the driver or
  its scenarios. It builds Release, hardened ad hoc and without the
  update key, unless `inputs.configuration` is `Debug`, which `sample` can attach to. The driver (`Scripts/agent-drive.swift`, whose
  header lists every step) launches the app through Launch Services, as the Dock and Finder do, and
  uses it: real keys, clicks and scrolls, menus and panels, the clipboard, shell commands standing in
  for other apps, Light and Dark, quit and relaunch. `inputs.scenario` holds steps; empty, it runs
  `inputs.scenario_file` from `Scripts/agent-drive/`, by default `tour.txt`, the whole app from a plain
  launch to a relaunch. `$WORK` in a step is a copy of `Scripts/Fixtures`. The artifact
  `agent-drive-<run id>` holds `transcript.txt` (one numbered, timed line per step), each step's
  captures, trees, values and files, the work directory as the tour left it, and the app's
  diagnostic logs. `clickat` takes a point of the window in screenshot pixels: the runner's display
  is 1×.

Reading CI from a cloud session: the GitHub MCP tools.

- `actions_list` with `list_workflow_runs`, then `list_workflow_jobs`.
- `get_job_logs` with `failed_only`.
- `actions_get` with `download_workflow_run_artifact`, for the screenshot and agent-drive's
  artifact; then `curl` the returned URL and look at each image.

## Releases (`.github/workflows/release.yml`, `Scripts/release.sh`)

After CI passes on a push to `main`, and only when the published app would differ from the newest
release — anything under `Markdown Editor/` or `Markdown Editor.xcodeproj/`, or in the scripts that
sign it (`Scripts/release.sh`, `Scripts/adhoc-harden.sh`), since build 202's defect was entirely in
the signing:

1. Refuse if the pinned Sparkle has OSV advisories (`Scripts/sparkle-advisories.sh`).
2. Derive the update key from `SPARKLE_SEED` (`Scripts/sparkle-key.sh`) and build the Release
   configuration with its public half as `SUPublicEDKey`, signed ad hoc: there is no Apple
   Developer account ([ADR 0015](adr/0015-no-apple-developer-account-releases-are-ad-hoc-for-good.md)). `CFBundleVersion` is the commit count.
   `CFBundleShortVersionString` is the next patch of `MARKETING_VERSION`
   (`Scripts/release-version.sh`).
3. Re-sign the app ad hoc with the hardened runtime's
   library-validation exception and without `get-task-allow` (`Scripts/adhoc-harden.sh`). An ad hoc
   app cannot load its own `Sparkle.framework` otherwise, and build 202 was published unable to
   start at all ([ADR 0012](adr/0012-an-ad-hoc-app-needs-the-library-validation-exception-and-a.md)).
4. Check the built app: a valid signature, the entitlements the signing above implies, the derived
   `SUPublicEDKey`, and `SUFeedURL` naming the repository it is published to.
5. **Launch it, twice.** `SMOKE_APP=… Scripts/smoke-test.sh` runs the bundle about to be published
   on a fixture and asserts on its diagnostic records (REQ-098). It installs no update: REQ-034
   keeps a smoke run from checking for one. The first launch is allowed a `mainActorStall`, and
   nothing else: on a runner booted minutes earlier it pages AppKit in from a cold disk. The
   second launch is held to every check ([ADR 0014](adr/0014-a-release-launches-its-bundle-twice-the-first-launch-s-stall.md)). Note what this step cannot do: GitHub's runners do not enforce
   library validation, so a build with build 202's defect would launch there and still die on every
   Mac. Step 4's entitlement check is what catches that one ([ADR 0012](adr/0012-an-ad-hoc-app-needs-the-library-validation-exception-and-a.md)).
6. Make `Markdown-Editor.dmg` (the app beside an Applications link) and the Sparkle zip. Sign the zip
   with the update key, then check that signature with Sparkle's own `sign_update --verify`. Then
   write `appcast.xml` (`Scripts/appcast.sh`).
7. Publish `v<x.y.z>` as the latest release, and delete all but the newest three.

The stable addresses are `releases/latest/download/appcast.xml` (the feed installed copies read)
and `releases/latest/download/Markdown-Editor.dmg` (the first install).

## Maintainer setup (one time, all in a browser)

All of it is done; it is recorded so it can be redone.

1. **The repository is public.** Sparkle can then read the release feed, which a private
   repository's release assets do not allow without credentials. Standard GitHub-hosted runners,
   macOS included, are also free for public repositories.
2. **`main` is protected.** A ruleset on the default branch requires a pull request and the status
   check `CI gate` (from GitHub Actions), allows squash merges only, and blocks force-pushes and
   deletion, with no bypass. The repository allows only squash merges, allows auto-merge, uses the
   pull request's title and body as the squash commit's, and deletes merged branches.
3. **The update key.** Its seed, a random password of at least 32 characters, has its master copy
   in the Azure Key Vault that the `release` environment's `AZURE_KEY_VAULT` variable names, as the
   secret `markdown-editor-sparkle-seed`; the vault is managed outside this repository. The
   `Release` job's first step fetches it keylessly into `SPARKLE_SEED`: GitHub's OIDC token for the
   environment `release` is exchanged for a token of an Entra app that trusts only
   `repo:tonimelisma/Markdown-Editor:environment:release`. The environment `release` deploys only
   from `main` and holds only the variables `AZURE_CLIENT_ID`, `AZURE_TENANT_ID` and
   `AZURE_KEY_VAULT`, none of them secret; there is no GitHub secret. The release derives the app's
   EdDSA key from the seed on every run. Changing or losing it means installed copies reject every
   later update, until they are reinstalled by hand.
4. **Install once** from `releases/latest/download/Markdown-Editor.dmg`. Without notarization, the
   first open needs System Settings → Privacy & Security → Open Anyway. From then on it updates
   itself.

There is no Apple Developer account and there will not be one
([ADR 0015](adr/0015-no-apple-developer-account-releases-are-ad-hoc-for-good.md)), so there is no
certificate or notarization step, and no signing identity anywhere in CI.

If the fetch fails (the vault, the secret or the Entra app's federated credential is missing), the
`Release` job fails at its first step and publishes nothing.

## Signing on a local Mac

The project file names no Apple team: `DEVELOPMENT_TEAM = $(MARKDOWN_EDITOR_DEVELOPMENT_TEAM)`,
which `xcodebuild` and Xcode read from the environment. Every script and CI build signs ad hoc and
sets `DEVELOPMENT_TEAM=` explicitly (`Scripts/lib/build-settings.sh`, `Scripts/release.sh`), so
nothing needs the variable. To sign a local build with your own team in Xcode, set it for GUI apps
before launching Xcode (`launchctl setenv MARKDOWN_EDITOR_DEVELOPMENT_TEAM <team id>`), never in
the project file.

## Planning an increment

Plans live in the pull request's Definition of Ready, or for several increments in a GitHub
tracking issue with a checklist, never in files. A plan is tidying, never evidence: delivery
evidence is one thing only, observed gate output, quoted
([ADR 0004](adr/0004-the-planning-apparatus-was-reduced.md)). Plans implement the current
architecture in [architecture.md](architecture.md); they do not redefine it.

### What a plan must answer

Four questions. **Write only what the increment actually has** — a plan for a one-line build-setting
change has no rollback behavior, and inventing a section for it produces ceremony, not thought.

1. **What is broken, and what is the evidence?** A reproduced defect, a measurement, or a
   requirement with no proof. Not "we should".
2. **What is the smallest change that fixes the cause rather than the symptom?** Name the files,
   types, and routes — including what gets **deleted**, since this repo keeps no displaced paths.
3. **What proof turns red if this is wrong?** `CLAUDE.md` §3's question, asked once, in the plan.
4. **What decisions does this make, and on what criteria?** Blockers, architecture changes,
   product judgement. Decide them by `CLAUDE.md` §7's method — criteria, alternatives, ranking,
   choice — and record the ones with consequences as an ADR in `docs/adr/`. Do not hand a decision
   back as a question.

Add anything else the increment genuinely has — ordered phases, instrumentation, failure behavior,
a deletion gate — when it has one.

### Executing a plan

1. **Check the blockers.** Some plans are blocked on another increment; some demand judgement,
   which the executor supplies by `CLAUDE.md` §7's method rather than by asking.
2. **Take them in the tracking issue's order.** The order encodes real dependencies. After its
   named blockers land, a plan must be implementable and mergeable without bundling another plan.
3. **Run the gate and read its output.** `Scripts/check.sh`. A plan is not done because its steps
   were performed — it is done when its stated proof is observed passing.
4. **If the plan is wrong, stop and re-plan.** A plan that does not survive contact with the code
   is a finding. Do not improvise production changes the plan does not authorise, and do not
   commit a placeholder to keep the sequence moving. On 2026-08-10 ten increments were committed as
   one-line stubs rather than reported as not-started, and the roadmap recorded them as delivered.
5. **Characterize before replacing.** Existing production behavior may already satisfy part of a
   plan. Keep proven correct code, add missing route evidence, and replace only a reproduced defect.

`file.swift:NNN` references in a plan are indicative; symbols are authoritative. Line numbers
drift. If a citation no longer lands on what its surrounding prose describes, trust the
description and the symbol name, and fix the citation in the same change.
