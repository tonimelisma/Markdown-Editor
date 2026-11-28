# 0010. Cloud-first development: CI is the Mac, Sparkle is the installer

- Status: accepted
- Date: 2026-11-26

## Context and problem

This repository had to be developable without a Mac: from cloud sessions, with CI as the only macOS, and with installed copies updating themselves instead of being reinstalled by hand.

## Decision drivers

**Criteria**, from vision.md's objectives and evaluation order:

1. No silent pass. `CLAUDE.md` §3: the build and the tests are either observed or reported as not run.
2. Trustworthy files. An update must not cost the user an edit.
3. Local and private (objective 5). Any network access is bounded, named and carries no content.
4. One obvious path, and cost. One gate everywhere, one installer, and no apparatus the
   [ADR 0001](0001-the-verification-apparatus-was-removed.md) would recognise.
5. No dependency on the maintainer's Mac.

## Considered options

**Alternatives, ranked.**

| Option | 1 | 2 | 3 | 4 | 5 |
| --- | --- | --- | --- | --- | --- |
| **A. Cloud sessions + GitHub macOS runner + Sparkle (chosen)** | ✓ CI's run is observed output | ✓ installs on quit, after autosave | ✓ one feed request, no profile | ✓ one gate, one workflow | ✓ |
| B. Cloud sessions drive the maintainer's Mac remotely | ✓ | ✓ | ✓ | ✗ two verification paths | ✗ needs the Mac awake |
| C. A self-hosted runner on the Mac | ✓ | ✓ | ✓ | ✓ | ✗ needs the Mac awake; runs CI code on it |
| D. Sparkle replaced by a hand-rolled updater or an install script | ✓ | ? | ✓ | ✗ re-implements signature checks and replace-and-relaunch | ✓ |
| E. Do nothing (develop on the Mac) | ✓ | — | ✓ | ✓ | ✗ |

B was closest. It would let a cloud session see a real local run. It still depends on the Mac being
awake, and it adds a second way to verify the same change.

**Choices inside A, and where each is worse.**

- **Two ways to work, as latchkey settled the same day.** A cloud session never reaches the
  maintainer's Mac during development, except for a live check asked for in that session. A
  local session is one started on a Mac. Both are described in `CLAUDE.md` itself.
- **Five minutes per commit, local and CI together** (the same budget as Otos). `check.sh` prints its duration. CI restores Xcode's
  compilation cache, and only a push to `main` saves it. Otos's prefix mapping is left out because
  it rewrites `#filePath`, which the tests here use to find files. A CI run's checkout path is
  constant, so its cache hits without it. Not yet measured here: the first CI runs give the
  baseline.

- **Automatic checks and installs, with no consent prompt.** `SUEnableAutomaticChecks` and
  `SUAutomaticallyUpdate` are set, as in latchkey and Otos, because auto-updates were
  asked for. This is worse for "no surprises" for any future user who did not expect an hourly
  request to GitHub. Sparkle's second-launch permission prompt is the change to make when the app is
  distributed to others.
- **The update key is set only in the Release configuration.** Debug and Release share a bundle
  identifier (see the restoration note in `MarkdownAppDelegate.init`). A Debug build that carried
  the key would replace itself, in DerivedData, with the published build.
- **Signing takes what it is given.** With a Developer ID identity and App Store Connect API key
  secrets, the release is notarized and stapled, as vision.md's Distribution section promises. With
  none it is signed ad hoc ([ADR 0011](0011-no-mac-not-even-once-the-update-key-comes-from-a-secret-and.md)), and the release notes say how to open it. That is worse
  than vision.md until a Developer ID exists.
- **The repository is public**, as latchkey and Otos are.
  A private repository's release assets cannot be downloaded without credentials, so the feed
  would be unreachable. Standard macOS runners are also free for public repositories, and the first
  CI run, while the repository was private, was never started. Publishing to a separate public
  repository was the alternative, and it was dropped from the scripts once this was chosen. The
  history was checked before publication: no credential, no personal path or location metadata.
  The one private value in it was the Apple team ID in `project.pbxproj`, which latchkey and Otos
  keep out of their repositories. The project now reads it from the environment
  (`$(MARKDOWN_EDITOR_DEVELOPMENT_TEAM)`) instead; removing it from history would need a rewrite
  of `main`.
- **Documentation-only changes skip the macOS job**, which builds nothing they could change. The
  `changes` job lists exactly which paths count as documentation; anything else, `.github/`
  included, runs macOS.

## Decision

**Decision.** Claude Code cloud sessions are this repository's default environment. A cloud session
has no Xcode, so GitHub Actions' `xcode-27` runner runs `Scripts/check.sh` for every pull request and
every push to `main`. That run, on a pull request's last commit, verifies a change made in the cloud.
A session on a Mac is optional: it runs the same gate locally and does not wait for CI. Where
there is no Xcode, `Scripts/check.sh` ends `INCOMPLETE` with exit status 3, never `PASS`.

Every `main` commit that passes CI and changes the app is published by `.github/workflows/release.yml`:
a signed Release build, a disk image, and Sparkle's feed. Installed copies update themselves within
the hour (REQ-033). The shape is Otos's ADR 0059, adapted. The evidence is in
[research/2026-11-26-cloud-first-development.md](../research/2026-11-26-cloud-first-development.md).

## Consequences

**Consequences.**

- REQ-030 now allows one network access: the update check, REQ-033. `PrivacyBoundaryTests` bounds it
  to the one file that imports Sparkle.
- `CLAUDE.md` was rebuilt around this, with its section numbers kept because other documents
  cite them. The stale model-named commit trailer gave way to the harness's attribution, and "small
  doc fixes can go straight to `main`" gave way to one pull request per session.
- Verification builds (`check.sh`, the smoke scripts) sign ad hoc wherever they run
  (`Scripts/lib/build-settings.sh`). The first CI run failed because the project's automatic
  signing wanted a team certificate the runner does not have, and no verification should depend
  on one person's Apple account. latchkey settled the same for its sandbox Mac the same day. Only
  `Scripts/release.sh` signs with a configured identity, when one is set.
- The repository gained a shared scheme. CI's fresh checkout has no autocreated scheme to rely on.
- Not yet observed: an installed copy updating itself. Until then REQ-033 is `Active`, not `Done`.

## Confirmation

CI's `Build, test and smoke (Xcode 27)` job runs `Scripts/check.sh` on every pull request and push to main; `PrivacyBoundaryTests` bound network access to the one file that imports Sparkle (REQ-030, REQ-033); `Scripts/check.sh` exits 3 (`INCOMPLETE`) without Xcode.

## Retirement proof

A verification path that needs a Mac becoming cheaper than the runner, or Sparkle no longer being the platform's update mechanism.

## Reversal plan

Develop on a Mac again: the gate already runs there; the release workflow and Sparkle feed can stay.
