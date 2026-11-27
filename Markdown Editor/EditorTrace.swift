//
//  EditorTrace.swift
//  Markdown Editor
//

import Foundation

/// Why a reconciliation-scope rule was broken.
///
/// // REQ-094/096; ARC-015.
nonisolated enum ReconciliationViolation: Sendable, Equatable {
    /// Observed session state was published while the view graph was reconciling it.
    case publication
    /// Live native selection, affinity, or scroll was captured during reconciliation.
    case liveStateCapture

    var symbol: DiagnosticSymbol {
        switch self {
        case .publication: return .publication
        case .liveStateCapture: return .liveStateCapture
        }
    }
}

nonisolated enum SourceHighlightWidenReason: Sendable, Equatable {
    case fenceParity

    var symbol: DiagnosticSymbol {
        switch self {
        case .fenceParity: return .fenceParity
        }
    }
}

/// Why an authoritative reconciliation result was dropped.
/// Why an accepted WYSIWYG edit could not be applied as a bounded patch. Both cases are
/// invariant violations: the presentation is rebuilt authoritatively and WYSIWYG goes
/// unavailable until it is current again.
nonisolated enum PresentationRecoveryReason: Sendable, Equatable {
    /// A patch could not be proven against both complete snapshots.
    case patchUnprovable
    /// Applied storage no longer matched the snapshot the patch was built against.
    case appliedStorageMismatch
    /// COR-71: a provisional snapshot disagreed with the parse of the same revision, first in
    /// this part of its content. Recorded as `patchUnprovable` until tour 45964220766 needed to
    /// tell the two apart.
    case provisionalDisagreed(PresentationSnapshot.ContentField)

    var symbol: DiagnosticSymbol {
        switch self {
        case .patchUnprovable: return .patchUnprovable
        case .appliedStorageMismatch: return .appliedStorageMismatch
        case .provisionalDisagreed(let field): return field.symbol
        }
    }
}

nonisolated enum ReconciliationDiscardReason: Sendable, Equatable {
    case stale
    case parseFailure
    case oracleModel
    case oracleSnapshot
    case identityMismatch

    var symbol: DiagnosticSymbol {
        switch self {
        case .stale: return .stale
        case .parseFailure: return .parseFailure
        case .oracleModel: return .oracleModel
        case .oracleSnapshot: return .oracleSnapshot
        case .identityMismatch: return .identityMismatch
        }
    }
}

/// Why a document load, save, or revert did not complete.
///
/// // REQ-100: deliberately minimal. `MarkdownDocumentData.init(data:)` has exactly one content
/// // throw site (invalid UTF-8); `fileUnreadable` covers a failure reading the URL itself
/// // (removed, permission denied) before any content ever reaches that decode step. AppKit's
/// // save completion reports only a success/failure boolean with no underlying reason — it
/// // does not distinguish a genuine write failure from the user cancelling a Save panel, the
/// // same limitation `ImagePlacementEvent.saveCancelledOrFailed` already accepts elsewhere in
/// // this codebase. Do not add a case this code cannot actually produce.
nonisolated enum DocumentIOFailure: Sendable, Equatable {
    case invalidUTF8
    case fileUnreadable
    case saveFailedOrCancelled
    /// A save while another app's write is unresolved (REQ-146): AppKit stops it and asks the
    /// person to save anyway, revert or save elsewhere. The app asking, not failing.
    case awaitingConflictDecision

    var symbol: DiagnosticSymbol {
        switch self {
        case .invalidUTF8: return .invalidUTF8
        case .fileUnreadable: return .fileUnreadable
        case .saveFailedOrCancelled: return .saveFailedOrCancelled
        case .awaitingConflictDecision: return .awaitingConflictDecision
        }
    }
}

