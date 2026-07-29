//
//  JSONLinesEditorTrace.swift
//  Markdown Editor
//

import Foundation

/// Production editor trace sink. Maps typed editor events onto JSON Lines diagnostic records.
///
/// // REQ-089/095/096; ARC-016: the only production instrumentation route. There is no
/// // `os_log` path for editor events, and no mapping below can emit a string that originated
/// // outside this file.
@MainActor
final class JSONLinesEditorTrace: EditorTraceSink {
    private let log: DiagnosticLog
    /// Opaque per-run handle identifying the document this sink belongs to.
    private let documentHandle: UInt64

    init(log: DiagnosticLog) {
        self.log = log
        self.documentHandle = log.makeDocumentHandle()
    }

    func record(_ event: EditorTraceEvent) {
        let mapped = Self.map(event)
        log.record(
            mapped.name,
            level: mapped.level,
            category: mapped.category,
            document: documentHandle,
            data: mapped.data
        )
    }

    struct Mapped {
        let name: DiagnosticEventName
        let level: DiagnosticLevel
        let category: DiagnosticCategory
        let data: [(key: DiagnosticField, value: DiagnosticValue)]
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    static func map(_ event: EditorTraceEvent) -> Mapped {
        switch event {
        case .mutationRequested(_, let revision, let location, let length, let replacementLength):
            return Mapped(name: .mutationRequested, level: .debug, category: .document, data: [
                (.revision, .uint(revision)),
                (.location, .int(location)),
                (.length, .int(length)),
                (.replacementLength, .int(replacementLength))
            ])
        case .mutationCommitted(_, let newRevision, let location, let length, let replacementLength):
            return Mapped(name: .mutationCommitted, level: .debug, category: .document, data: [
                (.revision, .uint(newRevision)),
                (.location, .int(location)),
                (.length, .int(length)),
                (.replacementLength, .int(replacementLength))
            ])
        case .mutationRefused(_, let reason):
            return Mapped(name: .mutationRefused, level: .error, category: .document, data: [
                (.reason, .symbol(reason.symbol))
            ])
        case .undoRegistered(let actionNameLength, let groupingTyping):
            return Mapped(name: .undoRegistered, level: .debug, category: .document, data: [
                (.nameLength, .int(actionNameLength)),
                (.grouping, .bool(groupingTyping))
            ])
        case .historyApplied(let direction, let newRevision, let location, let length):
            return Mapped(name: .historyApplied, level: .debug, category: .document, data: [
                (.direction, .symbol(direction.symbol)),
                (.revision, .uint(newRevision)),
                (.location, .int(location)),
                (.length, .int(length))
            ])
        case .historyRefused(let direction, let reason):
            return Mapped(name: .historyRefused, level: .error, category: .document, data: [
                (.direction, .symbol(direction.symbol)),
                (.reason, .symbol(reason.symbol))
            ])
        case .parseStarted(let sourceVersion, let utf16Count):
            return Mapped(name: .parseStarted, level: .debug, category: .projection, data: [
                (.sourceRevision, .uint(sourceVersion)),
                (.utf16Count, .int(utf16Count))
            ])
        case .parseCompleted(let sourceVersion):
            return Mapped(name: .parseCompleted, level: .debug, category: .projection, data: [
                (.sourceRevision, .uint(sourceVersion))
            ])
        case .parseCancelled(let sourceVersion):
            return Mapped(name: .parseCancelled, level: .debug, category: .projection, data: [
                (.sourceRevision, .uint(sourceVersion))
            ])
        case .modeToggle(let toSource):
            return Mapped(name: .modeToggle, level: .info, category: .edit, data: [
                (.mode, .symbol(toSource ? .source : .wysiwyg))
            ])
        case .compositionBegan(let sourceVersion):
            return Mapped(name: .compositionBegan, level: .debug, category: .edit, data: [
                (.sourceRevision, .uint(sourceVersion))
            ])
        case .compositionCommitted(let sourceVersion, let replacementLength):
            return Mapped(name: .compositionCommitted, level: .debug, category: .edit, data: [
                (.sourceRevision, .uint(sourceVersion)),
                (.replacementLength, .int(replacementLength))
            ])
        case .compositionCancelled:
            return Mapped(name: .compositionCancelled, level: .debug, category: .edit, data: [])
        case .compositionRefusedStale:
            return Mapped(name: .compositionRefusedStale, level: .error, category: .edit, data: [])
        case .imageCacheStore(let cost, let totalBytes):
            return Mapped(name: .imageCacheStore, level: .debug, category: .image, data: [
                (.cost, .int(cost)),
                (.totalBytes, .int(totalBytes))
            ])
        case .editRouted(let context, let groupingTyping, let planner):
            return Mapped(name: .editRouted, level: .debug, category: .edit, data: [
                (.mode, .symbol(context.symbol)),
                (.grouping, .bool(groupingTyping)),
                (.planner, .symbol(planner.symbol))
            ])
        case .presentationInstalled(let snapshotID, let sourceRevision, let provisional):
            return Mapped(name: .presentationInstalled, level: .debug, category: .projection, data: [
                (.snapshot, .uint(snapshotID)),
                (.sourceRevision, .uint(sourceRevision)),
                (.provisional, .bool(provisional))
            ])
        case .presentationTransition(let from, let to, let sourceRevision, let durationNanos):
            return Mapped(name: .presentationTransition, level: .debug, category: .projection, data: [
                (.fromSnapshot, .uint(from)),
                (.snapshot, .uint(to)),
                (.sourceRevision, .uint(sourceRevision)),
                (.durationNanos, .uint(durationNanos))
            ])
        case .reconciliationScheduled(let sourceRevision, let generation):
            return Mapped(name: .reconciliationScheduled, level: .debug, category: .projection, data: [
                (.sourceRevision, .uint(sourceRevision)),
                (.generation, .uint(generation))
            ])
        case .reconciliationDiscarded(let sourceRevision, let reason):
            return Mapped(name: .reconciliationDiscarded, level: .info, category: .projection, data: [
                (.sourceRevision, .uint(sourceRevision)),
                (.reason, .symbol(reason.symbol))
            ])
        case .reconciliationApplied(let snapshotID, let sourceRevision, let generation, let durationNanos):
            return Mapped(name: .reconciliationApplied, level: .debug, category: .projection, data: [
                (.snapshot, .uint(snapshotID)),
                (.sourceRevision, .uint(sourceRevision)),
                (.generation, .uint(generation)),
                (.durationNanos, .uint(durationNanos))
            ])
        case .editRefused(let category):
            return Mapped(name: .editRefused, level: .info, category: .edit, data: [
                (.reason, .symbol(category.symbol))
            ])
        case .availabilityChanged(let editable, let sourceRevision):
            return Mapped(name: .availabilityChanged, level: .debug, category: .session, data: [
                (.editable, .bool(editable)),
                (.sourceRevision, .uint(sourceRevision))
            ])
        case .updateOrigin(let origin):
            return Mapped(name: .updateOrigin, level: .debug, category: .session, data: [
                (.origin, .symbol(origin.symbol))
            ])
        case .documentOpened(let utf16Count):
            return Mapped(name: .documentOpened, level: .info, category: .document, data: [
                (.utf16Count, .int(utf16Count))
            ])
        case .documentClosed(let sourceRevision):
            return Mapped(name: .documentClosed, level: .info, category: .document, data: [
                (.revision, .uint(sourceRevision))
            ])
        case .hostUpdateEnded(let durationNanos, let updatesInWindow):
            return Mapped(name: .hostUpdateEnded, level: .debug, category: .viewUpdate, data: [
                (.durationNanos, .uint(durationNanos)),
                (.updatesPerSecond, .int(updatesInWindow))
            ])
        case .hostUpdateStorm(let updatesInWindow):
            return Mapped(name: .hostUpdateStorm, level: .fault, category: .viewUpdate, data: [
                (.updatesPerSecond, .int(updatesInWindow)),
                (.windowMillis, .int(1000))
            ])
        case .viewReconciliationViolation(let kind):
            return Mapped(name: .viewReconciliationViolation, level: .fault, category: .viewUpdate, data: [
                (.kind, .symbol(kind.symbol))
            ])
        }
    }
}
