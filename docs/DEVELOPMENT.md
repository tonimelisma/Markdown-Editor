# DEVELOPMENT

Where the work runs, what CI does, how a release is made, and the owner's one-time setup. The rules
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
| `Does it need macOS?` | Linux | A diff confined to `docs/`, top-level `*.md`, `.claude/`, `.gitignore` or the markdownlint config needs no Mac |
| `Portable steps (Linux)` | Linux | `Scripts/check.sh`, expecting exit 3 |
| `Build, test and smoke (Xcode 27)` | `xcode-27` | `Scripts/check.sh` in full, then one window screenshot uploaded as `screenshot-<run id>` (never gating) |
| `CI gate` | Linux | the one check a ruleset requires: every job passed, or macOS was rightly skipped |

The macOS job restores Xcode's compilation cache and the Swift packages from `main`'s newest
run, and only a push to `main` saves them. A failed run uploads `check-logs-<run id>-<attempt>`.

Reading CI from a cloud session: the GitHub MCP tools.

- `actions_list` with `list_workflow_runs`, then `list_workflow_jobs`.
- `get_job_logs` with `failed_only`.
- `actions_get` with `download_workflow_run_artifact`, for the screenshot.

## Releases (`.github/workflows/release.yml`, `Scripts/release.sh`)

After CI passes on a push to `main`, and only when `Markdown Editor/` or
`Markdown Editor.xcodeproj/` changed since the newest release:

1. Refuse if the pinned Sparkle has OSV advisories (`Scripts/sparkle-advisories.sh`).
2. Build the Release configuration, signed with the identity from `CERTIFICATE_P12`.
   `CFBundleVersion` is the commit count. `CFBundleShortVersionString` is the next patch of
   `MARKETING_VERSION` (`Scripts/release-version.sh`).
3. Check the built app: a valid signature, a non-empty `SUPublicEDKey`, and `SUFeedURL` naming the
   repository it is published to.
4. With a Developer ID identity and the notary secrets, notarize and staple the app and the disk
   image.
5. Make `Markdown-Editor.dmg` (the app beside an Applications link) and the Sparkle zip. Sign the zip
   with the EdDSA key (`sign_update`, key on standard input) and write `appcast.xml`
   (`Scripts/appcast.sh`).
6. Publish `v<x.y.z>` as the latest release, and delete all but the newest three.

The stable addresses are `releases/latest/download/appcast.xml` (the feed installed copies read)
and `releases/latest/download/Markdown-Editor.dmg` (the first install).

## Owner setup (once; only the owner can do these)

1. **Make the feed reachable.** A private repository's release assets need credentials, so
   installed copies cannot read a feed there. Choose one:
   - Make this repository public, as latchkey and Otos are. Nothing else changes.
   - Or publish to a public repository: create it, set the Actions variable `RELEASE_REPOSITORY`
     (`owner/name`) and the `release` environment secret `RELEASE_TOKEN` (a fine-grained token with
     Contents: write on that repository). Then change both `SPARKLE_FEED_URL` build settings in
     `project.pbxproj` to name it.
2. **Protect `main`.** Add a ruleset that requires the status check `CI gate`, allows squash
   merges only, and blocks force-pushes and deletion. Also turn on "Allow auto-merge" and
   "Automatically delete head branches".
3. **On the Mac, once:** `Scripts/release-setup.sh` in a clean checkout of `main`. It:
   - makes the update key in the login keychain (account `net.melisma.Markdown-Editor`);
   - exports the team's newest valid Developer ID Application identity, or failing that its
     Apple Development one;
   - sets `SPARKLE_PRIVATE_KEY`, `CERTIFICATE_P12` and `CERTIFICATE_PASSWORD` in the environment
     `release`;
   - opens the pull request that commits the public key.

   Merge that pull request. The next app change then publishes the first release.
4. **Optional, with a Developer ID:** set `NOTARY_KEY_P8` (the App Store Connect API key's `.p8`
   contents), `NOTARY_KEY_ID` and `NOTARY_ISSUER_ID` in the environment `release`, using
   `gh secret set <name> --env release`.
5. **Install once** from `releases/latest/download/Markdown-Editor.dmg`. Without notarization, the
   first open needs System Settings → Privacy & Security → Open Anyway. From then on it updates
   itself.

Until step 3 is done, the `Release` job warns which secrets are missing and publishes nothing.
