# COR-49 — Source-mode performance parity

- **Status:** Approved; not implemented
- **Requirements:** REQ-045 (moves to `Correction`, then `Done` with real `test` verification), REQ-040, REQ-051, REQ-090, REQ-123
- **Delivers:** none
- **ARC invariants:** ARC-Q05 extended to the source boundary; ARC-020 (samples honestly named and lifetime-owned) applies to the new metric; ARC-018 (styling never changes source) unchanged and re-proved

## Context

`SourceEditor.Coordinator.apply` (`SourceEditor.swift:151`) runs 120 ms after every keystroke and
does:

```swift
storage.setAttributes(theme.baseAttributes, range: full)                 // whole document
for token in tokens { storage.addAttributes(theme.attributes(for:), range: token.range) }
```

That is an O(document) attributed-string rewrite on the main actor, on a timer, while the user types.
`MarkdownHighlighter.tokens(for:)` regex-scans the whole document off-main to produce the input.

There is no metric, no budget, and no test. Every case in `PerformanceSampler.Metric` is a WYSIWYG
boundary. REQ-045 ("keep typing latency imperceptible") is `Done`, verified by
`computesCountsOffMainActor` — which proves word counting is off-main — plus `inherent`. Neither
covers the full-document restyle.

The app has two genuine editors. One has an eight-metric budget system; the other has nothing.

## Production changes

### 1. New metric — `Markdown Editor/PerformanceSampler.swift`

```swift
/// Main-actor application of lexical source styling: the attributed rewrite only, not the off-main
/// tokenisation that produced it.
case sourceHighlightApplication
```

Budget **8 ms** at p95, added to `PerformanceSampler.budgetNanos`. The same frame-shaped reasoning as
`layoutApplication`: it runs on the main actor while the user is typing. `PerformanceBudgetTests`
fails until the budget is declared, which is the intended forcing function.

Recorded around `apply` in `SourceEditor.Coordinator`.

### 2. Incremental application — `Markdown Editor/SourceEditor.swift`

Accumulate `NSTextStorage.editedRange` across the debounce interval and expand to whole lines:

```swift
/// The union of every line touched since the last applied styling.
///
/// Every block construct the lexical highlighter recognises is line-anchored — headings, fences, list
/// markers, table rows, thematic breaks — so a changed-line window covers all of them except a fence,
/// whose effect is unbounded below it and is handled by the parity check.
private func styleWindow(for editedRange: NSRange, in text: NSString) -> NSRange
```

`apply` restricts both the `setAttributes` reset and the token loop to `styleWindow`.

**Fence safety is the correctness guard, not an optimisation detail.** If the window's count of
fence-opening lines has a different parity from the previous pass, widen to the whole document for
that pass and record `EditorTraceEvent.sourceHighlightWidened(reason: .fenceParity)`. Typing three
backticks changes the styling of everything below the caret; a window-local restyle would leave the
rest of the document lying about what it is.

### 3. Remove the delegate-downcast state poke

`MarkdownSourceTextView.paste` reaches into
`(delegate as? SourceEditor.Coordinator)?.nextNativeGrouping = .discrete` in two places — a view
mutating its delegate's state through a downcast. Replace with an explicit
`coordinator.nextNativeEditIsDiscrete()`, and make `nextNativeGrouping` private to the coordinator.

## Proof

- `sourceHighlightAppliesOnlyToTheChangedWindow`, parameterised over `PerformanceCorpus.allCases`:
  using the spy `NSTextStorage` from `TextStorageApplierTests`, assert the number of attributed
  characters written for a one-character edit is under 5 % of document length. **Rehearsed failing** —
  today it writes 100 %.
- `sourceHighlightApplicationP95Under8ms`, parameterised over every corpus shape.
- `typingAFenceWidensTheStyleWindow` — open a fence above an existing block; assert the block below
  becomes code-styled and that `sourceHighlightWidened` was recorded. This is the proof that the
  optimisation did not trade correctness for speed, and it is **rehearsed failing** against a
  window-only implementation with no parity check.
- `sourceStylingStillLeavesTheStringUnchanged` — the existing REQ-040/051 guarantee re-proved against
  the incremental path, so ARC-018 is not weakened.
- `pasteMarksTheNextEditDiscreteWithoutTouchingDelegateState` — a source-conformance test proving no
  `as? SourceEditor.Coordinator` downcast remains in the view.

## Instrumentation and performance evidence

`sourceHighlightApplication` p50/p95 recorded per corpus shape in
`docs/research/performance-baseline.md`, alongside the WYSIWYG boundaries. Source mode gains a row in
the baseline table it has never had.

## Failure / rollback

Styling is presentation only; a defect can produce wrong colours but cannot alter source bytes —
`sourceStylingStillLeavesTheStringUnchanged` and the existing `rangesWithinBounds` proofs bound the
blast radius. The realistic failure is a stale style region after an edit the window missed; the fence
parity check covers the one unbounded construct, and any other miss is visible and non-destructive.

If `styleWindow` proves unreliable in review, land the metric and the budget alone and keep the
whole-document apply: measuring the problem is worth having even without the fix, and REQ-045 then
stays `Correction` with a recorded number rather than an `inherent` claim.

## Deletion / conformance gate

- No path performs a whole-document `setAttributes` on an ordinary keystroke; the only remaining
  whole-document restyle is the explicit fence-parity widening, which records a typed event every time
  it happens.
- `nextNativeGrouping` is no longer writable from the view.
- `Scripts/check-documentation-authority.sh`, `Scripts/check-instrumentation-coverage.sh` and
  `Scripts/check-proof-results.sh` pass, with REQ-045 citing `test` rather than `inherent`.
