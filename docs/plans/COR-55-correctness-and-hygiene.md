# COR-55 — Correctness and hygiene sweep

- **Status:** Approved; not implemented
- **Requirements:** REQ-085, REQ-095, REQ-098, REQ-102, REQ-103, REQ-105, REQ-110, REQ-116; ARC-017's alert-recording guarantee extended to a paste failure that currently presents nothing
- **Delivers:** none
- **ARC invariants:** ARC-007 (exact or typed refusal) applied to two force-unwraps that trap instead; ARC-011 (main-actor ownership) applied to a `deinit`; ARC-017, ARC-018 and ARC-020 unchanged and re-proved. No architecture change.

## Context

Findings from the August whole-application review that are individually small, jointly material, and
share no root cause. Each is an independent commit inside one PR.

Two of them are crash paths that survived COR-41's "remove hidden crash" sweep, one of which was
written during that same programme.

## Production changes

### 1. `ParseCoordinator.swift:212` — force-unwrap of a released document (crash)

```swift
guard let session, let self else { return }
if self.parseScheduler.finish(request) {
    self.scheduleParse(session: session, document: document!)   // document is a weak capture
}
```

The guard checks `session` and `self` and not `document`. Closing a document window while a parse is
in flight with a newer request pending traps.

Fix: `guard let session, let document, let self else { return }`.

Proof: `schedulerReschedulesNothingAfterTheDocumentIsReleased`. **Rehearsed failing — it must crash
before the fix**, since a proof for a crash that was never observed crashing is not a proof.

### 2. `MarkdownSourceIndex.swift:180–181` — force-unwrapped UTF-16 alignment (crash)

Two `samePosition(in: source.utf16)!` calls. `String.Index.samePosition(in:)` returns `nil` for an
index that is not aligned to a UTF-16 boundary, which is reachable with certain grapheme and surrogate
boundaries.

Fix: return a typed refusal consistent with ARC-007 — the file's own contract everywhere else:

```swift
guard let lowerIndex = start.samePosition(in: source.utf16),
      let upperIndex = end.samePosition(in: source.utf16) else {
    return .refused(.nonUTF16AlignedBoundary)
}
```

Proof: `unalignedGraphemeBoundaryRefusesRatherThanTraps`, with an astral-plane and unpaired-surrogate
fixture.

### 3. `EditorHost.swift:141` — `MainActor.assumeIsolated` inside `deinit`

`HostCoordinator.deinit` calls `MainActor.assumeIsolated { session.detach() }`. A `deinit` is not
guaranteed to run on the actor that owned the object; if the last release happens off-main this traps.

Fix: `deinit` keeps only `NotificationCenter.default.removeObserver(self)`. `session.detach()` already
runs from `ContentView.onDisappear`, and `detach` is documented and proved idempotent, so nothing is
lost.

Proof: `detachIsIdempotentAndDeinitPerformsNoActorWork`.

### 4. `WYSIWYGEditor.swift:881` — silent paste failure

```swift
if let plain = PastePolicy.plainText(from: .general) {
    _ = pastePlainText(plain)      // returns false whenever the presentation is stale
}
```

The text is discarded with no insertion, no alert, and no diagnostic. The user pressed ⌘V and nothing
happened. ARC-017 requires every user-visible failure to have a record — and this one escapes because
it presents no alert at all, which is the gap rather than an exemption.

Fix: present through `presentAlert(_:reason:)`, the compiler-enforced sole route, with a new
`.stalePresentation` reason. Make `performDragOperation`'s silent `return false` consistent with
`paste`'s existing alert for the no-target case; today the identical situation is loud in one method
and silent in the other.

Proof: `pasteIntoAStalePresentationReportsRatherThanDroppingTheText`, rehearsed failing.

### 5. `WYSIWYGEditor.swift:514` — `layoutApplication` measures caret blinks

`draw(_:)` records a sample on every call, including the twice-per-second insertion-point repaint. The
distribution is therefore dominated by sub-microsecond caret redraws, and a real layout regression
hides underneath thousands of them. ARC-020 requires samples to be honestly named and to include the
operations their boundary claims — this one includes a great many it does not claim.

Fix: sample in `layoutManager(_:didCompleteLayoutFor:atEnd:)` for the range an applied patch changed,
which is what the metric name asserts.

Proof: `layoutMetricIgnoresInsertionPointRepaints` — N caret blinks produce zero samples. Rehearsed
failing.

### 6. `WYSIWYGEditor.swift:604–749` — duplicated composition commit

`unmarkText` and `insertText` hold two near-identical fifty-line composition-commit sequences: stale
check, `complete()`, snapshot identity check, `session.perform`, trace, unmark, reapply.

```swift
/// The single route from a completed IME composition to a source transaction. Two copies of this
/// existed; the one that diverged is what made the performance suite hang for weeks (COR-32).
@discardableResult private func commitComposition(text: String) -> Bool
```

Proof: `bothCompositionCommitRoutesUseTheSameTransaction` — identical trace sequences from the
`insertText`-terminated and `unmarkText`-terminated paths. Existing
`committedCompositionUsesBoundedPatch` and the IME suites remain green.

### 7. `MarkdownTypography` — the displaced compatibility facade

