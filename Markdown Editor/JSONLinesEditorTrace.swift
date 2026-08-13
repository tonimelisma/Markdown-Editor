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
    private let origin: DiagnosticEvidenceOrigin
    /// Unit-test production routes write a separate synchronous evidence stream. The encoder
    /// probe below never enters it, so a symbolic vocabulary cannot satisfy observed coverage.
    private let coverageRecorder: ProductionRouteCoverageRecorder?
    /// Opaque per-run handle identifying the document this sink belongs to.
    private let documentHandle: UInt64?

    init(log: DiagnosticLog, origin: DiagnosticEvidenceOrigin = .productionRoute) {
        self.log = log
        self.origin = origin
        self.coverageRecorder = Self.makeCoverageRecorder(for: log, origin: origin)
        self.documentHandle = log.makeDocumentHandle()
    }

    init(
        log: DiagnosticLog,
        documentHandle: UInt64?,
        origin: DiagnosticEvidenceOrigin = .productionRoute
    ) {
        self.log = log
        self.origin = origin
        self.coverageRecorder = Self.makeCoverageRecorder(for: log, origin: origin)
        self.documentHandle = documentHandle
    }

    func record(_ event: EditorTraceEvent) {
        let mapped = Self.map(event)
        log.record(
            mapped.name,
            level: mapped.level,
            category: mapped.category,
            document: documentHandle,
            origin: origin,
            data: mapped.data
        )
        coverageRecorder?.record(mapped)
    }

    private static func makeCoverageRecorder(
        for log: DiagnosticLog,
        origin: DiagnosticEvidenceOrigin
    ) -> ProductionRouteCoverageRecorder? {
        guard origin == .productionRoute,
              log.header.hostKind == .unitTest else { return nil }
        return ProductionRouteCoverageRecorder(directory: hostedCoverageDirectory())
    }

    @MainActor
    final class ProductionRouteCoverageRecorder {
        private let handle: FileHandle?
        private let startedAt: Date
        private let startUptimeNanos: UInt64
        private var nextSequence: UInt64 = 0

        init?(directory: URL) {
            guard FileManager.default.fileExists(
                atPath: directory.appendingPathComponent(".enabled").path
            ) else { return nil }
            startedAt = Date()
            startUptimeNanos = DispatchTime.now().uptimeNanoseconds
            let runID = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12))
            let header = DiagnosticRunHeader(
                runID: runID,
                startedAt: startedAt,
                hostKind: .unitTest,
                shortVersion: "0",
                buildVersion: "0",
                osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
                processID: ProcessInfo.processInfo.processIdentifier
            )
            try? FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            let fileURL = directory.appendingPathComponent(
                "run-\(DiagnosticTimestamp.compactUTC(startedAt))-\(runID).jsonl"
            )
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
            handle = try? FileHandle(forWritingTo: fileURL)
            append(header.jsonLine)
        }

        func record(_ mapped: Mapped) {
            record(
                event: mapped.name,
                level: mapped.level,
                category: mapped.category,
                data: mapped.data
            )
        }

        func record(
            event: DiagnosticEventName,
            level: DiagnosticLevel,
            category: DiagnosticCategory,
            data: [(key: DiagnosticField, value: DiagnosticValue)]
        ) {
            nextSequence &+= 1
            let uptime = Double(DispatchTime.now().uptimeNanoseconds - startUptimeNanos) / 1_000_000_000
            let record = DiagnosticRecord(
                wallClock: Date(),
                uptimeSeconds: uptime,
                sequence: nextSequence,
                level: level,
                category: category,
                event: event,
                origin: .productionRoute,
                data: data
            )
            append(record.jsonLine)
        }

        private func append(_ line: String) {
            guard let data = (line + "\n").data(using: .utf8) else { return }
            try? handle?.write(contentsOf: data)
        }
    }

    static func hostedCoverageDirectory() -> URL {
        let filePath = #filePath as NSString
        let sourceDir = filePath.deletingLastPathComponent as NSString
        let repoRoot = sourceDir.deletingLastPathComponent
        return URL(fileURLWithPath: repoRoot, isDirectory: true)
            .appendingPathComponent(".build", isDirectory: true)
            .appendingPathComponent("instrumentation-coverage-tests", isDirectory: true)
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
        case .imageResolutionFailed(let reason):
            return Mapped(name: .imageResolutionFailed, level: .warn, category: .image, data: [
                (.reason, .symbol(reason.symbol))
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
        case .presentationRecovered(let snapshotID, let sourceRevision, let reason):
            return Mapped(name: .presentationRecovered, level: .fault, category: .projection, data: [
                (.snapshot, .uint(snapshotID)),
                (.sourceRevision, .uint(sourceRevision)),
                (.reason, .symbol(reason.symbol))
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
        case .documentLoaded(let utf16Count, let sourceRevision):
            return Mapped(name: .documentLoaded, level: .info, category: .document, data: [
                (.utf16Count, .int(utf16Count)),
                (.sourceRevision, .uint(sourceRevision))
            ])
        case .documentLoadFailed(let reason):
            return Mapped(name: .documentLoadFailed, level: .error, category: .document, data: [
                (.reason, .symbol(reason.symbol))
            ])
        case .documentSaveStarted(let utf16Count):
            return Mapped(name: .documentSaveStarted, level: .debug, category: .document, data: [
                (.utf16Count, .int(utf16Count))
            ])
        case .documentSaveSucceeded(let utf16Count, let sourceRevision, let durationNanos):
            return Mapped(name: .documentSaveSucceeded, level: .info, category: .document, data: [
                (.utf16Count, .int(utf16Count)),
                (.sourceRevision, .uint(sourceRevision)),
                (.durationNanos, .uint(durationNanos))
            ])
        case .documentSaveFailed(let reason):
            return Mapped(name: .documentSaveFailed, level: .error, category: .document, data: [
                (.reason, .symbol(reason.symbol))
            ])
        case .documentReverted(let sourceRevision, let utf16Count):
            return Mapped(name: .documentReverted, level: .info, category: .document, data: [
                (.sourceRevision, .uint(sourceRevision)),
                (.utf16Count, .int(utf16Count))
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
        case .imagePlacementPhase(let from, let to):
            return Mapped(name: .imagePlacementPhase, level: .debug, category: .image, data: [
                (.fromPhase, .symbol(from.symbol)),
                (.toPhase, .symbol(to.symbol))
            ])
        case .imagePlacementStarted(let claimCount):
            return Mapped(name: .imagePlacementStarted, level: .info, category: .image, data: [
                (.claimCount, .int(claimCount))
            ])
        case .imagePlacementCommitted(let fileCount, let totalBytes, let durationNanos):
            return Mapped(name: .imagePlacementCommitted, level: .info, category: .image, data: [
                (.fileCount, .int(fileCount)),
                (.totalBytes, .int(totalBytes)),
                (.durationNanos, .uint(durationNanos))
            ])
        case .imagePlacementFailed(let reason, let phase):
            return Mapped(name: .imagePlacementFailed, level: .error, category: .image, data: [
                (.reason, .symbol(reason.symbol)),
                (.phase, .symbol(phase.symbol))
            ])
        case .imagePlacementRolledBack(let removedFileCount):
            return Mapped(name: .imagePlacementRolledBack, level: .warn, category: .image, data: [
                (.removedFileCount, .int(removedFileCount))
            ])
        case .assetDirectoryPublished(let fileCount, let totalBytes):
            return Mapped(name: .assetDirectoryPublished, level: .debug, category: .image, data: [
                (.fileCount, .int(fileCount)),
                (.totalBytes, .int(totalBytes))
            ])
        case .userAlertPresented(let severity, let reason):
            let level: DiagnosticLevel = {
                switch severity {
                case .error: return .error
                case .warning: return .warn
                case .info: return .info
                }
            }()
            return Mapped(name: .userAlertPresented, level: level, category: .image, data: [
                (.level, .symbol(severity.symbol)),
                (.reason, .symbol(reason.symbol))
            ])
        case .performanceSummary(let metric, let count, let p50Nanos, let p95Nanos, let maxNanos):
            return Mapped(name: .performanceSummary, level: .info, category: .session, data: [
                (.metric, .symbol(metric.symbol)), (.count, .int(count)), (.p50Nanos, .uint(p50Nanos)),
                (.p95Nanos, .uint(p95Nanos)), (.maxNanos, .uint(maxNanos))
            ])
        case .budgetExceeded(let metric, let p95Nanos, let budgetNanos):
            return Mapped(name: .budgetExceeded, level: .warn, category: .session, data: [
                (.metric, .symbol(metric.symbol)), (.p95Nanos, .uint(p95Nanos)), (.budgetNanos, .uint(budgetNanos))
            ])
        case .sourceHighlightWidened(let reason):
            return Mapped(name: .sourceHighlightWidened, level: .info, category: .session, data: [
                (.reason, .symbol(reason.symbol))
            ])
        case .workLedger(let scope, let documentParses, let projectionCompiles, let oracleValidations, let attributedBuilds, let attributedCharactersWritten, let storageFullReplacements, let imageDecodes, let fileBytesRead, let mainThreadBlockedNanos):
            return Mapped(name: .workLedger, level: .debug, category: .diagnostics, data: [
                (.scope, .symbol(scope.symbol)),
                (.documentParses, .int(documentParses)),
                (.projectionCompiles, .int(projectionCompiles)),
                (.oracleValidations, .int(oracleValidations)),
                (.attributedBuilds, .int(attributedBuilds)),
                (.attributedCharactersWritten, .int(attributedCharactersWritten)),
                (.storageFullReplacements, .int(storageFullReplacements)),
                (.imageDecodes, .int(imageDecodes)),
                (.fileBytesRead, .int(fileBytesRead)),
                (.mainThreadBlockedNanos, .uint(mainThreadBlockedNanos)),
            ])
        case .frameStatistics(let hitchMillisPerSecond, let longestFrameNanos, let framesObserved):
            return Mapped(name: .frameStatistics, level: .info, category: .viewUpdate, data: [
                (.hitchMillisPerSecond, .double(hitchMillisPerSecond)),
                (.longestFrameNanos, .uint(longestFrameNanos)),
                (.framesObserved, .int(framesObserved)),
            ])
        case .memoryFootprint(let bytes, let peakBytes):
            return Mapped(name: .memoryFootprint, level: .info, category: .diagnostics, data: [
                (.bytes, .uint(bytes)),
                (.peakBytes, .uint(peakBytes)),
            ])
        }
    }
}
