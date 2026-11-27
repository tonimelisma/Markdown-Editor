# Cloud-first development of a macOS app

Date: 2026-11-26. Sources fetched that day. The decision built on it is in
[DECISIONS.md](../DECISIONS.md), "Cloud-first development".

## Question

The owner (2026-11-26): Claude Code cloud sessions become the default environment for this repository
(development, testing, building and releasing), with no dependency on the owner's MacBook. A session on
the Mac stays possible, and then runs the tests locally instead of waiting for CI. The app updates
itself with Sparkle and ships as a disk image. Do what latchkey and Otos (the owner's other macOS apps)
do, and keep everything in `CLAUDE.md`.

## What the sibling projects do (read 2026-11-26)

Both repositories are public, both develop in cloud sessions, and both verify through GitHub Actions.

- **Otos** (commit `be217c2`):
  - Every push runs `script/check.sh` on GitHub's `xcode-27` macOS runner. That run, on a pull
    request's last commit, is the verification for a change made in a cloud session.
  - A SessionStart hook (`script/cloud-setup.sh`) installs the Linux lint tools only when
    `CLAUDE_CODE_REMOTE=true`. In the VM, `check.sh` runs every gate that needs no Xcode and ends
    `check: INCOMPLETE`.
  - `release.yml` runs after CI passes on `main`. It builds and signs with the owner's Apple
    Development certificate, imported into a per-run keychain. It signs the zip with the app's own
    EdDSA key. It publishes `v<x.y.z>` with a DMG, the zip, dSYMs and `appcast.xml`, and marks the
    release latest, so `releases/latest/download/appcast.xml` is a stable feed URL.
  - Versions: the patch is the next one in the `MARKETING_VERSION` series, and `CFBundleVersion` is
    the commit count. The release skips a commit that does not change the app, refuses a Sparkle
    with OSV advisories, keeps the newest three releases, and is not notarized (ADR 0059).
  - The owner's one-time `script/release-setup.sh` on the Mac makes the key under the app's own
    keychain account and sets the environment `release`'s secrets with `gh`.
  - Its plan 0118 ("CI is the only Mac") and research note
    `2026-11-26-agent-instruction-files.md` cut `AGENTS.md` from 728 lines toward about 200.
- **latchkey** (commit `9adb867`, re-read at `bee78fa`):
  - The same Sparkle shape (`mac-tag.yml`, environment `release`, Apple Development certificate).
  - `mac-build.yml` splits macOS tests over four parallel jobs and keeps Xcode's compilation cache.
  - Hooks keep a session from leaving work unpushed.
  - Its `CLAUDE.md` had about 300 lines. #59 (`bee78fa`) cut it to about 200, with owner setup
    moved to `docs/development.md`.
  - #59 also settled "two ways to work". Cloud sessions are the main way and never use the
    MacBook during development, except for a live check the owner asks for. A local session is
    Claude Code started on the Mac and runs the Mac tests there. Both are described in `CLAUDE.md`
    itself, and the Mac tests gate merging.
  - Merges are squash merges by auto-merge. A pull request opens at its first commit, and a
    pushed branch is never rebased or force-pushed.
- **Otos, in progress** (branch `friendly-gates-m0b2mj`, `d8cf08c`): a commit is checked within
  five minutes, locally and on CI together (owner, 2026-11-26). Its CI restores Xcode's
  compilation cache and the lint caches, and only `main` saves them. Every check prints its
  durations.

## Findings

### The cloud environment

- A cloud session is Ubuntu 24.04 on x86_64 with about 4 vCPU, 16 GB of memory and 30 GB of disk,
  whatever the user's own OS. It has no macOS and no Xcode.
  <https://code.claude.com/docs/en/cloud-environments>
- The repository's `CLAUDE.md`, `.claude/rules/`, skills and `.claude/settings.json` hooks load in a
  cloud session. Hooks load only when the session has a single repository. A SessionStart hook runs
  locally and in the cloud; `CLAUDE_CODE_REMOTE` is `true` only in the cloud. What the hook prints
  is added to the session's context. (same page)
- A setup script runs as root and is snapshotted only if it finishes in about 5 minutes. Network
  secrets are injected by the proxy, and the VM never holds the key. (same page)
- Moving between environments: `claude --cloud "task"` starts a cloud session, and `claude --teleport`
  pulls one into the local terminal (it needs a clean tree and a pushed branch). The Desktop app can
  send a local session to the cloud. A cloud session can ask to attach a folder on the user's
  computer through Remote Control. <https://code.claude.com/docs/en/claude-code-on-the-web>,
  <https://code.claude.com/docs/en/remote-control>
- From this session's own observation: GitHub is reached through the session's GitHub tools, whose
  Actions endpoints list runs and jobs, return job logs, and return artifact download links. Otos
  records that the same proxy refuses GraphQL, tag pushes and REST release writes from the VM, so
  releases must be made by a workflow, never by the session.

### CLAUDE.md for current models

- Keep each file under about 200 lines: "Longer files consume more context and reduce adherence."
  `@path` imports do not reduce that cost. <https://code.claude.com/docs/en/memory>
- Keep only what Claude cannot infer from the code: the exact commands, where the code misleads,
  decisions not recorded in the repository, and anything corrected twice. Do not describe the
  architecture or the file layout, since Claude reads the repository itself.
  <https://code.claude.com/docs/en/best-practices>
- Current models follow a plainly worded line, and "piling on emphasis mostly makes Claude
  over-apply the rule". Give the reason; say what to do rather than what not to do. A rule that has
  to hold every time belongs in a hook or a test.
  <https://code.claude.com/docs/en/best-practices>,
  <https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices>
- Environment-specific notes can be printed by the SessionStart hook only where they apply, instead
  of loading in every session. Otos's note, citing the hooks documentation.

### GitHub-hosted macOS runners

- `xcode-27` (arm64, macOS 27) has been generally available since October 2026. A standard macOS
  runner has 3 cores, 7 GB of memory and 14 GB of disk. Standard runners are free for public
  repositories. Private repositories pay from the plan's minutes, and macOS minutes cost several
  times Linux minutes. Otos's research note `2026-11-26-ci-only-macos-development.md` (sources
  there); the multiplier was not re-verified here.
