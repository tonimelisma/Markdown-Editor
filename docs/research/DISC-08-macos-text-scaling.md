# DISC-08 — Does AppKit's Dynamic Type route reach this app's editor content?

- **Authority:** Evidence only — not architecture, not authorization. Current architecture is in `../ENGINEERING.md`; behavior in `../REQUIREMENTS.md`. Motivates `COR-64`.
- **First researched:** 2026-08-11
- **Last verified:** 2026-08-11
- **Environment:** macOS 27.0 (project `MACOSX_DEPLOYMENT_TARGET`), Swift 6, AppKit (no Catalyst).
- **Refresh when:** Apple documents an observable notification or property for Accessibility Text Size in a future AppKit release, or extends `preferredFont(forTextStyle:)` to update live for third-party apps; the project's `MACOSX_DEPLOYMENT_TARGET` moves to a macOS version whose release notes mention Accessibility Text Size or Dynamic Type changes for AppKit; or a future increment introduces user-selectable typography (Post-MVP backlog) and needs this finding re-verified first.
- **Method:** documentation and developer-forum review of `NSFont.preferredFont(forTextStyle:)`,
  `NSFont.TextStyle`, and the System Settings ▸ Accessibility ▸ Display ▸ Text Size control shipped
  since macOS Sequoia 15.1. No POC was built: the question is "does a public, documented route
  exist and is it reliable," which the platform's own documentation and Apple Developer Forum
  reports already answer without writing throwaway code. `CLAUDE.md`'s Stage-0-POC path is for
  questions only an experiment can answer; this one is answered by reading.

## Question

`VISION.md` fixes WYSIWYG typography at an approved default (15-pt system body, ~1.35× line
height). `ENGINEERING.md` §7 makes that default a proven constant. Neither document says whether a
user who needs larger text has any route to get it. iOS/iPadOS Dynamic Type is the platform's
answer to that question there; does an AppKit equivalent exist for a custom `NSTextView`-based
editor on macOS 27?

## Findings

1. macOS Sequoia 15.1 (2024) added **Accessibility ▸ Display ▸ Text Size**, a system-wide slider
   comparable in appearance to iOS's Dynamic Type setting, still present in macOS 27. It is a real,
   user-facing preference.
2. `NSFont.preferredFont(forTextStyle:options:)` exists in AppKit and returns a font for a named
   `NSFont.TextStyle` (`.body`, `.title1`, …), mirroring the UIKit API of the same name.
3. Multiple independent Apple Developer Forum threads (2024–2025) report that fonts returned by
   `NSFont.preferredFont(forTextStyle:)` **do not reflect the Accessibility Text Size setting and
   do not update when the setting changes** for ordinary third-party AppKit apps. No push
   notification (`NSNotification.Name` for a text-size change) is documented for AppKit outside the
   small first-party surface below.
4. Apple's own adoption is narrow and platform-owned: Finder, Mail, and the sidebar/source-list
   chrome of some first-party apps honor the setting. This is consistent with the setting being
   wired into specific system controls (`NSOutlineView` sidebar style, Finder's list view) rather
   than exposed as a general AppKit content-scaling contract third-party code can opt into.
5. No documented API gives a third-party app a way to **observe** the current Text Size value or a
   **change notification** for it. Without either, a custom `NSTextView` cannot honor the setting
   even if it wanted to: there is nothing to read and nothing to react to.
6. This differs in kind from Light/Dark appearance (`NSApplication.effectiveAppearance`, documented,
   observable, and already correctly adopted per `ARC-Q14`) and from Increase Contrast/Reduce
   Motion/Reduce Transparency (§ below, all exposed via documented, observable
   `NSWorkspace.shared.accessibilityDisplay*` properties). Text Size is the one system accessibility
   display setting in this family with no third-party read API as of this research date.

## Recommendation

Do not adopt `NSFont.preferredFont(forTextStyle:)` for editor body/heading fonts: it would read as
support for a setting the app cannot actually observe, producing a static font chosen once at
launch that silently stops matching the system setting — an unverifiable claim of exactly the shape
`CLAUDE.md` §4 already forbids ("a proof asserting an attribute value does not discharge a
requirement about what the user sees" generalizes to "an API call does not discharge a requirement
about what the user sees" when the call is not reliably observed to do anything). The honest
position is: macOS provides no general third-party route to this preference today. Record the gap
against `REQ-032`(accessibility) as a documented, guarded boundary (`COR-64`) rather than leaving it
undiscovered, and leave *user-selectable typography options* — a different, already-approved
backlog idea in `ROADMAP.md`'s Post-MVP backlog — as the product's own lever if the user later
wants in-app control independent of this OS limitation.

## Refresh triggers

- Apple documents an observable notification or property for Accessibility Text Size in a future
  AppKit release, or extends `preferredFont(forTextStyle:)` to update live for third-party apps —
  refresh in full and re-open the `COR-64` question as a build increment rather than a documented
  boundary.
- The project's `MACOSX_DEPLOYMENT_TARGET` moves to a macOS version whose release notes mention
  Accessibility Text Size or Dynamic Type changes for AppKit.
- A future increment introduces user-selectable typography (Post-MVP backlog): re-verify this
  finding before assuming the OS side is still closed.

Sources:
- [NSFont.TextStyle — Apple Developer Documentation](https://developer.apple.com/documentation/appkit/nsfont/textstyle)
- [NSFont.TextStyleOptionKey — Apple Developer Documentation](https://developer.apple.com/documentation/appkit/nsfont/textstyleoptionkey)
- [How do you support Preferred Font Size / Dynamic Type on macOS? — Apple Developer Forums](https://developer.apple.com/forums/thread/818858)
- [Dynamic font size for NSTextField on macOS — Apple Developer Forums](https://developer.apple.com/forums/thread/743557)
- [Is there a way to opt a Catalyst app into supporting preferred text size? — Apple Developer Forums](https://developer.apple.com/forums/thread/767622)
