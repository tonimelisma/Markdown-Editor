# 0015. No Apple Developer account: releases are ad hoc, for good

- Status: accepted
- Date: 2026-11-27

## Context and problem

**Why delete rather than keep the option.** That code was never exercised. Nothing tested it, and
it would rot until the day it was needed, which will not come. Git keeps it
(`release.sh` before this change) if that changes. Adding a certificate later would not break
updates: Sparkle checks the EdDSA key, not the signing identity.

## Decision drivers

- The maintainer will not pay for an Apple Developer account.
- Code that is never exercised rots.

## Considered options

### Keep the Developer ID and notarization paths, unused

- Bad: untested code waiting for a day that will not come.

### Ad hoc signing only (chosen)

- Good: one path, exercised by every release.
- Bad: a first install needs Open Anyway.

## Decision

**Decision.** There will be no Apple Developer account. Every release is signed ad hoc and is not notarized. The certificate and notarization
paths that waited for one are gone: `CERTIFICATE_P12`, `CERTIFICATE_PASSWORD` and the `NOTARY_*`
secrets, the keychain step in `release.yml`, and the Developer ID branches in `release.sh`.

## Consequences

**What it costs.** A first install needs **System Settings → Privacy & Security → Open Anyway**
once. Updates never do, because Sparkle installs them without the quarantine flag. The app keeps
the hardened runtime, minus library validation (`Scripts/adhoc-harden.sh`, 2026-11-26). vision.md's
Distribution section no longer promises a notarized download.

## Confirmation

`Scripts/release.sh` signs ad hoc and asserts the entitlements `Scripts/adhoc-harden.sh` sets; the release workflow holds no certificate or notary secret.

## Retirement proof

A Developer ID account.

## Reversal plan

Add the certificate and notarization steps back from Git history; Sparkle checks the EdDSA key, not the signing identity, so updates keep working.