The type self-describes as *"Compatibility facade for source-mode highlighting and older call sites"*.
`CLAUDE.md` §2 and `ENGINEERING.md` §15 forbid compatibility layers outright. It is not dead code:
`WYSIWYGEditor` constructed a fresh `MarkdownTypography()` on every `buildScoped` call, so it was a live
second owner of presentation styling beside `MarkdownTypography`.

Fix: move `baseAttributes` and `attributes(for: TokenStyle)` onto `MarkdownTypography`, delete
the duplicated styling owner, and pass **one shared instance** through `AttributedPresentationBuilder` rather than
constructing typography and theme objects per keystroke.

Proof: `typographyIsTheSoleOwnerOfPresentationStyling` — a source-conformance test in the shape of the
existing `noSecondaryMarkdownScannerRouteExists`, asserting no type other than `MarkdownTypography`
vends presentation fonts or colours.

### 8. `AttributedPresentationBuilder.swift:274` — `isQuoteBlock` is not a typed predicate

`ROADMAP.md` records that COR-39 made this a typed predicate. The implementation is still
`block.backgroundColor == nil` behind a function name, and the comment above it acknowledges a third
container kind would collide. Naming a predicate is not typing it.

Fix:

```swift
/// Quote and code containers are distinguishable by type, not by whether someone set a background.
final class QuoteTextBlock: NSTextBlock {}
final class CodeTextBlock: NSTextBlock {}
```

`MarkdownTypography.quoteBlock()` and `codeBlock()` return these; `isQuoteBlock` becomes
`block is QuoteTextBlock`.

`ROADMAP.md`'s COR-39 entry has already been corrected (2026-08-09) to record that the claim was false
when written; this increment makes it true and removes the correction note in the same change.

Proof: `quoteAndCodeContainersAreDistinguishedByType`, and the existing
`codeInsideQuoteComposesBothContainers` and `nestedBlockQuotesComposeTheirRules` stay green.

### 9. `Scripts/smoke-screenshot.sh` — a non-clean exit passes

The August verification run printed `app did not exit in time` and SIGTERM'd the process after the
capture succeeded. A killed run writes no REQ-095 terminating record, so its log reads as a crash —
and the script exits 0 regardless, which makes a shutdown regression invisible to the gate that exists
to catch it.

Fix: reproduce; determine whether `applicationWillTerminate` → `flushAndInvalidateAll` →
`finishSynchronously` blocks; fix the shutdown path; and make the script **fail** on a non-clean exit
with a distinct message, keeping its existing separation between an environment/capture failure and an
application diagnostic failure.

Proof: `Scripts/test-verify-smoke-log.sh` gains a fixture whose log lacks `runEnd` and must fail.

### 10. Small items

- `EditorCommandController.swift:67–69` — `availability(for:)` is computed twice per `perform`.
- `EditorCommandController.availability` — `case .codeBlock: fallthrough` has had a comment-only body
  since COR-38 retired its logic; delete the case.
- `EditorSession.swift:397` — the doc comment contains a duplicated fragment
  (`/// Primary edit entry    /// Primary edit entry —`).
- `SemanticEditEngine.swift:322–343` — the `switch` inside the `else` branch is indented at the wrong
  level.
- `SemanticEditEngine.swift:447–450` — an empty `// MARK: - Source mode` section left by COR-43.

Items 1–4 in this list are cosmetic and carry no proof; they are listed so the sweep is complete
rather than selective.

## Proof

Each numbered item above names its own proof. The two crash fixes (1 and 2) and the silent-failure fix
(4) must each be **observed failing — crashing, or dropping the text — before the fix**, and that
output pasted into the PR. A regression test for a crash nobody reproduced is a regression test for
nothing.

## Instrumentation and performance evidence

Item 5 changes what `layoutApplication` measures, so its recorded distribution will shift — expect the
p50 to rise substantially, because the caret blinks that were dragging it down are gone. Re-record it
in `docs/research/performance-baseline.md` and state plainly that a *higher* number here is the
correct outcome, so a future reader does not mistake an honest metric for a regression.

Item 7 removes a per-keystroke allocation; confirm the `nativeInputCallback` delta.

## Failure / rollback

Every item is an independent commit and independently revertible. None changes a coordinate, a
projection scope, or a persisted byte.

Item 7 is the largest surface — it touches every `buildScoped` call site — and is the one to land
first inside the PR so the rest sits on top of a compiling tree. If item 9's shutdown investigation
finds a deep AppKit cause, land the script's fail-on-non-clean-exit change alone and open a separate
increment for the cause, rather than leaving the gate permanently green on a broken shutdown.

## Deletion / conformance gate

- No `try!` and no force-unwrap of an optional that a guard in the same scope already handles remains
  in `ParseCoordinator` or `MarkdownSourceIndex`.
- the displaced styling facade no longer exists; `typographyIsTheSoleOwnerOfPresentationStyling` proves no
  replacement facade appeared.
- `backgroundColor == nil` is no longer used as a type tag anywhere.
- The duplicated composition-commit block is gone, proved by
  `bothCompositionCommitRoutesUseTheSameTransaction`.
- `ROADMAP.md`'s COR-39 correction note is deleted once the claim it corrects is true.
- `Scripts/check-documentation-authority.sh`, `Scripts/check-instrumentation-coverage.sh` and
  `Scripts/check-proof-results.sh` pass.
