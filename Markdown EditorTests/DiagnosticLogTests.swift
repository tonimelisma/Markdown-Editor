//
//  DiagnosticLogTests.swift
//  Markdown EditorTests
//
//  REQ-089/095/096; ARC-016: per-run JSON Lines diagnostics that cannot represent content.
//

import Testing
import AppKit
import Foundation
@testable import Markdown_Editor

@MainActor
struct DiagnosticLogTests {

    @Test func samplerComputesPercentilesFromKnownDistribution() {
        let sampler = PerformanceSampler(trace: nil)
        for value in 1...100 { sampler.record(.keystrokeTranslation, durationNanos: UInt64(value)) }
        #expect(sampler.drainSummaries() == [.init(metric: .keystrokeTranslation, count: 100, p50: 50, p95: 95, max: 100)])
    }

    @Test func budgetExceededIsRecordedWhenP95OverBudget() {
        let trace = InMemoryEditorTrace()
        let sampler = PerformanceSampler(trace: trace)
        sampler.record(.modeToggle, durationNanos: 20_000_000)
        sampler.flush()
        #expect(trace.events.contains(.budgetExceeded(metric: .modeToggle, p95Nanos: 20_000_000, budgetNanos: 16_000_000)))
    }

    @Test func performanceSummaryOmitsPerEventTimings() {
        let trace = InMemoryEditorTrace()
        let sampler = PerformanceSampler(trace: trace)
        sampler.record(.reconciliation, durationNanos: 1)
        #expect(trace.events.isEmpty)
        sampler.flush()
        #expect(trace.events.count == 1)
    }