/// Severity of a user-visible alert. Distinct from `DiagnosticLevel` (which describes how a
/// record itself should be treated in the log, not what kind of alert produced it).
nonisolated enum AlertSeverity: Sendable, Equatable {
    case error
    case warning
    case info

    var symbol: DiagnosticSymbol {
        switch self {
        case .error: return .alertError
        case .warning: return .alertWarning
        case .info: return .alertInfo
        }
    }
}

/// Why a user-visible alert was presented (REQ-102; ARC-017).
///
/// `.placement` reuses `ImagePlacementError` directly for every alert that already carries one
/// (busy, save-cancelled-or-failed, and every failure `fail(_:_:)` raises); the remaining cases
/// cover alert sites that occur before any placement error could exist — pasteboard
/// classification rejecting content outright, no resolvable insertion target, the
/// insertion-point-changed-after-commit warning, and the broken-references-after-move warning.
nonisolated enum AlertReason: Sendable, Equatable {
    case placement(ImagePlacementError)
    case noInsertionTarget
    case pasteboardUnsupportedOrCorrupt
    case insertionPointChangedAfterCommit
    case brokenReferencesAfterMove

    var symbol: DiagnosticSymbol {
        switch self {
        case .placement(let error): return error.symbol
        case .noInsertionTarget: return .noInsertionTarget
        case .pasteboardUnsupportedOrCorrupt: return .unsupportedOrCorrupt
        case .insertionPointChangedAfterCommit: return .insertionPointChanged
        case .brokenReferencesAfterMove: return .documentMoved
        }
    }
}

/// Which planner handled an accepted edit. Derived from the command, never from an action name.
///
/// // REQ-089; ARC-016: `SourceMutation.actionName` is a user-facing undo title and is never
/// // recorded; only its length appears, as it already does for undo registration.
nonisolated enum PlannerKind: Sendable, Equatable {
    case insertText
    case deleteBackward
    case toggleBold
    case toggleItalic
    case toggleStrikethrough
    case toggleInlineCode
    case setParagraph
    case setHeading
    case toggleOrderedList
    case toggleUnorderedList
    case toggleTaskList
    case toggleBlockQuote
    case toggleCodeBlock
    case setLink
    case toggleTask
    case replaceTableCell
    case insertImageMarkdown
    case insertParagraphBreak
    case joinBlockBackward

    init(_ command: SemanticCommand) {
        switch command {
        case .insertText: self = .insertText
        case .deleteBackward: self = .deleteBackward
        case .toggleBold: self = .toggleBold
        case .toggleItalic: self = .toggleItalic
        case .toggleStrikethrough: self = .toggleStrikethrough
        case .toggleInlineCode: self = .toggleInlineCode
        case .setParagraph: self = .setParagraph
        case .setHeading: self = .setHeading
        case .toggleOrderedList: self = .toggleOrderedList
        case .toggleUnorderedList: self = .toggleUnorderedList
        case .toggleTaskList: self = .toggleTaskList
        case .toggleBlockQuote: self = .toggleBlockQuote
        case .toggleCodeBlock: self = .toggleCodeBlock
        case .setLink: self = .setLink
        case .toggleTask: self = .toggleTask
        case .replaceTableCell: self = .replaceTableCell
        case .insertImageMarkdown: self = .insertImageMarkdown
        case .insertParagraphBreak: self = .insertParagraphBreak
        case .joinBlockBackward: self = .joinBlockBackward
        }
    }

    var symbol: DiagnosticSymbol {
        switch self {
        case .insertText: return .insertText
        case .deleteBackward: return .deleteBackward
        case .toggleBold: return .toggleBold
        case .toggleItalic: return .toggleItalic
        case .toggleStrikethrough: return .toggleStrikethrough
        case .toggleInlineCode: return .toggleInlineCode
        case .setParagraph: return .setParagraph
        case .setHeading: return .setHeading
        case .toggleOrderedList: return .toggleOrderedList
        case .toggleUnorderedList: return .toggleUnorderedList
        case .toggleTaskList: return .toggleTaskList
        case .toggleBlockQuote: return .toggleBlockQuote
        case .toggleCodeBlock: return .toggleCodeBlock
        case .setLink: return .setLink
        case .toggleTask: return .toggleTask
        case .replaceTableCell: return .replaceTableCell
        case .insertImageMarkdown: return .insertImageMarkdown
        case .insertParagraphBreak: return .insertParagraphBreak
        case .joinBlockBackward: return .joinBlockBackward
        }
    }
}

