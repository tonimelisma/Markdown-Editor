# 0022. File › Revert Document asks AppKit to revert; there is no Revert To submenu

- Status: accepted
- Date: 2026-11-27

## Context and problem

**Why.** AppKit builds Revert To from items it tells apart by private menu-item tags, and every
item sent without one opens the browser. The tour chose Last Saved Version and got the browser
(tour 45979207044). The menu is SwiftUI's, so AppKit's own submenu is not there to borrow.

## Decision drivers

**Criteria:** behaving as a Mac document does; preserving the person's work; relying only on
documented API.

## Considered options

| Option | Mac behaviour | Work preserved | Documented |
| --- | --- | --- | --- |
| **Revert Document…, the browser (chosen)** | ✓ Apple's documented route; the last saved version is on the right | ✓ the current text becomes a version | ✓ |
| Revert To with guessed private tags | ✓ when the guess is right | ✓ | ✗ breaks silently |
| Our own Last Saved Version, from text kept at each save | ~ one step quicker | ~ bypasses the version AppKit keeps of the current text | ✓, but a second revert path |
| Do nothing (the submenu as it was) | ✗ the title lies | ✓ | ✓ |

## Decision

**Decision.** The File menu offers Revert Document…, which sends `revertDocumentToSaved:`. For an
edited document AppKit asks whether to go back to the last saved version or browse older ones; for
one with no unsaved changes it opens the Versions browser. The menu has no Revert To submenu.

## Consequences

**Amended the same day.** Revert Document first opened the browser even after typing, because the
open typing group was not yet a change AppKit knew of. Once File commands counted the typing first,
AppKit offered Last Saved Version as well (tour 46000331975), which is what the submenu was for.

**Where it is worse.** Going back to the last save takes two steps, Revert Document… then Restore,
not one.

## Confirmation

`MarkdownDocumentTests` prove File › Revert Document sends `revertDocumentToSaved:`.

## Retirement proof

A documented way to build AppKit's Revert To items from a SwiftUI menu.

## Reversal plan

Add the submenu back once its items can be built from documented API.
