# DEVELOPMENT

Where the work runs, what CI does, how a release is made, and the owner's setup, which is done in a
browser and never needs the owner's Mac. The rules
for a session are in [`CLAUDE.md`](../CLAUDE.md) §2. The reasoning behind this layout is in
[DECISIONS.md](DECISIONS.md), 2026-11-26.

## Environments

| | Cloud session (default) | Local session (optional) | GitHub Actions |
| --- | --- | --- | --- |
| Started by | claude.ai/code, the phone, `claude --cloud` | Claude Code on the owner's Mac | a push, a pull request, a merge |
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
| `CI gate` | Linux | the one check a ruleset requires: every job passed, or macOS was rightly skipped |

The macOS job restores Xcode's compilation cache and the Swift packages from `main`'s newest
run, and only a push to `main` saves them. A failed run uploads `check-logs-<run id>-<attempt>`.

Two more workflows serve CI without gating anything:

- **`retry-unstarted.yml`**: when a CI or Release job ended without GitHub ever assigning it a
  runner (no runner, no steps), it re-runs that run's failed jobs. It runs at most twice, and only
  while the commit is still its branch's tip. A job that ran and failed is never retried.
- **`repeat-smoke.yml`**: started by hand (`actions_run_trigger`, `run_workflow`). It runs the
  smoke test `count` times on one runner and uploads every run's diagnostics as
  `repeat-smoke-<run id>`. `configuration: Release` launches the hardened Release bundle,
  `fresh` a new copy each time, `settle` waits after the build, and `sample` takes a `spindump` of
  each launch. Use it to chase a failure that comes and goes, instead of re-running CI.

Reading CI from a cloud session: the GitHub MCP tools.

- `actions_list` with `list_workflow_runs`, then `list_workflow_jobs`.
- `get_job_logs` with `failed_only`.
- `actions_get` with `download_workflow_run_artifact`, for the screenshot.

## Releases (`.github/workflows/release.yml`, `Scripts/release.sh`)

After CI passes on a push to `main`, and only when the published app would differ from the newest
release — anything under `Markdown Editor/` or `Markdown Editor.xcodeproj/`, or in the scripts that
sign it (`Scripts/release.sh`, `Scripts/adhoc-harden.sh`), since build 202's defect was entirely in
the signing:

1. Refuse if the pinned Sparkle has OSV advisories (`Scripts/sparkle-advisories.sh`).
2. Derive the update key from `SPARKLE_SEED` (`Scripts/sparkle-key.sh`) and build the Release
   configuration with its public half as `SUPublicEDKey`. Signing uses the identity from
   `CERTIFICATE_P12` if one is set, and is ad hoc otherwise. `CFBundleVersion` is the commit count.
   `CFBundleShortVersionString` is the next patch of `MARKETING_VERSION`
   (`Scripts/release-version.sh`).
3. Without a Developer ID, re-sign the app ad hoc with the hardened runtime's
   library-validation exception and without `get-task-allow` (`Scripts/adhoc-harden.sh`). An ad hoc
   app cannot load its own `Sparkle.framework` otherwise, and build 202 was published unable to
   start at all (`DECISIONS.md`, 2026-11-26).
4. Check the built app: a valid signature, the entitlements the signing above implies, the derived
   `SUPublicEDKey`, and `SUFeedURL` naming the repository it is published to.
5. **Launch it, twice.** `SMOKE_APP=… Scripts/smoke-test.sh` runs the bundle about to be published
   on a fixture and asserts on its diagnostic records (REQ-098). It installs no update: REQ-034
   keeps a smoke run from checking for one. The first launch is allowed a `mainActorStall`, and
   nothing else: on a runner booted minutes earlier it pages AppKit in from a cold disk. The
   second launch is held to every check (`DECISIONS.md`, 2026-11-27). Note what this step cannot do: GitHub's runners do not enforce
   library validation, so a build with build 202's defect would launch there and still die on every
   Mac. Step 4's entitlement check is what catches that one (`DECISIONS.md`, 2026-11-26).
6. With a Developer ID identity and the notary secrets, notarize and staple the app and the disk
   image.
7. Make `Markdown-Editor.dmg` (the app beside an Applications link) and the Sparkle zip. Sign the zip
   with the update key, then check that signature with Sparkle's own `sign_update --verify`. Then
   write `appcast.xml` (`Scripts/appcast.sh`).
8. Publish `v<x.y.z>` as the latest release, and delete all but the newest three.

The stable addresses are `releases/latest/download/appcast.xml` (the feed installed copies read)
and `releases/latest/download/Markdown-Editor.dmg` (the first install).

## Owner setup (only the owner can do these, all in GitHub's web settings, from any device)

Steps 1 to 3 were done on 2026-11-26: the repository is public, `main`'s ruleset is active, and
`SPARKLE_SEED` is set, with a copy the owner keeps outside GitHub.

1. **Make the repository public** (owner's choice, 2026-11-26): Settings → General → Danger Zone
   → Change visibility → Public. Sparkle can then read the release feed, which a private
   repository's release assets do not allow without credentials. Standard GitHub-hosted runners,
   macOS included, are also free for public repositories.
2. **Protect `main`.** A ruleset named `main` requires the status check `CI gate` and a pull
   request, allows squash merges only, and blocks force-pushes and deletion. The repository allows
   only squash merges, allows auto-merge, and deletes merged branches.
3. **The update key.** Settings → Environments → New environment `release` → Add environment
   secret `SPARKLE_SEED`: a random password of at least 32 characters, for example one a password
   manager generates. Keep a copy in the password manager. The release derives the app's EdDSA key
   from it on every run. Changing or losing it means installed copies reject every later update,
   until they are reinstalled by hand. The next app change after this publishes the first release.
4. **Optional, later: a certificate.** Without one, the app is signed ad hoc, macOS asks once to
   allow it, and the build needs the library-validation exception to load its own frameworks
   (`DECISIONS.md`, 2026-11-26). A Developer ID removes that exception and gets notarization:
   - `CERTIFICATE_P12` and `CERTIFICATE_PASSWORD`: the identity as a base64 `.p12`;
   - `NOTARY_KEY_P8`, `NOTARY_KEY_ID`, `NOTARY_ISSUER_ID`: an App Store Connect API key.

   Adding one does not break updates: Sparkle accepts a new signing identity as long as the update
   key is unchanged.
5. **Install once** from `releases/latest/download/Markdown-Editor.dmg`. Without notarization, the
   first open needs System Settings → Privacy & Security → Open Anyway. From then on it updates
   itself.

Until step 3 is done, the `Release` job warns that `SPARKLE_SEED` is missing and publishes nothing.
