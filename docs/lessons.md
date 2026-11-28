# Lessons

Rules learned the hard way that are not obvious from the code, and problems still open. The rules
that govern how tests are written are in `CLAUDE.md` §3; the decisions behind these are in the
ADRs.

## Rules learned

- GitHub's macOS runners do not enforce library validation, so a release-time launch there cannot
  catch an app that dies in dyld on every real Mac; only the static entitlement assertion can.
  Build 202 shipped that way ([ADR 0012](adr/0012-an-ad-hoc-app-needs-the-library-validation-exception-and-a.md)).
- The first launch shortly after a runner boots stalls on a cold, throttled disk (10 of 10), and
  no later launch does; judge stalls on a warm launch
  ([ADR 0014](adr/0014-a-release-launches-its-bundle-twice-the-first-launch-s-stall.md)).
- A docs-only push skipped macOS and still released the tree an earlier, unbuilt `main` commit
  had changed; CI now asks whether the app differs from the newest release
  ([ADR 0014](adr/0014-a-release-launches-its-bundle-twice-the-first-launch-s-stall.md)).
- `-AppleInterfaceStyle Light` is a no-op; `-NSRequiresAquaSystemAppearance YES` forces light
  ([ADR 0008](adr/0008-the-product-is-photographed-by-naming-a-screen-at-launch-not.md)).
- Recording all cancelled work as a fault, and then allowing orphans wholesale, hid a double parse
  on every open ([ADR 0018](adr/0018-replaced-work-is-superseded-not-orphaned.md)).
- Ending a typing undo group inside one of AppKit's document activities deadlocks; end it on the
  next main-queue turn ([ADR 0020](adr/0020-unsaved-typing-is-edited-before-appkit-counts-it-undo-groups.md)).
- A hidden Source editor's document view sits off the clip's origin, so raw clip-bounds offsets
  lie; store document-relative offsets
  ([ADR 0009](adr/0009-mode-scroll-state-is-an-offset-from-the-top-of-the-document.md)).

## Open problems

- The first window's cost has never been measured on a real Mac (#111).
- CI against the five-minute budget with a warm cache, and Mac runners that are never assigned
  (#112).
