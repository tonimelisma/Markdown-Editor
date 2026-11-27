//
//  DiagnosticLogTests.swift
//  Markdown EditorTests
//
//  REQ-089/095/096; ARC-016: per-run JSON Lines diagnostics that cannot represent content.
//

import Testing
import AppKit
import Foundation
import Darwin
@testable import Markdown_Editor

@MainActor
struct DiagnosticLogTests {

    @Test func samplerComputesPercentilesFromKnownDistribution() {
        let sampler = PerformanceSampler(trace: nil)
        for value in 1...100 { sampler.record(.nativeInputCallback, durationNanos: UInt64(value)) }
        #expect(sampler.drainSummaries() == [.init(metric: .nativeInputCallback, count: 100, p50: 50, p95: 95, max: 100)])
    }

    // Verifies: REQ-103 — a summary describes every sample of its window. The latency probe takes
    // 600 a minute; a ring of the newest 512 lost the first nine seconds of each minute, and a
    // print panel's first load there was absent from the count, the max and the p95.
    @Test func aSummaryCountsEverySampleOfItsWindowAndKeepsTheLargest() {
        let sampler = PerformanceSampler(trace: nil, coordinator: DiagnosticRunCoordinator())
        sampler.record(.mainActorLatency, durationNanos: 1_500_000_000)
        for _ in 1..<600 { sampler.record(.mainActorLatency, durationNanos: 1_000_000) }
        let summary = sampler.drainSummaries().first { $0.metric == .mainActorLatency }
        sampler.invalidate()
        #expect(summary?.count == 600)
        #expect(summary?.max == 1_500_000_000)
    }

    // Verifies: REQ-103 — the percentiles weigh the whole window, not its newest part: a slow
    // first sixth of the minute still sets the p95.
    @Test func thePercentilesWeighTheWholeWindow() {
        let sampler = PerformanceSampler(trace: nil, coordinator: DiagnosticRunCoordinator())
        for _ in 0..<200 { sampler.record(.mainActorLatency, durationNanos: 400_000_000) }
        for _ in 0..<1_000 { sampler.record(.mainActorLatency, durationNanos: 1_000_000) }
        let summary = sampler.drainSummaries().first { $0.metric == .mainActorLatency }
        sampler.invalidate()
        #expect(summary?.count == 1_200)
        #expect(summary?.p95 == 400_000_000, "summary: \(String(describing: summary))")
        #expect(summary?.p50 == 1_000_000, "summary: \(String(describing: summary))")
    }

    // Verifies: REQ-090 — the evidence type refuses a run with no executed samples, so a
    // latency gate cannot be reported as satisfied by having measured nothing.
    @Test func performanceEvidenceRejectsZeroSamples() {
        let evidence = PerformanceEvidence(warmups: 5, samples: [])
        #expect(evidence.samples.isEmpty)
        #expect(evidence.median == nil)
        #expect(evidence.p95 == nil)
        #expect(evidence.failures == ["no performance samples"])
    }

    // Verifies: REQ-103 — the bounded periodic summary records a budget breach.
    @Test func budgetExceededIsRecordedWhenP95OverBudget() {
        let trace = InMemoryEditorTrace()
        let sampler = PerformanceSampler(trace: trace)
        for _ in 0..<PerformanceSampler.samplesForAPercentile { sampler.record(.modeTransition, durationNanos: 20_000_000) }
        sampler.flush()
        #expect(trace.events.contains(.budgetExceeded(metric: .modeTransition, p95Nanos: 20_000_000, budgetNanos: 16_000_000)))
    }

