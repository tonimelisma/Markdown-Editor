# 0023. Saves write in the background, from bytes taken as the save begins

- Status: accepted
- Date: 2026-11-27

## Context and problem

**Why.** Two probes timed the tour's documents minute by minute. Every autosave was a save record of
133–413 ms and a main-actor stall of the same size, which the person feels as typing that freezes
(probes 45979646302, 45980923448). The serialized write held the main thread for file coordination,
version preservation and the write itself. §9 had kept serialized writes "unless a future measured
platform requirement proves it necessary"; this is that measurement.

## Decision drivers

**Criteria:** the person's typing never waits on the disk (vision.md: responsiveness); the document's
state stays the main actor's (ARC-011); every save still writes exactly the text it was asked to;
cost.

## Considered options

| Option | Typing during a save | ARC-011 | Exact bytes | Cost |
| --- | --- | --- | --- | --- |
| **Async write from a snapshot taken at save (chosen)** | ✓ held only while bytes are encoded | ✓ background reads an immutable value | ✓ the text as the save began | small |
| Autosave less often | ✗ still freezes, less often | ✓ | ✓ | none, and more work at risk |
| A long-lived mirrored text for writers | ✓ | ✗ a second source of truth | ~ mirror can lag | large |
| Do nothing | ✗ 0.1–0.4 s freeze per autosave | ✓ | ✓ | none |

## Decision

**Decision.** `MarkdownDocument` returns true from `canAsynchronouslyWrite` for every save.
`save(to:ofType:for:completionHandler:)` takes the bytes on the main actor before AppKit starts and
keeps them until the next save. On the background thread, `writeSafely` calls
`unblockUserInteraction()` and `data(ofType:)` returns the bytes.
architecture.md §9 states the contract.

## Consequences

**Amended the same day.** Saving a moment after typing hung the app. The cause was not the
background write: ending the typing group makes AppKit count the change in an activity queued on
the main queue, and a save started in the same turn waited for it with the main thread held
(probe 45999625665). A File command that ends a typing group now starts on the next turn.

**Where it is worse.** A background write that arrives with no snapshot fails instead of reading
the document; no path in AppKit was seen to do that, and the failure is a save error, not a wrong
file. Encoding the bytes still happens on the main actor, which is linear in the document's size.

## Confirmation

`AcceptedEditTransactionTests` prove `canAsynchronouslyWrite` and that the background write reads the snapshot taken as the save began.

## Retirement proof

A save path where encoding the bytes on the main actor is itself measured as a typing stall.

## Reversal plan

Return false from `canAsynchronouslyWrite`; autosaves freeze typing again.
