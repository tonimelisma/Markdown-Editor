# COR-53 — macOS citizenship: window frame, Print, shortcuts, list continuation

- **Status:** Approved; not implemented
- **Requirements:** REQ-014 (standard document behaviour — gains Print), REQ-020 (tabs — moves from `inherent` to `test`), REQ-058 and REQ-108 (command surface — extended); new REQ-130 (Return continues and ends a list), REQ-131 (window frame restored, documents cascade)
- **Delivers:** REQ-130, REQ-131
- **ARC invariants:** ARC-024 (one window-scoped command model) unchanged and reused — list continuation routes through it rather than becoming a second path. No architecture change.

## Context

Gaps between this app and one that shipped with the OS, all found in the August review:

- `MarkdownDocument.makeWindowControllers` builds a bare `NSWindow`, sets a fixed content size, and
  calls `window.center()`. There is no `windowFrameAutosaveName` and no `shouldCascadeWindows`, so the
  app forgets its window size on every launch and two documents open exactly on top of each other.
  REQ-020's tab claim is `inherent` and, with a hand-constructed window and no tabbing identifier,
  untested.
- There is no Print and no Page Setup anywhere. TextEdit prints. For this app printing is close to
  free — the visible `NSTextView` already holds a laid-out attributed document.
- `EditorMenuCommands.shortcuts` declares exactly three shortcuts. Headings have none, though `⌘1`–`⌘6`
  is the convention in Pages, Notes, Bear, Obsidian and iA Writer. Lists, quote, code block and mode
  switching have none.
- Return does not continue a list. `keyDown` and `doCommand(by:)` both intercept Return, and only to
  toggle a task checkbox — and because `keyDown` returns first, the `doCommand` branch is unreachable
  for a real key press. Every Markdown editor and every rich-text editor macOS ships continues lists.
- At the product's own default 720 pt width, the toolbar hides strikethrough, inline code, all four
  list commands, quote, code block and Add Image behind the overflow chevron. `ENGINEERING.md` §8's
  "never compresses labels" is honoured; the outcome is that most formatting commands are invisible.
- `Add Image…` sits in the Format menu — an insertion command in a formatting menu.
- `⌘K` with no selection is disabled, where every other editor inserts a link and places the caret in
  the label.

## Phase 0 — POC: two decisions to measure rather than argue

### D1 — Print scope

Build both and look at the output.

| Observation | Action |
| --- | --- |
| Printing the **current mode** produces sensible output in both modes | adopt it — what you see is what prints, and there is no second render path to keep in agreement with the first |
| Source-mode printing is unusable (no page breaks, clipped measure) | always print the rendered document, and record why |

### D2 — Toolbar width

Extend `EditorToolbarConstructionTests` to sum `NSToolbarItem.minSize` across
`EditorMenuCommands.commandOrder` and report the width at which nothing overflows.

| Observation | Action |
| --- | --- |
| Required width ≤ 900 pt | widen the default content width to that value and keep every command visible |
| Required width > 900 pt | keep 720 pt and move the six least-used commands into the Paragraph popup; record which six and the basis for "least used" |

**Then, without stopping:** write `docs/research/DISC-07-print-and-toolbar.md` (evidence-only
authority, dates, method, measurements, decisions applied), delete the POC, rewrite Phases 1 and 5,
commit, and continue.

Note that the reading measure (720 pt) and the window width are different facts. The window does not
have to equal the measure; it has to hold the app's own chrome.

## Phase 1 — window frame memory and cascading

```swift
let controller = NSWindowController(window: window)
controller.shouldCascadeWindows = true
if !MarkdownAppDelegate.isSmokeRun {
    controller.windowFrameAutosaveName = "MarkdownDocumentWindow"
}
window.tabbingIdentifier = "MarkdownDocument"
window.tabbingMode = .preferred
```

`setContentSize` remains the first-launch default; autosave restores over it afterwards. The smoke
guard exists because a verification run must never inherit or write the user's real window frame — the
same class of mistake `Markdown_EditorApp`'s `ApplePersistenceIgnoreState` comment already records
about writing to the persistent defaults domain.

## Phase 2 — Print

```swift
CommandGroup(replacing: .printItem) {
    Button("Page Setup…") { NSApp.sendAction(#selector(NSDocument.runPageLayout(_:)), to: nil, from: nil) }
        .keyboardShortcut("P", modifiers: [.command, .shift])
    Button("Print…") { NSApp.sendAction(#selector(NSDocument.printDocument(_:)), to: nil, from: nil) }
        .keyboardShortcut("p")
}
```

```swift
/// Prints what is on screen. The visible editor already holds a laid-out attributed document, so
/// there is no second render path to keep in agreement with the first.
override func printOperation(withSettings settings: [NSPrintInfo.AttributeKey: Any]) throws
    -> NSPrintOperation
```

Resolve the printed view from the window controller's `HostCoordinator`, configure `NSPrintInfo`
margins, and return `NSPrintOperation(view:printInfo:)`.

## Phase 3 — shortcuts