    // Verifies: REQ-103 — a p95 is judged only from enough samples to be one. With fewer, the
    // nearest-rank p95 is the largest sample: five edits of a just-opened document were judged
    // by its first layout (tours 46012382716, 46013947916). They carry into the next window.
    @Test func aFewSamplesCarryIntoTheNextWindowBeforeTheirP95IsJudged() {
        let trace = InMemoryEditorTrace()
        let sampler = PerformanceSampler(trace: trace, coordinator: DiagnosticRunCoordinator())
        let budget = PerformanceSampler.budgetNanos[.layoutApplication]!
        for _ in 0..<5 { sampler.record(.layoutApplication, durationNanos: budget * 2) }
        sampler.flush()
        let judged: () -> [EditorTraceEvent] = {
            trace.eventsMatching {
                switch $0 {
                case .budgetExceeded(.layoutApplication, _, _), .performanceSummary(.layoutApplication, _, _, _, _): return true
                default: return false
                }
            }
        }
        #expect(judged().isEmpty, "five samples were summarised and judged as a p95: \(judged())")

        for _ in 5..<PerformanceSampler.samplesForAPercentile { sampler.record(.layoutApplication, durationNanos: budget * 2) }
        sampler.flush()
        #expect(trace.events.contains(.performanceSummary(metric: .layoutApplication, count: PerformanceSampler.samplesForAPercentile, p50Nanos: budget * 2, p95Nanos: budget * 2, maxNanos: budget * 2)), "the carried samples were lost")
        #expect(trace.events.contains(.budgetExceeded(metric: .layoutApplication, p95Nanos: budget * 2, budgetNanos: budget)), "twenty over-budget samples were not judged")
        sampler.invalidate()
    }

    // Verifies: REQ-103 — the last flush writes what remains, its largest included, and judges
    // no p95 it has too few samples for.
    @Test func theLastFlushWritesAFewSamplesWithoutJudgingThem() {
        let trace = InMemoryEditorTrace()
        let sampler = PerformanceSampler(trace: trace, coordinator: DiagnosticRunCoordinator())
        let budget = PerformanceSampler.budgetNanos[.layoutApplication]!
        for _ in 0..<5 { sampler.record(.layoutApplication, durationNanos: budget * 2) }
        sampler.invalidate()
        #expect(trace.events.contains(.performanceSummary(metric: .layoutApplication, count: 5, p50Nanos: budget * 2, p95Nanos: budget * 2, maxNanos: budget * 2)))
        #expect(!trace.events.contains(.budgetExceeded(metric: .layoutApplication, p95Nanos: budget * 2, budgetNanos: budget)), "five samples were judged as a p95")
    }

