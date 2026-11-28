# 0017. An agent drives the app on a Mac runner, to look; tests still prove

- Status: accepted
- Date: 2026-11-27

## Context and problem

**What the runner allows** (UI probe, PR #97, run 45942394078, macOS 27.0.1 on `xcode-27`):

- SIP is disabled.
- `/bin/bash` holds Accessibility, AppleEvents and ScreenCapture grants in the system TCC
  database, and `AXIsProcessTrusted()` is true for a tool the job runs.
- The app's accessibility tree is complete: 210 elements, including the toolbar, the text area's
  value, task checkboxes, images and the whole menu bar.
- An accessibility press on the Source segment switched the mode (`modeToggle` in the app's log).
- A real ⌘S key event saved the document (`documentSaveSucceeded`).
- Typed text went nowhere, because nothing had keyboard focus.
- System Events' `keystroke` did nothing either.
- The display is 1×, so a screenshot pixel is a window point.

**What it found, in its first morning.** None of these was caught by the test suite, which drives
the editor through harnesses that set the selection before every keystroke and call the planners
directly:

| Found | Run | Cause | Now proved by |
| --- | --- | --- | --- |
| Pressing Source switched the editor and left WYSIWYG selected | probe 45942394078 | the toolbar followed `session.mode` from a `$mode` sink, which runs in `willSet` | `theModeControlFollowsTheMode` |
| Typing in WYSIWYG stopped after one character | 45943545906, 45944610103 | a recovery dropped the selection, and the keystroke guard compared AppKit's affinity with the owner's | `aRecoveryKeepsTheCaret`; `typingAtTheStartOfAHeadingContinues` |
| A keystroke at the start of a heading or other block was recovered as a COR-71 fault | 45943545906 | the parser-free transition shifts runs and blocks by projection position only | `aKeystrokeAtAnyOffsetIsReconciledWithoutRecovery` |
| Every keystroke before a soft line break was recovered | 45945859891; CI on 2625fc4 | cmark gives breaks no source position, and their insertion fell back to 0 | `lineBreaksInsertWhereTheirLineEnds`; `typingAWordIntoTheRichFixtureIsReconciledWithoutRecovery` |
| The View and Format menus were disabled and every formatting shortcut did nothing | 45944610103, 45945859891 | document windows are AppKit windows, and the menu's `@FocusedValue` never reached them; once it did, `.disabled` was decided once, before the first parse | `theMenuReachesTheKeyDocumentWindowsCommands`; `theMenuFollowsAvailabilityAfterItWasBuilt` |
| Sixteen of nineteen approved shortcuts were on no menu item | reading the code the menu failure led to | hand-written buttons, three of which called the function that attaches shortcuts | the menu is built from one table through one function |
| After an edit in WYSIWYG, Source mode drew every paragraph in the heading's font | 45945859891 | a whole-text replacement kept the highlighter's line cache | `everyLineIsRestyledAfterTheTextChangedElsewhere` |

Run 45949097608 is the first in which every expectation of the default scenario held: a word
typed at the start of a heading, toolbar bold, cmd-I, cmd-S, Source from the toolbar, WYSIWYG
from the View menu, Source from ctrl-cmd-2.

## Decision drivers

**Criteria** (vision.md's evaluation section): automated verification must stay trustworthy, which is
what §4 protects; correctness under mode switching, because the bug above lived where AppKit,
Combine and the session meet, and no unit test was looking there; ownership clarity and absence
of duplicate paths; and cost.

## Considered options

**Alternatives.**

- **An on-demand instrument for an agent's eyes, outside the gate (chosen).** Nothing in the
  product changes and no test depends on it. A cloud session gains the one thing it lacked:
  seeing what the app does when someone uses it. Each run costs about three minutes of a
  macOS runner.
- **An XCUITest target in the gate.** Rejected. It is the flaky, slow kind of proof §4 removed:
  timing-dependent, at the mercy of the runner's TCC state, and over the five-minute budget. A
  red UI test would block a merge for reasons that are not the change's.
- **Claude Code with computer use, running on the runner.** Rejected for now. It needs an API-key
  secret and would be a second agent, whose work this session sees only through its report.
  The eyes are the same, screenshots and the accessibility tree, and a scenario the session
  writes and reads back itself costs less and can be repeated exactly.
- **An in-app scenario driver, named at launch like `MARKDOWN_EDITOR_SMOKE_SCENE`.** Rejected. It
  would be a second path into the command model, which the 2026-08-29 decision refused. It also
  could not show what real input does, which is where the bug above was.
- **Do nothing.** The cloud session keeps seeing one passive screenshot per CI run. The toolbar
  bug stays invisible.

## Decision

**Decision.** `.github/workflows/agent-drive.yml` lets an agent in a cloud session operate the
real app on a GitHub Mac runner. The agent writes a scenario of real clicks, real keys, menu
choices and accessibility presses (`Scripts/agent-drive.swift`) and dispatches it. Afterwards it
downloads a screenshot, accessibility tree, element value or saved file for each step, plus the
app's diagnostic log, and looks at them. CLAUDE.md §4 gains it as its one exception that drives
the UI. It is never a gate and never a requirement's proof. A defect it finds is fixed with a unit
or component test that fails for it.

## Consequences

**Where the chosen option is worse.** Its findings are only as good as the scenario and the
agent's looking. A run that "looked fine" proves nothing, which is why it can never be cited as
a proof. A scenario also cannot reach what the runner's TCC grants do not allow.

## Confirmation

Nothing requires `agent-drive.yml`; each defect it found is proved by the unit or component test named in the table above. A weekly scheduled tour keeps the driver and the app honest with each other.

## Retirement proof

A UI-test mechanism that is deterministic and inside the five-minute budget, which would let a scenario become a proof.

## Reversal plan

Delete `agent-drive.yml`, `Scripts/agent-drive.swift` and `Scripts/agent-drive/`; nothing else depends on them.
