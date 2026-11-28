# 0009. Mode scroll state is an offset from the top of the document (COR-93)

- Status: accepted
- Date: 2026-08-30

## Context and problem

**What it fixed.** The first switch into Source mode opened halfway down the file. The screenshot
gallery caught it — the Source scene photographed a document starting mid-table — and nothing
else had, because every piece of state involved was reporting the truth: the session held
`.zero`, the clip view's bounds origin was `0`, and the restore did exactly what it was told.
AppKit had parked the Source text view at `documentView.frame.origin.y == -1044` inside an
861-point clip over a 2122-point document, so bounds origin `0` meant *1044 points into the
file*. The Source editor is laid out while hidden, which is why it and not WYSIWYG.

**Measured, not reasoned.** Three candidate explanations were tested against the running app with
temporary probes and all three were wrong: the string is installed at construction (not lazily on
first switch), `NSScrollView.tile()` after forcing text layout does not reset the placement, and
neither does laying out the clip view. The probe that settled it printed the document view's own
frame origin, which no amount of reading the code would have produced.

## Decision drivers

- Recorded state must mean the same thing in both editors.
- Correctness must not depend on undocumented AppKit placement.

## Considered options

**Alternatives.** (A) Store offsets document-relative — chosen; one conversion, both editors, and
"zero means the top" becomes true by construction. (B) Special-case Source with a scroll-to-top on
first entry: hides the defect while leaving every recorded offset in a coordinate space that lies,
so the second switch would be wrong instead of the first. (C) Fight AppKit's placement until the
document view sits at zero — two attempts failed, and it makes correctness depend on undocumented
placement behaviour rather than on measuring it.

## Decision

**Decision.** `SourceModeState.scrollOffset` and `WYSIWYGModeState.scrollOffset` are offsets from
the top of the document, not raw `NSClipView` bounds origins. `EditorHostView.HostCoordinator`
owns the only conversion, in `scrollOffset(in:)` and `restoreScrollOffset(_:in:)`.

## Consequences

**Where the chosen option is worse.** It puts a coordinate conversion between the session and
AppKit, so a future reader of `scrollOffset` must know it is not a clip-bounds origin. That is
what the architecture.md §12 paragraph and the comment on the helpers are for. The alternative — a
raw AppKit coordinate whose meaning depends on where AppKit happened to put a view — is the one
that already cost a defect nobody could see in the state.

## Confirmation

`SourceModeScrollTests` restore a document-relative offset into a Source editor laid out while hidden.

## Retirement proof

AppKit placing a hidden text view's document view at the clip's origin, documented and measured.

## Reversal plan

Store raw clip-bounds origins again; the first-switch defect returns.
