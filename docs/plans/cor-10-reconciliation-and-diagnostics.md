# COR-10 — Publication-free reconciliation and JSON Lines diagnostics

- **Status:** Approved; not implemented
- **Requirements:** REQ-089 (amended), REQ-094, REQ-095, REQ-096; REQ-052/086 unchanged
- **Architecture impact:** approved change — adds ARC-015 and ARC-016, ARC-Q11, and
  ENGINEERING §11. Approved on the strength of the reproduced counterexample below.

## Counterexample

Debug build, `open basic.md` (five lines), window idle, no user input: sustained 100% CPU.
`sample` attributes 2217 of 2217 samples to a repeating chain:

```
__CFRunLoopDoObservers → NSHostingView.beginTransaction → GraphHost.flushTransactions
  → AG::Subgraph::update → PlatformViewRepresentableAdaptor.updateViewProvider
    → EditorHostView.updateNSView              EditorHost.swift:82
      → HostCoordinator.applyMode              EditorHost.swift:232
        → EditorSession.updateWYSIWYGModeState EditorSession.swift:118
```

`EditorHostView` observes `EditorSession` and writes to it during its own `updateNSView`.
`@Published` invalidates on assignment, not on change, so the write re-dirties the view being
reconciled. One full view-graph update runs per run-loop pass, forever. It is a livelock, not a
deadlock: the main thread is never blocked.

Writing sites, all unconditional per reconciliation:

| Site | Path |
|---|---|
| `EditorHost.swift:203` | `applyMode` captures live source selection/scroll into `updateSourceModeState` |
| `EditorHost.swift:217` | `applyMode` captures live WYSIWYG selection/scroll into `updateWYSIWYGModeState` |
| `EditorHost.swift:250` | `setSelectedRanges` → `textViewDidChangeSelection` → `WYSIWYGTextView.swift:306` writes selection back |
| `MarkdownTextView.swift:187` | same write-back in source mode |
| `EditorHost.swift:299`, `WYSIWYGTextView.swift:69` | `pendingSelectionRestoration` consumed (published) during reconciliation |

Rejected as band-aids: equality guards inside the `update*ModeState` setters (works by accident,
fails the moment a `CGFloat` scroll offset jitters, preserves the illegal flow, and would make the
regression proof pass trivially); `DispatchQueue.main.async` deferral (a slower loop); an
`isApplyingMode` re-entrancy flag (masks the symptom).

Second finding: `MarkdownDocument.trace` is never assigned outside tests and `OSLogEditorTrace` is
instantiated nowhere. Production has no instrumentation at all, which is why this defect produced
no app-authored evidence.

## Design

### A. Publication follows rendering, not ownership

No view body renders selection, affinity, scroll offset, the authoritative tree, or the one-shot
selection instruction. `EditorToolbar` reads mode state only inside button *actions*
(`currentSelection()`), never in `body`. Only `mode`, `presentation`, and `resolvedImages` drive
reconciliation.

`EditorSession` keeps sole ownership of all of it (ARC-002 unchanged) but publishes only the
rendered subset:

- `@Published`: `mode`, `presentation`, `resolvedImages`.
- session-owned, unpublished: `sourceModeState`, `wysiwygModeState`, `authoritativeTree`,
  `pendingSelectionRestoration`.

Availability transitions always accompany a `presentation` assignment (`installPresentation`,
`invalidateDerivedState`, `scheduleParse` failure paths), so the host is still re-invoked exactly
when `isEditable` must change.

### B. Reconciliation becomes a pure reader

- Delete the capture blocks at `EditorHost.swift:200–226`. `applyMode` only reads.
- Split `applyMode` into `applyModeIfChanged(_:)`: return immediately when `lastAppliedMode ==
  mode`. Visibility, focus, and scroll/selection restoration run on a real mode change only.
- `updateNSView` brackets its whole body in `session.withViewReconciliation { }`.

### C. Live native state enters only from AppKit events

- `HostCoordinator` becomes an `NSObject` and observes `NSView.boundsDidChangeNotification` on
  each `NSClipView` (`postsBoundsChangedNotifications = true`) to record scroll offset.
- Both `textViewDidChangeSelection` implementations return without writing session state when
  `session.updateOrigin.current != .nativeUserInput`. The same rule already governs
  `closeTypingUndoGroup()` two lines below; it was simply not applied to the state write.
- The bounds observer applies the same origin guard and skips an unchanged offset.

### D. Enforcement

`EditorSession` gains `viewReconciliationDepth` and `stateMutationCount`. While depth > 0, any
`objectWillChange` publication or `update*ModeState` call records a
`viewReconciliationViolation` fault and `assertionFailure`s in DEBUG.

### E. Diagnostics

