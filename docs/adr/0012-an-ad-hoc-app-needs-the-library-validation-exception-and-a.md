# 0012. An ad hoc app needs the library-validation exception, and a release is proved by launching it

- Status: accepted
- Date: 2026-11-26

## Context and problem

**What happened.** v1.0.0 (build 202) was published, installed, and could not start. Every launch
died in dyld before `main`:

```text
Library not loaded: @rpath/Sparkle.framework/Versions/B/Sparkle
Reason: ... not valid for use in process: mapping process and mapped file (non-platform)
have different Team IDs
```

An ad hoc signature carries no Team ID. Library validation, part of the hardened runtime, loads
only a library whose team matches the process's, and "no team" never matches "no team" — so an ad
hoc app cannot load its own embedded framework. Signing the bundle deeply in one pass does not
help; observed on the published bundle and on a build from source.

**Why CI was green.** The gate's smoke run launches the *Debug* app, and Debug is signed without
the hardened runtime: it sets `ENABLE_DEBUG_DYLIB = YES` (previews), and library validation would
refuse that build's own `Markdown Editor.debug.dylib` exactly as it refused Sparkle. Re-signing the
Debug bundle with `--options runtime` and nothing else changed reproduces the crash, which is the
evidence that the hardened runtime is the single switch. `ENABLE_HARDENED_RUNTIME = YES` in both
configurations, so the project setting said nothing. Release signs `0x10002(adhoc,runtime)`, Debug
`0x2(adhoc)`. The release path then checked only `codesign --verify --deep --strict`, which is
content with an app that cannot start, and nothing ever launched a Release build.

## Decision drivers

**Criteria** (vision.md: the product is installable and it works; honesty of evidence; no step on the
maintainer's Mac; one obvious path, cost).

## Considered options

| Option | Installs and runs | Security given up | No Mac | Cost |
| --- | --- | --- | --- | --- |
| **A. Library-validation exception on the ad hoc build only (chosen)** | ✓ | the one exception; the rest of the hardened runtime stays | ✓ | ✓ one script |
| B. Require a Developer ID (`CERTIFICATE_P12`) | ✓ | none — and notarization becomes possible | ✗ needs a paid account first; no release until then | ✗ |
| C. Drop the hardened runtime from Release | ✓ | all of it, and notarization is then impossible | ✓ | ✓ |
| D. Link Sparkle statically, or drop the updater | ✓ | none | ✓ | ✗ Sparkle ships as a framework; REQ-033 would go |
| E. Do nothing | ✗ | — | ✓ | — |

B is the right end state and A does not block it: the exception is granted only when there is no
identity, so the day `CERTIFICATE_P12` is set, library validation comes back on by itself. C gives
up far more for the same benefit. D trades a shipped requirement for a signing nicety.

## Decision

**Decision.** The ad hoc Release build is re-signed with
`com.apple.security.cs.disable-library-validation` (`Scripts/adhoc-harden.sh`), and no release is
published until that exact bundle has been launched and has passed REQ-098's smoke assertions
(`Scripts/release.sh`). `get-task-allow` is dropped from the published signature at the same time.

## Consequences

**Where A is worse.** The app can load any library placed inside its bundle. For an unsigned
distribution this changes little — anyone who can write into the bundle can also re-sign it ad hoc
— but under a Developer ID it would matter, which is why the exception is not granted then.

**Where the proof is weaker than it looks.** **GitHub's macOS runners do not enforce library
validation.** The probe above launches there, unhardened — found when this change's own test failed
on CI for exactly that reason, which is the only reason it is known. Two consequences, and they are
the ones to remember:

- A release-time launch **could not have caught build 202**, and cannot catch the next defect of
  this kind. The app would have started on the runner and still died on every Mac. The launch is
  kept because it catches everything else a release can be broken by; what catches *this* is the
  entitlement assertion, which is static and the same on every host.
- The gate's test discriminates only where library validation is enforced — the maintainer's Mac, and
  anyone else's. On a host without it, it says so in its own output and reports only the
  entitlement half as proved. It never reports a proof it did not make.
- That launch installs nothing: REQ-034 keeps a smoke run from checking for updates
  (`onlyAKeyedBuildOutsideVerificationUpdatesItself`).
- Not yet observed: a published release that a person has installed and opened.

## Confirmation

**Proof.**

- The defect, from source: a Release build with the release path's own flags, launched, dies in
  dyld with the message above. The same bundle after `Scripts/adhoc-harden.sh` starts and passes
  the smoke assertions (64 records, 5 host updates).
- `Scripts/test-adhoc-harden.sh`, run by the gate: it builds the smallest bundle that can show the
  defect — an ad hoc app, hardened runtime, loading a dylib from its own `Contents/Frameworks` —
  and requires that bundle to **fail** to launch before `Scripts/adhoc-harden.sh` touches it, and
  to run after. Mutations turn it red: dropping the exception (the app stays unable to launch) and
  keeping `get-task-allow`. It also requires the script to refuse an app whose entitlements are
  not the ones Xcode generates, rather than re-sign it with fewer.
- `Scripts/release.sh` refuses to publish unless the signed bundle carries the exception, does not
  carry `get-task-allow`, and passes `SMOKE_APP=… Scripts/smoke-test.sh` — a launch of the bundle
  that is about to be published, asserted on by REQ-098's verifier, whose own discrimination
  `Scripts/test-verify-smoke-log.sh` proves in the gate.

## Retirement proof

A Developer ID signature, under which the exception is not granted and library validation returns by itself.

## Reversal plan

Drop `Scripts/adhoc-harden.sh` once releases are signed with a Developer ID, where library validation works unmodified.