Change `EditorMenuCommands.shortcuts` to `[EditorCommand: KeyboardShortcut]` so modifiers are
expressible, and **iterate the table rather than indexing it**, which deletes the three
`Self.shortcuts[...]!` force-unwraps at `:50`, `:53` and `:60`.

| Command | Shortcut | Command | Shortcut |
| --- | --- | --- | --- |
| `.paragraph` | `⌘0` | `.blockQuote` | `⌃⌘Q` |
| `.heading(1…6)` | `⌘1`–`⌘6` | `.inlineCode` | `⌃⌘C` |
| `.unorderedList` | `⇧⌘7` | `.codeBlock` | `⇧⌃⌘C` |
| `.orderedList` | `⇧⌘8` | `.strikethrough` | `⇧⌘X` |
| `.taskList` | `⇧⌘9` | `.wysiwygMode` / `.sourceMode` | `⌃⌘1` / `⌃⌘2` |

## Phase 4 — Return continues a list

Collapse the two redundant Return interceptions into one `doCommand(by:)` route; the `keyDown`
keyCode 36/76 branch is deleted, since it shadows the `doCommand` path today.

Add `SemanticCommand.continueList` with a `ListEditPlanner` case:

- caret at the end of a **non-empty** item → insert `"\n"` plus the item's own marker spelling, taken
  from COR-50's `source` field, with an ordered marker incremented;
- caret at the end of an **empty** item → remove the marker, leaving an empty paragraph — the
  universal "Return twice ends the list";
- caret anywhere else → not this command; ordinary newline insertion.

```swift
/// Return inside a list item is a *semantic command*, not literal typing: it routes through the same
/// window-scoped controller as the toolbar (ARC-024), so it inherits validation, refusal and undo
/// grouping instead of growing three new copies of them.
```

Adding `.continueList` to `EditorCommand` makes `CommandLivenessMatrixTests` — the closed matrix —
fail until its behaviour in both modes is declared. That is the proof mechanism, chosen deliberately
rather than added afterwards.

**Depends on COR-50** for the marker source spelling.

## Phase 5 — toolbar width, Insert menu, and ⌘K

Apply D2. Add `CommandMenu("Insert")` holding `Add Image…`; Format keeps formatting.

`.editLink` becomes enabled with a zero-length selection; `commitLink` inserts `[](destination)` and
requests selection restoration inside the brackets — the shape `MarkdownSourceTextView.insertImageMarkdown`
already uses for REQ-073's empty description.

## Proof

- `windowControllerRestoresItsAutosavedFrame`, `documentWindowsShareATabbingIdentifier`,
  `smokeRunDoesNotPersistAWindowFrame`. REQ-020 moves from `inherent` to `test`.
- `printOperationUsesTheVisibleEditorsLaidOutContent` — assert the operation's view is the visible text
  view and its `NSPrintInfo` is not the zero-margin default. Nothing is printed.
- `noShortcutShadowsAStandardAppKitKeyEquivalent` — checked against `⌘N/O/S/W/P/Q/Z/X/C/V/A/F`,
  `⇧⌘S`, `⇧⌘Z`, `⌘,`. **Rehearsed failing** by adding `⌘S`.
- `everyToolbarCommandFitsTheDefaultWindowWidth`. **Rehearsed failing** at 720 pt.
- `returnAtEndOfListItemContinuesTheList`, `returnOnEmptyListItemEndsTheList`,
  `returnInOrderedListIncrementsTheNumber`, `returnOnATaskItemContinuesWithAnUncheckedBox`,
  `returnInsideAParagraphInsertsAnOrdinaryNewline`.
- `CommandLivenessMatrixTests` covers `.continueList` in both modes — the closed matrix does this
  automatically once the case is added, which is why it is the mechanism.
- `editLinkWithNoSelectionInsertsAnEmptyLabelledLink`.
- `returnInterceptionHasExactlyOneRoute` — a source-conformance test proving the `keyDown` branch is
  gone, so the unreachable-duplicate defect cannot return.

## Instrumentation and performance evidence

`.continueList` records `editRouted` and `mutationCommitted` like any other semantic command, so the
smoke run's structured log covers it with no new event. Confirm no `modeTransition` regression from
the wider default window.

## Failure / rollback

Each phase is independently revertible and none touches the projection or coordinate machinery.

The one behavioural risk is Return interception: if `continueList` misfires, the user cannot insert a
newline, which is severe. The planner therefore returns "not this command" for every case except a
caret at a list item's end, and falls through to ordinary insertion rather than refusing —
`returnInsideAParagraphInsertsAnOrdinaryNewline` is the proof and must be rehearsed failing.

Window autosave carries a smaller risk of restoring an off-screen frame on a display change; AppKit
constrains restored frames to a visible screen, and `window.minSize` is already set.

## Deletion / conformance gate

- The `keyDown` keyCode 36/76 Return branch is deleted, not left unreachable.
- No `Self.shortcuts[...]!` force-unwrap remains.
- `window.center()` is removed in favour of cascade plus autosave — the two are alternative owners of
  the same fact and both must not remain.
- `Scripts/check-documentation-authority.sh`, `Scripts/check-instrumentation-coverage.sh` and
  `Scripts/check-proof-results.sh` pass.