/// Category of a refused editor edit, including transition-proof failures.
nonisolated enum EditRefusalCategory: Sendable, Equatable {
    case refusal(EditRefusal)
    case invalidPresentationTransition

    var symbol: DiagnosticSymbol {
        switch self {
        case .invalidPresentationTransition: return .invalidPresentationTransition
        case .refusal(let refusal):
            switch refusal {
            case .staleVersion: return .staleVersion
            case .stalePresentation: return .stalePresentation
            case .ambiguousSelection: return .ambiguousSelection
            case .unsupportedCommand: return .unsupportedCommand
            case .mappingFailure: return .mappingFailure
            case .invalidRange: return .invalidRange
            case .unavailable: return .unavailable
            case .mixedDomain: return .mixedDomain
            case .crossCell: return .crossCell
            case .unprovable: return .unprovable
            }
        }
    }
}

/// Privacy-safe editor instrumentation events — identifiers and numeric metadata only.
///
/// // REQ-089; ARC-016: no associated value is a `String`. Document text, replacement text,
/// // selected text, URLs, descriptions, filenames, and paths are unrepresentable here.
nonisolated enum EditorTraceEvent: Sendable, Equatable {
    case mutationRequested(id: UUID, revision: UInt64, location: Int, length: Int, replacementLength: Int)
    case mutationCommitted(id: UUID, newRevision: UInt64, location: Int, length: Int, replacementLength: Int)
    case mutationRefused(id: UUID, reason: SourceEditRefusal)
    case undoRegistered(actionNameLength: Int, groupingTyping: Bool)
    case historyApplied(direction: HistoryDirection, newRevision: UInt64, location: Int, length: Int)
    case historyRefused(direction: HistoryDirection, reason: SourceEditRefusal)
    case parseStarted(sourceVersion: UInt64, utf16Count: Int)
    case parseCompleted(sourceVersion: UInt64)
    case parseCancelled(sourceVersion: UInt64)
    case modeToggle(toSource: Bool)
    case compositionBegan(sourceVersion: UInt64)
    case compositionCommitted(sourceVersion: UInt64, replacementLength: Int)
    case compositionCancelled
    case compositionRefusedStale
    case imageDisplayCacheObserved(hit: Bool, bytesRead: Int, decodeCount: Int, durationNanos: UInt64, totalBytes: Int)
    /// REQ-114: a referenced local image that could not be resolved for display. Carries only a
    /// closed reason symbol — never the destination, filename, or path.
    case imageResolutionFailed(reason: LocalImageResolveFailure)
    case editRouted(context: EditorMode, groupingTyping: Bool, planner: PlannerKind)
    case presentationInstalled(snapshotID: UInt64, sourceRevision: UInt64, provisional: Bool)
    case presentationTransition(from: UInt64, to: UInt64, sourceRevision: UInt64, durationNanos: UInt64)
    case presentationRecovered(snapshotID: UInt64, sourceRevision: UInt64, reason: PresentationRecoveryReason)
    case reconciliationScheduled(sourceRevision: UInt64, generation: UInt64)
    case reconciliationDiscarded(sourceRevision: UInt64, reason: ReconciliationDiscardReason)
    case reconciliationApplied(snapshotID: UInt64, sourceRevision: UInt64, generation: UInt64, durationNanos: UInt64)
    case editRefused(category: EditRefusalCategory)
    case availabilityChanged(editable: Bool, sourceRevision: UInt64)
    case updateOrigin(EditorUpdateOrigin)
    case documentOpened(utf16Count: Int)
    case documentClosed(sourceRevision: UInt64)
    case documentLoaded(utf16Count: Int, sourceRevision: UInt64)
    case documentLoadFailed(reason: DocumentIOFailure)
    case documentSaveStarted(utf16Count: Int)
    case documentSaveSucceeded(utf16Count: Int, sourceRevision: UInt64, durationNanos: UInt64)
    case documentSaveFailed(reason: DocumentIOFailure)
    case documentReverted(sourceRevision: UInt64, utf16Count: Int)
    /// REQ-145–149: the file changed underneath an open document, and what was done about it.
    /// Carries no path — a filename is document-identifying content (REQ-031).
    case externalFileChange(
        event: ExternalFileEvent,
        local: LocalEditState,
        outcome: ExternalChangeOutcome,
        sourceRevision: UInt64
    )

    // View-update integrity (REQ-094/096; ARC-015).
    case hostUpdateEnded(durationNanos: UInt64, updatesInWindow: Int)
    case hostUpdateStorm(updatesInWindow: Int)
    case viewReconciliationViolation(kind: ReconciliationViolation)

    // Image placement (REQ-101/102; ARC-017).
    case imagePlacementPhase(from: ImagePlacementPhase, to: ImagePlacementPhase)
    case imagePlacementStarted(claimCount: Int)
    case imagePlacementCommitted(fileCount: Int, totalBytes: Int, durationNanos: UInt64)
    case imagePlacementFailed(reason: ImagePlacementError, phase: ImagePlacementPhase)
    case imagePlacementRolledBack(removedFileCount: Int)
    case assetDirectoryPublished(fileCount: Int, totalBytes: Int)
    case userAlertPresented(severity: AlertSeverity, reason: AlertReason)
    case performanceSummary(metric: PerformanceSampler.Metric, count: Int, p50Nanos: UInt64, p95Nanos: UInt64, maxNanos: UInt64)
    case budgetExceeded(metric: PerformanceSampler.Metric, p95Nanos: UInt64, budgetNanos: UInt64)
    case sourceHighlightWidened(reason: SourceHighlightWidenReason)
    case workLedger(scope: WorkScope, documentParses: Int, projectionCompiles: Int, oracleValidations: Int, attributedBuilds: Int, attributedCharactersWritten: Int, storageFullReplacements: Int, imageDecodes: Int, fileBytesRead: Int, mainThreadBlockedNanos: UInt64)
    case frameStatistics(hitchMillisPerSecond: Double, longestFrameNanos: UInt64, framesObserved: Int)
    case memoryFootprint(bytes: UInt64, peakBytes: UInt64)
}

