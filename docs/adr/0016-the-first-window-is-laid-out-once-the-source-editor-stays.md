# 0016. The first window is laid out once; the Source editor stays eager

- Status: accepted
- Date: 2026-11-27

## Context and problem

**Measured, on a warm runner launch** (repeat-smoke 45923942236, `spindump`, 10 ms samples):
`makeWindowControllers` took 24–28 samples. About 10 were `NSWindow(contentViewController:)`
laying out the tree. About 8 were `setContentSize` laying it out again at 720×560, the cost
removed here. About 5 were our two editors (`EditorHostView.makeNSView`), most of that in AppKit's
one-time set-up of the text-input cursor and the spell checker, which whichever editor comes first
pays.

## Decision drivers

**Criteria** (vision.md's evaluation section): correctness under mode switching first, ownership
clarity, then measured performance and cost.

## Considered options

| Option | Correctness | Saves | Cost |
| --- | --- | --- | --- |
| **Create the window at its final size (chosen)** | ✓ no behaviour changes | ~8 samples, a whole layout pass | one line |
| Also build Source lazily | ~ REQ-052's persistent editors, REQ-086's restoration and COR-93's hidden-layout scroll fix all assume both exist | ~1–2 samples, since the AppKit set-up moves to the other editor | a new lifecycle state in `EditorHost` |
| Do nothing | ✓ | 0 | 0 |

## Decision

**Decision.** The document window is created at its final size, so it is laid out once instead of
twice. The Source editor is still built with the window, not on first use.

## Consequences

**Where it is worse.** A returning user's saved window frame still costs one resize, because
AppKit restores it after the window exists. And none of this is measured on a real Mac.

## Confirmation

`theDocumentWindowIsCreatedAtItsFinalSize` proves the window is created at its final size.

## Retirement proof

A profile on a real Mac showing the eager Source editor as a material share of opening a window.

## Reversal plan

Create the window at the old default size; one line.