- The images keep the display awake and pre-grant Screen Capture to `/bin/bash`, which is what
  `Scripts/smoke-screenshot.sh` needs to capture the app's own window. Otos's note, citing
  actions/runner-images.

### Sparkle 2

- The latest stable release is 2.10.1 (tagged 2026-10-25); 2.11.0-beta.1 followed on 2026-11-16.
  Checked against the repository's tags. OSV reports no advisory for 2.10.1
  (`Scripts/sparkle-advisories.sh`, 2026-11-26).
- `generate_keys` keeps the private EdDSA key in the login keychain (`-x` exports it). `sign_update`
  takes the key on standard input with `--ed-key-file -`. With SwiftPM the tools are in
  `SourcePackages/artifacts/sparkle/Sparkle/bin/`. <https://sparkle-project.org/documentation/>
- Sparkle recommends a Developer ID–signed, notarized DMG that holds the app beside an
  `/Applications` link, served over HTTPS. Notarization takes a DMG or a zip; a zip cannot be
  stapled, so the app inside is stapled instead.
  <https://sparkle-project.org/documentation/publishing/>,
  <https://developer.apple.com/documentation/security/customizing-the-notarization-workflow>
- `hdiutil create` on hosted runners intermittently fails with "Resource busy", so retry it.
  <https://gitlab.kitware.com/cmake/cmake/-/issues/25671>

## What differs here

1. **This repository was private, and the siblings are public.** The owner then made it public.
   - A private repository's release assets are not downloadable without credentials, so installed
     copies cannot read a feed there.
   - Its macOS CI minutes are billed against the plan.
   - The siblings resolved both by going public, and so did this repository (owner, 2026-11-26).
2. **VISION promises Developer ID signing and notarization; the siblings use an Apple Development
   certificate without notarization**, exported from the owner's Mac (Otos re-exports it yearly).
   The owner ruled out any Mac step here. Releases therefore sign ad hoc unless a certificate secret
   is set, and derive the update key from a secret password. Sparkle 2.10.1's `SUUpdateValidator`
   accepts an update whose EdDSA key is unchanged, whatever its signing identity, and its own
   message says "adhoc signing can be used at minimum". Sparkle's private-key format is the
   32-byte Ed25519 seed, base64 (`common_cli/Secret.swift`).
3. **REQ-030 promised no network access.** Sparkle's update check is the first network access the
   application makes, so the requirement has to change with the code.
4. **Debug and Release share one bundle identifier** (Otos's dev builds have their own). So the
   update key is set only in the Release configuration, and the Debug builds that Xcode, the tests
   and the smoke scripts run never replace themselves.
5. **There was no CI at all, and no shared scheme.** `xcodebuild -scheme` had relied on a scheme that
   Xcode autocreated on the Mac.

## Conclusions

- Cloud sessions are the default environment. GitHub's `xcode-27` runner is the only Mac anything
  waits for. A session on the Mac is optional and runs the same gate locally.
- `Scripts/check.sh` ends INCOMPLETE (exit 3) where there is no Xcode, never PASS.
- Releases follow the Otos shape, with notarization when the identity allows it.
- The repository goes public, as the siblings did (owner, 2026-11-26).