`DiagnosticValue` is a closed enum — `.int`, `.uint`, `.double`, `.bool`, `.symbol(DiagnosticSymbol)`
— with **no string case**, making content, URLs, filenames, and paths unrepresentable (ARC-016).
The String-typed associated values on `EditorTraceEvent` (`reconciliationDiscarded(reason:)`,
`editRefused(category:)`, `editRouted(context:planner:)`) are replaced by closed enums in the same
change; no stringly-typed trace path remains.

`DiagnosticLog` writes one JSON Lines file per run to `~/Library/Logs/Markdown Editor/`, named
`run-<UTC timestamp>-<run id>.jsonl`. First record is the run header (schema version, run id,
build, commit, host kind from the existing `MarkdownAppDelegate.isRunningUnitTests`, OS, pid); a
`runEnd` record marks clean termination. Every record carries `t`, `up`, `seq`, `lvl`, `cat`,
`ev`, opaque `doc` handle, and flat `data`. Records buffer on the main actor and flush on a
background serial queue (depth, ~250 ms timer, `lvl >= error`, `willTerminate`). Per-`(cat,ev)`
rate collapse emits `{"ev":"repeated","of":…,"count":N}` above threshold. Retention bounds
per-file size and run count, oldest first.

`JSONLinesEditorTrace` replaces `OSLogEditorTrace`, which is deleted. `MarkdownDocument` is wired
to the sink at construction. New events: `hostUpdateBegan/Ended`, `hostUpdateStorm`,
`viewReconciliationViolation`, `mainActorStall`, document lifecycle.

`MainActorWatchdog` pings the main actor from a background `DispatchSourceTimer`; no reply within
one second records a fault.

## Files

**Add:** `DiagnosticValue.swift`, `DiagnosticRecord.swift`, `DiagnosticLog.swift`,
`JSONLinesEditorTrace.swift`, `MainActorWatchdog.swift`;
`Markdown EditorTests/ReconciliationInvariantTests.swift`, `DiagnosticLogTests.swift`.

**Modify:** `EditorSession.swift`, `EditorHost.swift`, `WYSIWYGTextView.swift`,
`MarkdownTextView.swift`, `EditorTrace.swift`, `MarkdownDocument.swift`,
`Markdown_EditorApp.swift`, `SemanticEditEngine.swift` (trace call sites).

**Delete:** `OSLogEditorTrace`; the `applyMode` capture blocks; `@Published` on the four
unrendered session properties; every String-typed trace associated value.

## Phases

1. Publication split and unrendered-state de-publication.
2. `applyMode` split, capture deletion, reconciliation bracket.
3. Event-driven scroll capture and delegate origin guards.
4. Re-entrancy counter and violation reporting.
5. Diagnostic value/record/log/sink, `OSLogEditorTrace` deletion, wiring, watchdog.
6. Requirement, ENGINEERING, and ROADMAP reconciliation; delete this plan.

## Proof

Automated, non-UI, direct AppKit construction only.

| Test | Discriminates |
|---|---|
| `unchangedModeReconciliationMutatesNoSessionState` | fails today — `stateMutationCount` increments every pass |
| `hostReconciliationPublishesNothing` | fails today — `objectWillChange` fires every pass |
| `idleDocumentSettlesAfterBoundedHostUpdates` | fails today — never settles |
| `programmaticSelectionDoesNotWriteSessionState` | fails today — delegate writes back |
| `diagnosticPayloadHasNoStringCase` | ARC-016 by construction |
| `runHeaderIdentifiesHostKindAndBuild`, `everyRecordIsOneParsableJSONLine`, `retentionRemovesOldestRuns` | REQ-095 |
| `reentrantPublicationRecordsFault`, `hostUpdateStormRecordsFault`, `repeatedEventsCollapseWithCount` | REQ-096 |

Existing suites — `PersistentEditorCharacterizationTests`, `AcceptedEditTransactionTests`,
`EditorIntegrationTests` — must stay green; REQ-086 mode restoration is unchanged behavior.

Measurement: relaunch the counterexample and confirm idle CPU at rest, plus a bounded
`hostUpdateEnded` count in the run's JSONL file.

## Failure and rollback

Each phase is independently revertable. If the de-publication in phase 1 proves insufficient for
some rendered fact, the correction is to publish that specific fact explicitly — not to restore
blanket publication. No compatibility shim is retained.

## Deletion gate

After implementation: no `OSLogEditorTrace` symbol; no `os_log`/`Logger` use for editor events; no
`@Published` on the four unrendered properties; no session write reachable from `updateNSView`;
no String-typed `EditorTraceEvent` associated value. Verified by source inspection in review and
by `Scripts/check-documentation-authority.sh`.