    // Verifies: REQ-103 — summaries are emitted on flush and never per keystroke. The flush
    // also emits the process memory sample used by the diagnostics contract.
    @Test func performanceSummaryOmitsPerEventTimings() {
        let trace = InMemoryEditorTrace()
        let sampler = PerformanceSampler(trace: trace)
        sampler.record(.parseProjection, durationNanos: 1)
        #expect(trace.events.isEmpty)
        sampler.flush(final: true)
        #expect(trace.events.count == 2)
        #expect(trace.events.contains { event in
            if case .performanceSummary(metric: .parseProjection, count: 1, p50Nanos: 1, p95Nanos: 1, maxNanos: 1) = event {
                return true
            }
            return false
        })
        #expect(trace.events.contains { event in
            if case .memoryFootprint = event { return true }
            return false
        })
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
    @Test func everyTraceEventMapsToSymbolicPayload() async {
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
            .externalFileChange(event: .contentsChanged, local: .clean, outcome: .reloadPreservingSelection, sourceRevision: 1),
            .compositionCancelled,
            .compositionRefusedStale,
            .imageDisplayCacheObserved(hit: true, bytesRead: 0, decodeCount: 0, durationNanos: 5, totalBytes: 20),
            // REQ-114: `oversizeDimensions` carries measurements in the Swift case; the mapping
            // must reduce it to a bare reason symbol so the payload cannot describe the file.
            .imageResolutionFailed(reason: .missingFile),
            .imageResolutionFailed(reason: .oversizeDimensions(width: 99_999, height: 99_999)),
            .editRouted(context: .wysiwyg, groupingTyping: true, planner: PlannerKind(.toggleBold)),
            .presentationInstalled(snapshotID: 1, sourceRevision: 1, provisional: false),
            .presentationTransition(from: 1, to: 2, sourceRevision: 2, durationNanos: 5),
            .presentationRecovered(snapshotID: 2, sourceRevision: 2, reason: .patchUnprovable),
            .presentationRecovered(snapshotID: 2, sourceRevision: 2, reason: .appliedStorageMismatch),
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
            , .performanceSummary(metric: .nativeInputCallback, count: 2, p50Nanos: 3, p95Nanos: 4, maxNanos: 5)
            , .budgetExceeded(metric: .modeTransition, p95Nanos: 17, budgetNanos: 16)
            , .sourceHighlightWidened(reason: .fenceParity)
            , .workLedger(
                scope: .acceptedEdit,
                documentParses: 1,
                projectionCompiles: 2,
                oracleValidations: 3,
                attributedBuilds: 4,
                attributedCharactersWritten: 5,
                storageFullReplacements: 6,
                imageDecodes: 7,
                fileBytesRead: 8,
                mainThreadBlockedNanos: 9
            )
            , .frameStatistics(hitchMillisPerSecond: 1.5, longestFrameNanos: 10, framesObserved: 11)
            , .memoryFootprint(bytes: 12, peakBytes: 13)
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

        let requestedPath = ProcessInfo.processInfo.environment["EDITOR_TRACE_COVERAGE_LOG_DIR"]
        // Fallback is kept for manual Xcode runs outside Scripts/check.sh.
        // The test's ordinary diagnostic log follows this per-checkout directory. Production
        // route evidence is captured separately through the gate-owned FIFO in the same
        // checkout's deterministic .build directory.
        let fallbackPath: String = {
            let filePath = #filePath as NSString
            // #filePath is .../<checkout>/Markdown EditorTests/DiagnosticLogTests.swift
            // Two components up is the checkout root.
            let testsDir = filePath.deletingLastPathComponent as NSString
            let repoRoot = testsDir.deletingLastPathComponent
            var hash: UInt64 = 1469598103934665603 // FNV-1a 64-bit offset
            for byte in repoRoot.utf8 {
                hash ^= UInt64(byte)
                hash &*= 1099511628211
            }
            let suffix = String(format: "%08x", UInt32(truncatingIfNeeded: hash))
            return URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                .appendingPathComponent("MarkdownEditorTraceCoverage-\(suffix)", isDirectory: true)
                .path
        }()
        let coveragePath = requestedPath.flatMap { $0.isEmpty ? nil : $0 } ?? fallbackPath
        let coverageLog = DiagnosticLog(
            directory: URL(fileURLWithPath: coveragePath, isDirectory: true),
            hostKind: .unitTest
        )
        let sink = JSONLinesEditorTrace.makeEncodingProbe(log: coverageLog)
        for event in events {
            sink.record(event)
        }
        coverageLog.finish()
        await coverageLog.drain()

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

    // Verifies: REQ-099/135 — a production sink emits an explicit production-route origin. The
    // closed encoder test above uses `encodingProbe` and cannot satisfy this assertion.
    @Test func productionRouteRecordsCarryExplicitProductionOrigin() async {
        let log = DiagnosticLog(directory: makeTemporaryDirectory(), hostKind: .unitTest)
        let sink = JSONLinesEditorTrace(log: log)
        sink.record(route: .documentOpened, .documentOpened(utf16Count: 8))
        let recorded = await lines(of: log)
        let event = recorded
            .compactMap(object)
            .first { ($0["ev"] as? String) == DiagnosticEventName.documentOpened.rawValue }
        #expect(event?["origin"] as? String == DiagnosticEvidenceOrigin.productionRoute.rawValue)
    }

    // Verifies: REQ-099 — an encoding probe's records stay visibly non-production even when it
    // emits a complete symbolic vocabulary, so the vocabulary check cannot be satisfied by a probe
    // rather than by a route a real run actually takes.
    @Test func encodingProbeRecordsCannotMasqueradeAsProductionRoute() async {
        let log = DiagnosticLog(directory: makeTemporaryDirectory(), hostKind: .unitTest)
        let sink = JSONLinesEditorTrace.makeEncodingProbe(log: log)
        sink.record(.documentOpened(utf16Count: 8))
        let recorded = await lines(of: log)
        let event = recorded
            .compactMap(object)
            .first { ($0["ev"] as? String) == DiagnosticEventName.documentOpened.rawValue }
        #expect(event?["origin"] as? String != DiagnosticEvidenceOrigin.productionRoute.rawValue)
    }

    // Verifies: REQ-089/111 — the real parse owner reports image resolution failure through its
    // document trace when a local attachment cannot be resolved.
    @Test func parseOwnerRecordsImageResolutionFailureOnTheProductionRoute() async {
        let document = MarkdownDocument()
        let trace = InMemoryEditorTrace()
        document.trace = trace
        document.installTextForTesting("![missing](missing-image.png)\n")
        let session = EditorSession()
        session.attach(document: document)
        for _ in 0..<200 {
            if trace.events.contains(where: {
                if case .imageResolutionFailed = $0 { return true }
                return false
            }) { break }
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(2))
        }
        #expect(trace.events.contains {
            if case .imageResolutionFailed = $0 { return true }
            return false
        })
        session.detach()
    }

    // Verifies: REQ-089/085 — the real parse owner emits cache telemetry for the dedicated service.
    @Test func parseOwnerRecordsImageDisplayCacheTelemetryOnTheProductionRoute() async throws {
        let directory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let assets = directory.appendingPathComponent("assets", isDirectory: true)
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Images/sample.png")
        try FileManager.default.copyItem(at: fixture, to: assets.appendingPathComponent("sample.png"))
        let document = MarkdownDocument()
        document.fileURL = directory.appendingPathComponent("document.md")
        let trace = InMemoryEditorTrace()
        document.trace = trace
        document.installTextForTesting("![](assets/sample.png)\n")
        let session = EditorSession()
        session.attach(document: document)
        for _ in 0..<200 {
            if trace.events.contains(where: {
                if case .imageDisplayCacheObserved = $0 { return true }
                return false
            }) { break }
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(2))
        }
        #expect(trace.events.contains {
            if case .imageDisplayCacheObserved(_, let bytes, let decodes, _, _) = $0 {
                return bytes > 0 && decodes == 1
            }
            return false
        })
        session.detach()
    }

    // Verifies: REQ-103 — `parseProjection` times the parse and the projection, not the parse
    // task's wait for the main actor between them. A showcase parse of a few milliseconds was
    // recorded at 875 ms while the main thread opened its window (tour 46011070302).
    @Test func parseProjectionLeavesOutTheWaitForTheMainActor() async {
        let document = MarkdownDocument()
        let trace = InMemoryEditorTrace()
        document.trace = trace
        let text = "# Title\n\nBody paragraph.\n"
        document.installTextForTesting(text)
        let session = EditorSession(performanceSamplerCoordinator: DiagnosticRunCoordinator())
        session.attach(document: document)
        defer { session.detach() }
        let revision = document.sourceVersion
        // Hold the main actor until the parse has finished off it, which the session's memo
        // shows, then half a second more: the parse's hop is then sure to have waited that long,
        // however long cmark's lock kept the parse waiting (CI 46020138506: 1.9 s).
        holdMainActor(until: { session.intentRecorder.parseMemo.tree(source: text, sourceVersion: revision) != nil }, then: 0.5)
        var whole: UInt64?
        for _ in 0..<2_000 where whole == nil {
            for event in trace.events {
                if case .reconciliationApplied(_, let applied, _, let duration) = event, applied == revision { whole = duration }
            }
            if whole == nil { try? await Task.sleep(for: .milliseconds(5)) }
        }
        let summary = session.performanceSampler?.drainSummaries().first { $0.metric == .parseProjection }
        #expect(whole != nil, "the parse never landed")
        #expect(summary != nil, "no parse was measured")
        if let whole, let summary {
            #expect(summary.max + 400_000_000 <= whole, "the wait for the main actor was timed as parsing: parse \(summary.max) ns of \(whole) ns")
        }
    }

    // Verifies: REQ-123 — a document opened before its window exists parses once when the window
    // opens on the main screen. The parse before the window guessed scale 2, so on a 1x display
    // (CI's runner, an external monitor) binding the window parsed it again. On a 2x host this
    // passes either way; CI's runner is 1x.
    @Test func aWindowOpenedAfterAttachOnTheMainScreenNeedsNoSecondParse() {
        let document = MarkdownDocument()
        document.installTextForTesting("hello\n")
        let session = EditorSession()
        session.attach(document: document)
        defer { session.detach() }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.titled], backing: .buffered, defer: true)
        let before = session.parseCoordinator.generation()
        session.bind(editorWindow: window)
        #expect(session.parseCoordinator.generation() == before, "binding a main-screen window parsed the document again")
    }

    // Verifies: ARC-023 — a backing change from the session's own window that changes the scale
    // images were decoded for invalidates the current generation and schedules a fresh display
    // request; one that leaves the scale as it was (a colour-space change, say) parses nothing.
    // The first window bound used to count as a change, and every open parsed twice.
    @Test func owningWindowBackingChangeStartsNewGeneration() async {
        let document = MarkdownDocument()
        document.installTextForTesting("hello\n")
        let session = EditorSession()
        let window = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: true)
        session.bind(editorWindow: window)
        session.attach(document: document)
        let unchanged = session.parseCoordinator.generation()
        NotificationCenter.default.post(name: NSWindow.didChangeBackingPropertiesNotification, object: window)
        #expect(session.parseCoordinator.generation() == unchanged, "a backing change at the same scale parsed again")

        session.parseCoordinator.overrideScheduledBackingScaleForTesting(window.backingScaleFactor + 1)
        let before = session.parseCoordinator.generation()
        NotificationCenter.default.post(name: NSWindow.didChangeBackingPropertiesNotification, object: window)
        #expect(session.parseCoordinator.generation() > before, "a scale change did not start a new generation")
        session.detach()
    }

    // Verifies: REQ-111 — a parse that finishes after a newer source snapshot is discarded by the
    // real coordinator and leaves a typed reconciliation record.
    @Test func parseOwnerRecordsStaleReconciliation() async {
        let document = MarkdownDocument()
        let trace = InMemoryEditorTrace()
        document.trace = trace
        let source = String(repeating: "# heading\n\nparagraph with enough structure to parse.\n", count: 2_000)
        document.installTextForTesting(source)
        let session = EditorSession()
        session.attach(document: document)
        // Invalidate synchronously after the real parse is scheduled, before its detached task
        // can deliver the result back to this main actor. Cancellation would exercise only
        // parseCancelled; leaving the task alive proves the stale-result guard itself.
        session.parseCoordinator.bumpGenerationWithoutCancellationForTesting()
        for _ in 0..<500 {
            if trace.events.contains(where: {
                if case .reconciliationDiscarded = $0 { return true }
                return false
            }) { break }
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(2))
        }
        #expect(trace.events.contains {
            if case .reconciliationDiscarded = $0 { return true }
            return false
        }, "events: \(trace.events)")
        session.detach()
    }

    // Verifies: REQ-085 — cancellation through the owning ParseCoordinator invalidates its
    // operation identity synchronously, so a pending parse cannot remain current.
    @Test func parseOwnerCancellationInvalidatesGeneration() {
        let document = MarkdownDocument()
        document.installTextForTesting("hello\n")
        let session = EditorSession()
        session.attach(document: document)
        let before = session.parseCoordinator.generation()

        session.parseCoordinator.cancel()

        #expect(session.parseCoordinator.generation() > before)
        #expect(session.presentation == nil)
        session.detach()
    }

    // Verifies: REQ-115 — the smoke exercise uses the ordinary window command route for an
    // accepted insertion and a semantic command, independent of process/window timing.
    @Test func smokeEditExerciseUsesRealRoutes() {
        let document = MarkdownDocument()
        document.installTextForTesting("hello\n")
        let trace = InMemoryEditorTrace()
        document.trace = trace
        let session = EditorSession()
        session.attach(document: document)
        session.setMode(.source)
        let controller = EditorCommandController()
        controller.bind(
            document: document,
            session: session,
            actionRouter: EditorActionRouter(),
            window: nil
        )

        MarkdownAppDelegate.exerciseSmokeEdits(using: controller)

        #expect(document.text == "**x**hello\n")
        #expect(trace.events.contains {
            if case .mutationCommitted = $0 { return true }
            return false
        })
        #expect(trace.events.contains {
            if case .editRouted = $0 { return true }
            return false
        })
        session.detach()
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

    // Verifies: REQ-095; ARC-Q17 — sequence allocation and writer reservation are one atomic
    // operation even while the watchdog reports from a detached task, and no late fault can
    // append after the terminal record.
    @Test func watchdogRecordsRemainOrderedAndCannotAppendAfterFinish() async {
        let log = DiagnosticLog(directory: makeTemporaryDirectory(), hostKind: .unitTest)
        let reportFault = log.makeProcessFaultReporter()
        let tasks = (0..<20).map { index in
            Task.detached { reportFault(UInt64(index + 1)) }
        }
        for index in 0..<20 {
            log.record(.documentOpened, level: .info, category: .document, data: [(.count, .int(index))])
        }
        for task in tasks { await task.value }
        log.finish()
        let before = await lines(of: log)
        reportFault(999)
        let after = await lines(of: log)
        #expect(after == before)
        let sequences = after.compactMap { object($0)?["seq"] as? Int }
        #expect(sequences == sequences.sorted())
        #expect(after.last?.contains("\"ev\":\"runEnd\"") == true)
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
        let log = DiagnosticLog(directory: directory, hostKind: .unitTest, byteLimit: 2_048)
        // Error-level records are not collapsed; enough ordinary records reach the reserved
        // terminal-record space and exercise DiagnosticLog's actual sizeLimitReached route.
        for _ in 0..<100 {
            log.record(
                .userAlertPresented,
                level: .error,
                category: .diagnostics,
                data: [(.reason, .symbol(.writeFailed))]
            )
        }
        // Finish immediately after scheduling the burst: the cap marker and clean-shutdown
        // marker must both survive the serialized writer race.
        log.finish()

        var recorded = [String]()
        for _ in 0..<100 {
            recorded = await lines(of: log)
            if recorded.contains(where: { $0.contains("\"ev\":\"sizeLimitReached\"") }) { break }
            await Task.yield()
        }
        let written = recorded.joined(separator: "\n") + "\n"
        #expect(written.utf8.count <= 2_048)
        #expect(recorded.contains { $0.contains("\"ev\":\"sizeLimitReached\"") })
        #expect(recorded.last?.contains("\"ev\":\"runEnd\"") == true)
        for line in recorded {
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
    // Verifies: REQ-097 — the override is not merely honoured for the write path; a run under it
    // must not prune the user's production directory. Pruning is the destructive half of this
    // requirement ("cannot read, prune, or pollute"), and the resolution proof below cannot see
    // it: resolution could be correct while `pruneRuns` was handed the production directory.
    @Test func aRunUnderTheOverrideNeverPrunesTheProductionDirectory() throws {
        let production = makeTemporaryDirectory()
        let override = makeTemporaryDirectory()

        // Fill the production directory past the retention bound with plausible run files.
        var productionRuns: [URL] = []
        for index in 0..<(DiagnosticLog.maximumRetainedRuns + 5) {
            let url = production.appendingPathComponent(String(format: "run-2026010100000%02d-abc.jsonl", index))
            try Data("{}\n".utf8).write(to: url)
            productionRuns.append(url)
        }
        // And the override directory too, so we can tell pruning ran at all.
        for index in 0..<(DiagnosticLog.maximumRetainedRuns + 5) {
            let url = override.appendingPathComponent(String(format: "run-2026010100000%02d-def.jsonl", index))
            try Data("{}\n".utf8).write(to: url)
        }

        let resolved = DiagnosticLog.defaultDirectory(
            hostKind: .production,
            environment: ["MARKDOWN_EDITOR_DIAGNOSTICS_DIR": override.path]
        )
        #expect(resolved.path == override.path)

        DiagnosticLog.pruneRuns(in: resolved, keeping: DiagnosticLog.maximumRetainedRuns)

        // The user's production diagnostics are untouched, every file still present.
        for url in productionRuns {
            #expect(FileManager.default.fileExists(atPath: url.path), "pruned a production run: \(url.lastPathComponent)")
        }
        // Pruning really did run — against the override directory only.
        let remaining = try FileManager.default.contentsOfDirectory(atPath: override.path)
            .filter { $0.hasPrefix("run-") && $0.hasSuffix(".jsonl") }
        #expect(remaining.count == DiagnosticLog.maximumRetainedRuns)
    }

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
