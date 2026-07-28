# COR-14 — Image placement and asset filesystem instrumentation

- **Status:** Approved; not implemented
- **Requirements:** REQ-101, REQ-102
- **Architecture impact:** adds `ARC-017` (added to `docs/ENGINEERING.md` on this branch when
  implemented; no existing invariant changes).

The largest gap in this initiative. `ImagePlacementController`, `AssetDirectoryStore`,
`ImageIOExecutor`, `POSIXFileOps`, `ImageBatchPreflight`, and `FilePromiseBridge` contain zero
trace references, and there are 11 sites that set `placementController.alert` — every one shows
the user an error and logs nothing. This is the subsystem that touches the user's real image
files.

## Requirements and invariant

- **REQ-101** — The system shall record image-placement phase transitions, claim counts, byte
  counts, and typed failures for every paste, drag-and-drop, and Add Image operation, without
  recording file names, paths, providers, or image data.
- **REQ-102** — WHEN the system presents a failure or warning to the user, it shall record a
  matching diagnostic at `error` or `warn` level.
- **ARC-017** — Every user-visible failure alert has a corresponding diagnostic record.
  *Proof: alert-construction sites route through one instrumented entry point; conformance test.*

## The vocabulary already exists — reuse it

Do not invent new categories. These enums are already closed and exhaustive:

- `ImagePlacementPhase` (`ImagePlacementModels.swift`): `idle`, `accepted`, `receivingPromises`,
  `awaitingSave`, `staging`, `publishing`, `committing`, `committed`, `cancelled`, `failed`
- `ImagePlacementEvent` (`ImagePlacementStateMachine.swift`): `begin`, `startReceivingPromises`,
  `startAwaitingSave`, `promisesReceived`, `saveSucceeded`, `saveCancelledOrFailed`,
  `startStaging`, `startPublishing`, `startCommitting`, `succeed`, `fail`, `cancel`
- `ImagePlacementError`: `busy`, `noDocumentURL`, `saveCancelled`, `saveFailed`, `documentMoved`,
  `unsafeDestination`, `unsupportedOrCorrupt`, `typeMismatch`, `writeFailed`, `promiseFailed`,
  `promiseTimedOut`, `nonRegularSource`, `parentChanged`

Add a `var symbol: DiagnosticSymbol` to each, and the corresponding cases to `DiagnosticSymbol`.
This is mechanical; keep the case names identical so the log reads like the code.

## Events to add

| Event | Payload | Level |
|---|---|---|
| `imagePlacementPhase(from:to:)` | two phase symbols | `debug` |
| `imagePlacementStarted(claimCount:)` | count | `info` |
| `imagePlacementCommitted(fileCount:totalBytes:durationNanos:)` | counts, timing | `info` |
| `imagePlacementFailed(reason:phase:)` | error + phase symbols | `error` |
| `imagePlacementRolledBack(removedFileCount:)` | count | `warn` |
| `assetDirectoryPublished(fileCount:totalBytes:)` | counts | `debug` |
| `assetDirectoryRejected(reason:)` | containment-failure symbol | `error` |
| `userAlertPresented(severity:reason:)` | severity + reason symbols | `warn` / `error` |

## Enforcing ARC-017 rather than hoping for it

Do not sprinkle `trace?.record` next to each of the 11 alert sites — that is exactly the pattern
that decays. Instead make the alert property private and funnel every assignment through one
instrumented method on `ImagePlacementController`:

```swift
@Published private(set) var alert: AlertKind?

/// REQ-102; ARC-017: the only way to raise a user-visible alert, so a presented failure
/// can never be absent from the run log.
func presentAlert(_ kind: AlertKind, reason: AlertReason) {
    alert = kind
    actions?.trace?.record(.userAlertPresented(severity: kind.severity, reason: reason))
}

func dismissAlert() { alert = nil }
```

Then update all 11 call sites (6 in `ImagePlacementController`, 2 in `MarkdownTextView`, 3 in
`WYSIWYGTextView`) and `ContentView`'s alert-dismissal binding. Verify the exact current count and
locations against code before changing call sites — the draft's count is a recommendation, not a
guarantee.

**Conformance test** `everyAlertSiteRecordsDiagnostic`: assert by source inspection that no file
outside `ImagePlacementController.swift` contains `alert = `. Same style of executable structural
proof already used in `ArchitectureConformanceTests`.

`ImagePlacementController` needs a trace reference; it already holds `actions:
DocumentActionInterface`. Decide, by reading `DocumentActionInterface.swift`, whether to expose
`trace` on that protocol or give the controller its own weak sink — prefer not widening the
protocol if a direct sink is cleaner.

## Files

**Modify:** `Markdown Editor/EditorTrace.swift`, `Markdown Editor/DiagnosticValue.swift`,
`Markdown Editor/DiagnosticRecord.swift`, `Markdown Editor/JSONLinesEditorTrace.swift`,
`Markdown Editor/ImagePlacementModels.swift`, `Markdown Editor/ImagePlacementStateMachine.swift`,
`Markdown Editor/ImagePlacementController.swift`, `Markdown Editor/MarkdownTextView.swift`,
`Markdown Editor/WYSIWYGTextView.swift`, `Markdown Editor/ContentView.swift`,
`Markdown Editor/AssetDirectoryStore.swift`, `docs/ENGINEERING.md` (§12 ARC-Q, §13 ARC-017),
`docs/REQUIREMENTS.md` (REQ-101/102 → Done).

**Add:** conformance and behavior tests listed below.

## Proof

- `imagePlacementFailureIsRecorded` — drive a failing placement through the existing test seams
  (`prepareUntitledPlacementForTesting`, `saveBridgeOverride`) and assert the typed reason.
- `imagePlacementTraceOmitsFilenames` — run a placement with a fixture named
  `secret-holiday-photo.png` and assert that string appears in no emitted line. This is the
  highest-value privacy test in the whole initiative; write it first.
- `everyAlertSiteRecordsDiagnostic` — structural.
- `rollbackIsRecorded` — the filesystem adversarial suite already forces rollback; assert the
  record.
- `Scripts/check-instrumentation-coverage.sh` passes.

## Rollback

Self-contained apart from the `alert` property becoming private with an accessor method; any
revert must restore the previous 11 call sites verbatim rather than leaving a mixed state.
