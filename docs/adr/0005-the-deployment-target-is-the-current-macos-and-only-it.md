# 0005. The deployment target is the current macOS, and only it

- Status: accepted
- Date: 2026-08-22

## Context and problem

**Why it is defensible.** The app has no users yet, so there is no installed base to strand. The
editor is built on TextKit, `NSDocument`, and the system appearance and accessibility APIs, and
every back-release lowers the floor for all of them at once: availability guards, a second
appearance path, and a second set of typography measurements. vision.md ranks "one obvious path"
and "ride the platform" above reach.

## Decision drivers

The criteria are those stated under Considered options.

## Considered options

### macOS 27 only (chosen)

- Good: one appearance path, one typography baseline, no availability guards.
- Bad: nobody on an earlier macOS can run it.

### Support earlier releases

- Bad: availability audit, a second measured typography baseline, a CI matrix.

## Decision

**Decision.** `MACOSX_DEPLOYMENT_TARGET = 27.0`. The application does not run on any earlier
release. Recorded because it was never written down, and a large audience decision that exists
only as a build setting is exactly what this file is for.

## Consequences

As stated above.

## Confirmation

`MACOSX_DEPLOYMENT_TARGET = 27.0` in `Markdown Editor.xcodeproj/project.pbxproj`; the appcast states the same minimum (`Scripts/appcast.sh`).

## Retirement proof

**What would change it.** The first request from someone who cannot run it. Lowering the floor is
a real increment — availability audit, a second measured typography baseline, and a CI matrix
that does not exist yet — not a build-setting edit, and it should not be done casually because
one person asked.

## Reversal plan

An increment: lower the target, audit availability, measure a second typography baseline, add a CI runner for the older release.