nonisolated enum HistoryDirection: Sendable, Equatable {
    case undo
    case redo

    var symbol: DiagnosticSymbol {
        switch self {
        case .undo: return .undo
        case .redo: return .redo
        }
    }
}

extension SourceEditRefusal {
    var symbol: DiagnosticSymbol {
        switch self {
        case .staleVersion: return .staleVersion
        case .invalidRange: return .invalidRange
        case .conflict: return .conflict
        case .contentMismatch: return .contentMismatch
        }
    }
}

extension EditorMode {
    var symbol: DiagnosticSymbol {
        switch self {
        case .source: return .source
        case .wysiwyg: return .wysiwyg
        }
    }
}

extension EditorUpdateOrigin {
    var symbol: DiagnosticSymbol {
        switch self {
        case .nativeUserInput: return .nativeUserInput
        case .programmaticPresentation: return .programmaticPresentation
        case .selectionRestoration: return .selectionRestoration
        case .modeRestoration: return .modeRestoration
        case .history: return .history
        case .composition: return .composition
        }
    }
}

extension ImagePlacementPhase {
    var symbol: DiagnosticSymbol {
        switch self {
        case .idle: return .idle
        case .accepted: return .accepted
        case .receivingPromises: return .receivingPromises
        case .awaitingSave: return .awaitingSave
        case .staging: return .staging
        case .publishing: return .publishing
        case .committing: return .committing
        case .committed: return .committed
        case .cancelled: return .cancelled
        case .failed: return .failed
        }
    }
}