    private func makeTemporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("diagnostics-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Decodes one JSON Lines record into a dictionary.
    private func object(_ line: String) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any]
    }

    private func lines(of log: DiagnosticLog) async -> [String] {
        await log.drain()
        let text = (try? String(contentsOf: log.fileURL, encoding: .utf8)) ?? ""
        return text.split(separator: "\n").map(String.init)
    }

    // Verifies: REQ-089; ARC-016 — the payload value type has no string case, so document
    // content, URLs, filenames, and paths are unrepresentable rather than merely omitted.
    @Test func diagnosticPayloadHasNoStringCase() {
        // Exhaustive over `DiagnosticValue`: adding a `.string` case fails to compile here.
        let samples: [DiagnosticValue] = [
            .int(-3), .uint(7), .double(1.5), .bool(true), .symbol(.wysiwyg)
        ]
        for value in samples {
            switch value {
            case .int, .uint, .double, .bool, .symbol:
                continue
            }
        }
        // Every symbol is a compile-time literal from a closed vocabulary.
        #expect(DiagnosticSymbol.allCases.allSatisfy { !$0.rawValue.isEmpty })
        #expect(DiagnosticValue.symbol(.setLink).jsonFragment == "\"setLink\"")
    }

    // Verifies: REQ-089; ARC-016 — every event name in the vocabulary is reachable from a
    // mapping whose payload fields are numbers, booleans, or closed symbols, and every
    // emitted line survives JSON parsing.
    @Test func everyTraceEventMapsToSymbolicPayload() {
        let events: [EditorTraceEvent] = [
            .mutationRequested(id: UUID(), revision: 1, location: 0, length: 1, replacementLength: 2),
            .mutationCommitted(id: UUID(), newRevision: 2, location: 0, length: 1, replacementLength: 2),
            .mutationRefused(id: UUID(), reason: .contentMismatch),
            .undoRegistered(actionNameLength: 6, groupingTyping: true),
            .historyApplied(direction: .undo, newRevision: 3, location: 0, length: 1),
            .historyRefused(direction: .redo, reason: .conflict),
            .parseStarted(sourceVersion: 1, utf16Count: 10),
            .parseCompleted(sourceVersion: 1),
            .parseCancelled(sourceVersion: 1),
            .modeToggle(toSource: true),
            .compositionBegan(sourceVersion: 1),
            .compositionCommitted(sourceVersion: 1, replacementLength: 2),
            .compositionCancelled,
            .compositionRefusedStale,
            .imageCacheStore(cost: 10, totalBytes: 20),
            .editRouted(context: .wysiwyg, groupingTyping: true, planner: PlannerKind(.toggleBold)),
            .presentationInstalled(snapshotID: 1, sourceRevision: 1, provisional: false),
            .presentationTransition(from: 1, to: 2, sourceRevision: 2, durationNanos: 5),
            .reconciliationScheduled(sourceRevision: 1, generation: 1),
            .reconciliationDiscarded(sourceRevision: 1, reason: .identityMismatch),
            .reconciliationApplied(snapshotID: 1, sourceRevision: 1, generation: 1, durationNanos: 5),
            .editRefused(category: .refusal(.crossCell)),
            .editRefused(category: .invalidPresentationTransition),
            .availabilityChanged(editable: true, sourceRevision: 1),
            .updateOrigin(.modeRestoration),
            .documentOpened(utf16Count: 8),
            .documentClosed(sourceRevision: 4),
            .documentLoaded(utf16Count: 8, sourceRevision: 1),
            .documentLoadFailed(reason: .invalidUTF8),
            .documentSaveStarted(utf16Count: 8),
            .documentSaveSucceeded(utf16Count: 8, sourceRevision: 1, durationNanos: 5),
            .documentSaveFailed(reason: .saveFailedOrCancelled),
            .documentReverted(sourceRevision: 2, utf16Count: 8),
            .hostUpdateEnded(durationNanos: 5, updatesInWindow: 1),
            .hostUpdateStorm(updatesInWindow: 500),
            .viewReconciliationViolation(kind: .publication),
            .imagePlacementPhase(from: .idle, to: .accepted),
            .imagePlacementStarted(claimCount: 1),
            .imagePlacementCommitted(fileCount: 1, totalBytes: 100, durationNanos: 5),
            .imagePlacementFailed(reason: .writeFailed, phase: .staging),
            .imagePlacementRolledBack(removedFileCount: 1),
            .assetDirectoryPublished(fileCount: 1, totalBytes: 100),
            .userAlertPresented(severity: .error, reason: .placement(.busy))
            , .performanceSummary(metric: .keystrokeTranslation, count: 2, p50Nanos: 3, p95Nanos: 4, maxNanos: 5)
            , .budgetExceeded(metric: .modeToggle, p95Nanos: 17, budgetNanos: 16)
        ]

        var covered = Set<DiagnosticEventName>()
        for event in events {
            let mapped = JSONLinesEditorTrace.map(event)
            covered.insert(mapped.name)
            let record = DiagnosticRecord(
                wallClock: Date(),
                uptimeSeconds: 0,
                sequence: 1,
                level: mapped.level,
                category: mapped.category,
                event: mapped.name,
                document: 1,
                data: mapped.data
            )
            let decoded = object(record.jsonLine)
            #expect(decoded != nil, "mapped record is not valid JSON: \(record.jsonLine)")
        }

        // Produced outside the EditorTraceEvent mapping: the log's own lifecycle events, plus
        // mainActorStall, which the app delegate's watchdog records directly through
        // DiagnosticLog (COR-12; documented in ENGINEERING.md §11) since it observes a
        // process-level condition with no document or EditorTraceSink in scope.
        let logOwned: Set<DiagnosticEventName> = [
            .runStart, .runEnd, .repeated, .sizeLimitReached, .mainActorStall
        ]
        let unreachable = Set(DiagnosticEventName.allCases).subtracting(covered).subtracting(logOwned)
        #expect(unreachable.isEmpty, "unmapped event names: \(unreachable.map(\.rawValue).sorted())")
    }

    // Verifies: REQ-095 — the run header survives a hostile runtime version string, which is
    // the only non-literal text anywhere in the format.
    @Test func runHeaderEscapesHostileVersionStrings() {
        let header = DiagnosticRunHeader(
            runID: "abc",
            startedAt: Date(timeIntervalSince1970: 0),
            hostKind: .production,
            shortVersion: "1.0 \"beta\"",
            buildVersion: "back\\slash",
            osVersion: "Version 27.0 \"X\"",
            processID: 42
        )
        let decoded = object(header.jsonLine)
        let run = decoded?["run"] as? [String: Any]
        #expect(run?["version"] as? String == "1.0 \"beta\"")
        #expect(run?["os"] as? String == "Version 27.0 \"X\"")
    }

    // Verifies: REQ-095 — the first record identifies the run, including whether it is
    // production usage or a hosted test run.
    @Test func runHeaderIdentifiesHostKindAndBuild() async {
        let log = DiagnosticLog(directory: makeTemporaryDirectory(), hostKind: .unitTest)
        log.record(.documentOpened, level: .info, category: .document, document: 1)
        let recorded = await lines(of: log)

        #expect(recorded.count >= 2)
        let header = object(recorded[0])
        let run = header?["run"] as? [String: Any]
        #expect(run?["host"] as? String == "unitTest")
        #expect(run?["id"] as? String != nil)
        #expect(run?["build"] as? String != nil)
        #expect(header?["v"] as? Int == DiagnosticRunHeader.schemaVersion)
    }

    // Verifies: REQ-095 — every record is one parsable JSON object on its own line with a
    // strictly increasing sequence number, so a truncated run still reads cleanly.
    @Test func everyRecordIsOneParsableJSONLine() async {
        let log = DiagnosticLog(directory: makeTemporaryDirectory(), hostKind: .unitTest)
        for index in 0..<10 {
            log.record(
                .presentationInstalled,
                level: .debug,
                category: .projection,
                document: 1,
                data: [(.snapshot, .uint(UInt64(index)))]
            )
        }
        let recorded = await lines(of: log)

        var previousSequence = -1
        for line in recorded {
            let decoded = object(line)
            #expect(decoded != nil, "line is not valid JSON")
            let sequence = decoded?["seq"] as? Int ?? -1
            #expect(sequence > previousSequence)
            previousSequence = sequence
        }
        #expect(recorded.count == 11)
    }

    // Verifies: REQ-095 — the terminating record distinguishes a clean exit from a crash.
    @Test func finishWritesTerminatingRecord() async {
        let log = DiagnosticLog(directory: makeTemporaryDirectory(), hostKind: .unitTest)
        log.record(.documentOpened, level: .info, category: .document)
        log.finish()
        let recorded = await lines(of: log)

        #expect(recorded.last?.contains("\"ev\":\"runEnd\"") == true)
        // Records after termination are dropped rather than appended past the end marker.
        log.record(.documentClosed, level: .info, category: .document)
        let afterFinish = await lines(of: log)
        #expect(afterFinish.count == recorded.count)
    }

    // Verifies: REQ-096 — a defect firing every run-loop pass produces bounded evidence.
    @Test func repeatedEventsCollapseWithCount() async {
        let log = DiagnosticLog(directory: makeTemporaryDirectory(), hostKind: .unitTest)
        let burst = DiagnosticLog.repeatCollapseThreshold * 5
        for _ in 0..<burst {
            log.record(.hostUpdateEnded, level: .debug, category: .viewUpdate)
        }
        log.finish()
        let recorded = await lines(of: log)

        let emitted = recorded.filter { $0.contains("\"ev\":\"hostUpdateEnded\"") }.count
        #expect(emitted <= DiagnosticLog.repeatCollapseThreshold + 1)
        let summaries = recorded.filter {
            $0.contains("\"ev\":\"repeated\"") && $0.contains("\"of\":\"hostUpdateEnded\"")
        }
        #expect(summaries.count == 1)
        let suppressed = burst - emitted
        #expect(summaries.first?.contains("\"count\":\(suppressed)") == true)
    }

    // Verifies: REQ-095 — per-file size is bounded, and reaching the cap is recorded as a
    // well-formed record rather than a hand-written fragment that would break the schema.
    @Test func fileSizeCapIsBoundedAndRecorded() async {
        let directory = makeTemporaryDirectory()
        let log = DiagnosticLog(directory: directory, hostKind: .unitTest)
        let sink = DiagnosticFileSink(url: log.fileURL, byteLimit: 200)
        // Fill past a deliberately tiny cap.
        var reachedCap = false
        for index in 0..<50 where !reachedCap {
            reachedCap = await sink.append(["{\"seq\":\(index)}"])
        }
        #expect(reachedCap)

        let written = (try? String(contentsOf: log.fileURL, encoding: .utf8)) ?? ""
        #expect(written.utf8.count <= 200)
        for line in written.split(separator: "\n") {
            #expect(object(String(line)) != nil)
        }
    }

    // Verifies: REQ-095 — retention keeps the newest runs and removes the oldest.
    @Test func retentionRemovesOldestRuns() throws {
        let directory = makeTemporaryDirectory()
        let manager = FileManager.default
        // Distinct modification dates so ordering is deterministic.
        for index in 0..<8 {
            let url = directory.appendingPathComponent("run-2026072\(index)T000000Z-\(index).jsonl")
            manager.createFile(atPath: url.path, contents: Data("{}\n".utf8))
            try manager.setAttributes(
                [.modificationDate: Date(timeIntervalSince1970: 1_000 + Double(index) * 60)],
                ofItemAtPath: url.path
            )
        }

        DiagnosticLog.pruneRuns(in: directory, keeping: 3)

        let remaining = try manager.contentsOfDirectory(atPath: directory.path).sorted()
        #expect(remaining.count == 3)
        #expect(remaining.contains("run-20260727T000000Z-7.jsonl"))
        #expect(!remaining.contains("run-20260720T000000Z-0.jsonl"))
    }

    // Verifies: REQ-095 — a document wires the production sink and records its own lifecycle.
    @Test func documentRecordsLifecycleThroughSink() async {
        let log = DiagnosticLog(directory: makeTemporaryDirectory(), hostKind: .unitTest)
        let document = MarkdownDocument()
        document.trace = JSONLinesEditorTrace(log: log)
        document.installTextForTesting("# Hello\n")
        document.trace?.record(.documentOpened(utf16Count: 8))
        let recorded = await lines(of: log)

        let opened = recorded.filter { $0.contains("\"ev\":\"documentOpened\"") }
        #expect(opened.count == 1)
        #expect(opened.first?.contains("\"utf16Count\":8") == true)
        // Documents appear as opaque handles, never as names or paths.
        #expect(opened.first?.contains("\"doc\":1") == true)
    }

    // Verifies: REQ-100 — a load failure (the only throw site: invalid UTF-8) is recorded
    // before NSDocument's own error is rethrown.
    @Test func documentLoadFailureIsRecorded() async {
        let log = DiagnosticLog(directory: makeTemporaryDirectory(), hostKind: .unitTest)
        let document = MarkdownDocument()
        document.trace = JSONLinesEditorTrace(log: log)

        #expect(throws: CocoaError.self) {
            try document.read(from: Data([0xFF, 0xFE, 0xFD]), ofType: MarkdownContentType.identifier)
        }

        let recorded = await lines(of: log)
        let failed = recorded.filter { $0.contains("\"ev\":\"documentLoadFailed\"") }
        #expect(failed.count == 1)
        #expect(failed.first?.contains("\"lvl\":\"error\"") == true)
        #expect(failed.first?.contains("\"reason\":\"invalidUTF8\"") == true)
    }

    // Verifies: REQ-100 — a failure reading the URL itself (never reaching the Data-based
    // override at all) is still recorded, distinctly from an invalid-UTF-8 content failure.
    @Test func documentLoadFailureForUnreadableURLIsRecorded() async {
        let log = DiagnosticLog(directory: makeTemporaryDirectory(), hostKind: .unitTest)
        let document = MarkdownDocument()
        document.trace = JSONLinesEditorTrace(log: log)
        let nonexistent = FileManager.default.temporaryDirectory
            .appendingPathComponent("no-such-file-\(UUID().uuidString).md")

        #expect(throws: (any Error).self) {
            try document.read(from: nonexistent, ofType: MarkdownContentType.identifier)
        }

        let recorded = await lines(of: log)
        let failed = recorded.filter { $0.contains("\"ev\":\"documentLoadFailed\"") }
        #expect(failed.count == 1)
        #expect(failed.first?.contains("\"reason\":\"fileUnreadable\"") == true)
    }

    // Verifies: REQ-100 — a real, valid file still reaches the Data-based override normally
    // through the URL-based override (no failure recorded on the healthy path).
    @Test func documentLoadThroughURLRecordsNoFailure() async throws {
        let log = DiagnosticLog(directory: makeTemporaryDirectory(), hostKind: .unitTest)
        let document = MarkdownDocument()
        document.trace = JSONLinesEditorTrace(log: log)
        let url = makeTemporaryDirectory().appendingPathComponent("valid.md")
        try Data("# Hello\n".utf8).write(to: url)

        try document.read(from: url, ofType: MarkdownContentType.identifier)

        let recorded = await lines(of: log)
        #expect(recorded.filter { $0.contains("\"ev\":\"documentLoadFailed\"") }.isEmpty)
        #expect(recorded.filter { $0.contains("\"ev\":\"documentLoaded\"") }.count == 1)
    }

    // Verifies: REQ-100 — a document saved for the first time while still untouched (revision
    // 0, never yet read from any file) and then reverted is classified as a revert, not a load.
    // sourceVersion alone cannot distinguish this case (Save never advances it), which is
    // exactly why isRevertingViaAppKit exists rather than relying on sourceVersion == 0.
    @Test func revertOfNeverBeforeLoadedDocumentIsClassifiedAsRevert() async throws {
        let log = DiagnosticLog(directory: makeTemporaryDirectory(), hostKind: .unitTest)
        let document = MarkdownDocument()
        document.trace = JSONLinesEditorTrace(log: log)
        // The document itself is never loaded from a file before this — it starts blank via
        // init(), exactly like a real File > New document that was then saved without edits.
        let url = makeTemporaryDirectory().appendingPathComponent("untouched.md")
        try Data().write(to: url)

        try document.revert(toContentsOf: url, ofType: MarkdownContentType.identifier)

        let recorded = await lines(of: log)
        #expect(recorded.filter { $0.contains("\"ev\":\"documentReverted\"") }.count == 1)
        #expect(recorded.filter { $0.contains("\"ev\":\"documentLoaded\"") }.isEmpty)
    }

    // Verifies: REQ-100 — a save whose destination was never determined (the Save-panel-cancel
    // case: DocumentSaveBridge reports failure without save(to:ofType:for:completionHandler:)
    // ever firing) is still recorded, not silently dropped because it took a different path
    // than a write that was actually attempted.
    @Test func documentSaveCancelledBeforeDestinationIsRecorded() async {
        let log = DiagnosticLog(directory: makeTemporaryDirectory(), hostKind: .unitTest)
        let document = MarkdownDocument()
        document.trace = JSONLinesEditorTrace(log: log)
        document.installTextForTesting("# Hello\n")

        final class NeverReachesSaveOverride: DocumentSaving {
            func saveDocument() async -> DocumentSaveOutcome { .cancelled }
        }
        document.saveExecutorOverride = NeverReachesSaveOverride()
        let outcome = await document.saveDocument()
        #expect(outcome == .cancelled)

        let recorded = await lines(of: log)
        let failed = recorded.filter { $0.contains("\"ev\":\"documentSaveFailed\"") }
        #expect(failed.count == 1)
    }

    // Verifies: REQ-100 — a save failure reaching save(to:ofType:for:completionHandler:) is
    // recorded at error level. Tests recordSaveOutcome directly with a synthetic error rather
    // than provoking a genuine AppKit save failure: two earlier attempts (a nonexistent parent
    // directory, then a permission-denied directory) each took 30+ seconds or hung outright in
    // a headless test host, apparently due to AppKit's own save-error recovery flow. The real
    // integration is exercised by documentIOTraceOmitsPaths (a genuine successful save) and by
    // documentSaveCancelledBeforeDestinationIsRecorded (the one failure path that is fast and
    // deterministic to drive for real).
    @Test func documentSaveFailureIsRecorded() async {
        let log = DiagnosticLog(directory: makeTemporaryDirectory(), hostKind: .unitTest)
        let document = MarkdownDocument()
        document.trace = JSONLinesEditorTrace(log: log)
        document.installTextForTesting("# Hello\n")

        document.recordSaveOutcome(
            error: CocoaError(.fileWriteNoPermission),
            utf16Count: 8,
            startUptimeNanos: DispatchTime.now().uptimeNanoseconds
        )

        let recorded = await lines(of: log)
        let failed = recorded.filter { $0.contains("\"ev\":\"documentSaveFailed\"") }
        #expect(failed.count == 1)
        #expect(failed.first?.contains("\"lvl\":\"error\"") == true)
        #expect(failed.first?.contains("\"reason\":\"saveFailedOrCancelled\"") == true)
        #expect(recorded.filter { $0.contains("\"ev\":\"documentSaveSucceeded\"") }.isEmpty)
    }

    // Verifies: REQ-100; ARC-016 — the highest-value privacy test in this increment: a
    // revealing file URL must never reach any emitted trace line across a real load and a real
    // (successful) save.
    @Test func documentIOTraceOmitsPaths() async throws {
        let log = DiagnosticLog(directory: makeTemporaryDirectory(), hostKind: .unitTest)
        let document = MarkdownDocument()
        document.trace = JSONLinesEditorTrace(log: log)
        let revealingURL = makeTemporaryDirectory().appendingPathComponent("secret-document-name.md")
        defer { try? FileManager.default.removeItem(at: revealingURL) }
        document.fileURL = revealingURL

        try document.read(from: Data("# Hello\n".utf8), ofType: MarkdownContentType.identifier)
        let outcome = await document.saveDocument()
        #expect(outcome == .succeeded)

        let recorded = await lines(of: log)
        #expect(!recorded.isEmpty)
        for line in recorded {
            #expect(!line.contains("secret-document-name"), "path leaked into trace line: \(line)")
        }
    }

    // Verifies: REQ-097 — an explicit override directory takes priority over both the
    // production and unit-test defaults, so verification runs cannot touch the user's own log
    // directory.
    @Test func diagnosticsDirectoryHonoursEnvironmentOverride() {
        let override = makeTemporaryDirectory().path
        let productionResolved = DiagnosticLog.defaultDirectory(
            hostKind: .production,
            environment: ["MARKDOWN_EDITOR_DIAGNOSTICS_DIR": override]
        )
        let unitTestResolved = DiagnosticLog.defaultDirectory(
            hostKind: .unitTest,
            environment: ["MARKDOWN_EDITOR_DIAGNOSTICS_DIR": override]
        )
        #expect(productionResolved.path == override)
        #expect(unitTestResolved.path == override)

        let withoutOverride = DiagnosticLog.defaultDirectory(hostKind: .production, environment: [:])
        #expect(withoutOverride.path != override)

        let emptyOverride = DiagnosticLog.defaultDirectory(
            hostKind: .production,
            environment: ["MARKDOWN_EDITOR_DIAGNOSTICS_DIR": ""]
        )
        #expect(emptyOverride.path == withoutOverride.path)
    }
}
