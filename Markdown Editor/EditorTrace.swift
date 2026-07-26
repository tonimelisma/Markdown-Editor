//
//  EditorTrace.swift
//  Markdown Editor
//

import Foundation
import OSLog

/// Privacy-safe editor instrumentation events — identifiers and numeric metadata only.
///
/// // REQ-089: no source text, replacement text, selected text, URL strings, or complete paths.
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
    case imageCacheStore(cost: Int, totalBytes: Int)
}

nonisolated enum HistoryDirection: String, Sendable, Equatable {
    case undo
    case redo
}

/// Sink for privacy-safe editor events.
@MainActor
protocol EditorTraceSink: AnyObject {
    func record(_ event: EditorTraceEvent)
}

/// In-memory recorder for tests.
@MainActor
final class InMemoryEditorTrace: EditorTraceSink {
    private(set) var events: [EditorTraceEvent] = []

    func record(_ event: EditorTraceEvent) {
        events.append(event)
    }

    func reset() {
        events.removeAll()
    }

    func eventsMatching(_ predicate: (EditorTraceEvent) -> Bool) -> [EditorTraceEvent] {
        events.filter(predicate)
    }
}

/// Production OSLog sink — privacy-safe signposts / fault summaries only.
@MainActor
final class OSLogEditorTrace: EditorTraceSink {
    private let logger = Logger(subsystem: "net.daringfireball.markdown-editor", category: "EditorTrace")

    func record(_ event: EditorTraceEvent) {
        switch event {
        case .mutationRequested(let id, let revision, let location, let length, let replacementLength):
            logger.debug("mutationRequested id=\(id.uuidString, privacy: .public) rev=\(revision) loc=\(location) len=\(length) replLen=\(replacementLength)")
        case .mutationCommitted(let id, let newRevision, let location, let length, let replacementLength):
            logger.debug("mutationCommitted id=\(id.uuidString, privacy: .public) rev=\(newRevision) loc=\(location) len=\(length) replLen=\(replacementLength)")
        case .mutationRefused(let id, let reason):
            logger.fault("mutationRefused id=\(id.uuidString, privacy: .public) reason=\(String(describing: reason), privacy: .public)")
        case .undoRegistered(let actionNameLength, let groupingTyping):
            logger.debug("undoRegistered nameLen=\(actionNameLength) typing=\(groupingTyping)")
        case .historyApplied(let direction, let newRevision, let location, let length):
            logger.debug("historyApplied \(direction.rawValue, privacy: .public) rev=\(newRevision) loc=\(location) len=\(length)")
        case .historyRefused(let direction, let reason):
            logger.fault("historyRefused \(direction.rawValue, privacy: .public) reason=\(String(describing: reason), privacy: .public)")
        case .parseStarted(let sourceVersion, let utf16Count):
            logger.debug("parseStarted rev=\(sourceVersion) utf16=\(utf16Count)")
        case .parseCompleted(let sourceVersion):
            logger.debug("parseCompleted rev=\(sourceVersion)")
        case .parseCancelled(let sourceVersion):
            logger.debug("parseCancelled rev=\(sourceVersion)")
        case .modeToggle(let toSource):
            logger.debug("modeToggle toSource=\(toSource)")
        case .compositionBegan(let sourceVersion):
            logger.debug("compositionBegan rev=\(sourceVersion)")
        case .compositionCommitted(let sourceVersion, let replacementLength):
            logger.debug("compositionCommitted rev=\(sourceVersion) replLen=\(replacementLength)")
        case .compositionCancelled:
            logger.debug("compositionCancelled")
        case .compositionRefusedStale:
            logger.fault("compositionRefusedStale")
        case .imageCacheStore(let cost, let totalBytes):
            logger.debug("imageCacheStore cost=\(cost) total=\(totalBytes)")
        }
    }
}
