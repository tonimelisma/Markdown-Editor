# 0020. Unsaved typing is edited before AppKit counts it; undo groups end outside AppKit's activities

- Status: accepted
- Date: 2026-11-27

## Context and problem

**Why.** The tour found two defects with one cause.

- Typing stays in one open undo group, and AppKit counts a change only when a group closes.
  After a sentence typed since the last save, the document read as clean, and another app's write
  was adopted over the sentence.
- Closing a window after typing ended that group inside NSDocument's close activity. The
  resulting change-count update waited on the activity itself, and the app hung for good. A
  sample of the hung process showed the cycle.

## Decision drivers

**Criteria:** preservation of the person's work above all (vision.md's first objective); behaving as
a Mac document does (Edited, the close prompt, undo to the saved point); cost.

## Considered options

| Option | Work preserved | Mac document behaviour | Cost |
| --- | --- | --- | --- |
| **Open typing group counts as edited; end it only outside activities (chosen)** | ✓ | ✓ undo to the saved point still clears Edited | small |
| Mark edited by revision: any revision but the file's | ✓ | ✗ undo back to the saved text stays Edited | small |
| Group typing by event, as AppKit does by default | ✓ | ✓ | the undo history's shape changes for every edit route |
| Do nothing | ✗ data loss, a hang | — | none |

## Decision

**Decision.** A document is edited when AppKit says so, or while a typing undo group holds edits.
The typing group is ended at the entry of Save, Save As and a close's review (`canClose`, which
⌘W, the close button and Quit all reach), each of which then starts a main-queue turn later. The
close itself and load drop it without ending it. architecture.md §10 states both rules.

Quit was added after tour 46011070302: quitting 0.7 s after typing reached the review with the
group open, the review's sheet ended it inside AppKit's activity, and the app hung as the close
had.

## Consequences

**Where it is worse.** Autosave does not end the typing group, which a deadlock risk inside its
activity rules out. After an autosave during typing, Edited can linger until the group closes.
That costs nothing but a prompt.

## Confirmation

`SourceIntegrityCharacterizationTests` and `DocumentLifecycleContractTests` cover the open typing group counting as edited and the group ending outside AppKit's activities.

## Retirement proof

AppKit counting an open undo group as a change, or ending it safely inside its activities.

## Reversal plan

Let AppKit group typing by event, which changes the undo history's shape on every edit route.