extension ImagePlacementError {
    var symbol: DiagnosticSymbol {
        switch self {
        case .busy: return .busy
        case .noDocumentURL: return .noDocumentURL
        case .saveCancelled: return .saveCancelled
        case .saveFailed: return .saveFailed
        case .documentMoved: return .documentMoved
        case .unsafeDestination: return .unsafeDestination
        case .unsupportedOrCorrupt: return .unsupportedOrCorrupt
        case .typeMismatch: return .typeMismatch
        case .writeFailed: return .writeFailed
        case .promiseFailed: return .promiseFailed
        case .promiseTimedOut: return .promiseTimedOut
        case .nonRegularSource: return .nonRegularSource
        case .parentChanged: return .parentChanged
        }
    }
}

extension ExternalFileEvent {
    var symbol: DiagnosticSymbol {
        switch self {
        case .contentsChanged: return .contentsChanged
        case .deleted: return .deleted
        case .moved: return .moved
        }
    }
}

extension LocalEditState {
    var symbol: DiagnosticSymbol {
        switch self {
        case .clean: return .clean
        case .dirty: return .dirty
        }
    }
}

extension ExternalChangeOutcome {
    var symbol: DiagnosticSymbol {
        switch self {
        case .reloadPreservingSelection: return .reloadPreservingSelection
        case .retainLocalEditsAsConflicted: return .retainLocalEditsAsConflicted
        case .retainContentAfterDeletion: return .retainContentAfterDeletion
        case .followMove: return .followMove
        }
    }
}

extension PerformanceSampler.Metric {
    var symbol: DiagnosticSymbol {
        switch self {
        case .nativeInputCallback: return .nativeInputCallback
        case .modeTransition: return .modeTransition
        case .parseProjection: return .parseProjection
        case .imageResolution: return .imageResolution
        case .authoritativeApplication: return .authoritativeApplication
        case .layoutApplication: return .layoutApplication
        case .mainActorLatency: return .mainActorLatency
        case .sourceHighlightApplication: return .sourceHighlightApplication
        case .sourceHighlightCompute: return .sourceHighlightCompute
        case .semanticCommand: return .semanticCommand
        }
    }
}

/// Sink for privacy-safe editor events.
@MainActor
protocol EditorTraceSink: AnyObject {
    func record(_ event: EditorTraceEvent)
    /// Production owners must declare the closed route they are executing. The one-argument
    /// method remains the encoding/gate-fixture path and is never reachability evidence.
    func record(route: DiagnosticEventName, _ event: EditorTraceEvent)
}

/// In-memory recorder for tests.
@MainActor
final class InMemoryEditorTrace: EditorTraceSink {
    private(set) var events: [EditorTraceEvent] = []

    func record(_ event: EditorTraceEvent) {
        events.append(event)
    }

    func record(route: DiagnosticEventName, _ event: EditorTraceEvent) {
        events.append(event)
    }

    func reset() {
        events.removeAll()
    }

    func eventsMatching(_ predicate: (EditorTraceEvent) -> Bool) -> [EditorTraceEvent] {
        events.filter(predicate)
    }
}

extension LocalImageResolveFailure {
    /// REQ-114/089; ARC-016: a closed symbol per failure class. `oversizeDimensions` deliberately
    /// drops its measured width and height here — they are recorded as the reason class only, so
    /// the payload cannot describe the referenced file.
    var symbol: DiagnosticSymbol {
        switch self {
        case .remoteURL: return .remoteURL
        case .missingFile: return .missingFile
        case .encodedFileTooLarge: return .encodedFileTooLarge
        case .unsupportedType: return .unsupportedType
        case .corrupt: return .corrupt
        case .oversizeDimensions: return .oversizeDimensions
        case .decodeFailed: return .decodeFailed
        case .staleVersion: return .staleImageVersion
        }
    }
}
