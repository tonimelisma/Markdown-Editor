# ADR-0004 — Direct distribution (Developer ID + notarization); App Sandbox off for now

- **Status:** Accepted
- **Date:** 2026-07-21
- **Deciders:** Toni Melisma
- **Related:** [VISION §8](../VISION.md); `Markdown Editor.xcodeproj` build settings

## Context

A macOS app can ship via the **Mac App Store** (mandatory App Sandbox, Apple review + payments,
a revenue cut) or via **direct download** (Developer ID signature + Apple notarization, self-
managed updates). App Sandbox adds real file-access friction during development (security-scoped
bookmarks, entitlements) that we do not want to fight while building the core editor.

## Decision

**Direct download only**, signed with a **Developer ID** and **notarized** by Apple. **App
Sandbox is disabled** for now (`ENABLE_APP_SANDBOX = NO` in Debug and Release); hardened runtime
stays **on** (required for notarization). App Sandbox can be re-adopted later if we ever choose
to target the Mac App Store.

## Consequences

- **Positive:** no sandbox file-access friction during development; full flexibility over
  updates and distribution; notarization still gives Gatekeeper trust.
- **Negative / costs:** not App Store-distributable as-is; we own update/notarization plumbing;
  re-adding the sandbox later means revisiting file access with security-scoped bookmarks.
- **Follow-ups:** notarization/signing pipeline is a later increment; a future "App Store" ADR
  would supersede the sandbox part of this one.

## Alternatives considered

- **Mac App Store (sandbox-first):** rejected for now — sandbox friction; store cut; review
  latency.
- **Sandbox on, direct download:** rejected — the friction without the App Store benefit.
