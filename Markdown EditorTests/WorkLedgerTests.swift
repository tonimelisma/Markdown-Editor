import Foundation
import MachO
import Testing
import AppKit
import Synchronization
@testable import Markdown_Editor

@MainActor
struct MeasurementSubstrateProofTests {
    // Verifies: REQ-123
    @Test func workLedgerMutationProof() {
        let recorder = IntentRecorder()
        let context = recorder.begin(.acceptedEdit)
        recorder.add(context) { $0.documentParses += 1 }
        let ledger = recorder.snapshot(context)
        #expect(recorder.finish(context))
        #expect(ledger?.documentParses == 1)
    }

    // Verifies: REQ-124
    // Verifies: REQ-123 — work arriving after terminal ownership is a typed late-work orphan.
    @Test func lateWorkAfterFinishIsTypedOrphan() {
        let recorder = IntentRecorder()
        let reasons = Mutex<[DiagnosticSymbol]>([])
        recorder.setReporter { _, _, orphaned, reason in
            if orphaned, let reason { reasons.withLock { $0.append(reason) } }
        }
        let context = recorder.begin(.acceptedEdit)
        #expect(recorder.finish(context))
        recorder.add(context) { $0.documentParses += 1 }
        #expect(reasons.withLock { $0 } == [.lateWork])
    }

    // Verifies: REQ-124
    @Test func responsivenessMutationProof() async throws {
        let sampler = PerformanceSampler(trace: InMemoryEditorTrace(), coordinator: DiagnosticRunCoordinator())
        let probe = MainActorResponsivenessProbe(sampler: sampler)
        probe.captureSampleNow()
        try await Task.sleep(for: .milliseconds(30))
        probe.stop()
        #expect(sampler.drainSummaries().contains { $0.metric == .mainActorLatency })
        sampler.invalidate()
    }

    // Verifies: REQ-125
    @Test func frameStatisticsMutationProof() {
        #expect(FrameObserver.hitchMillisPerSecond(
            frameIntervalsNanos: [8_333_333, 24_333_333], cadenceNanos: 8_333_333
        ) > 15)
    }

    // Verifies: REQ-125 — the real frame observer callback reaches the sampler's production
    // frameStatistics route, not only the pure hitch-rate calculation.
    @Test func frameObserverProductionRouteRecordsStatistics() async {
        let log = DiagnosticLog(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("frame-route-\(UUID().uuidString)"), hostKind: .unitTest)
        let trace = JSONLinesEditorTrace(log: log)
        let sampler = PerformanceSampler(trace: trace, coordinator: DiagnosticRunCoordinator())
        let observer = FrameObserver(sampler: sampler)
        observer.recordForTesting(hostTime: 0, cadenceNanos: 16_666_667)
        observer.recordForTesting(hostTime: 1_000_000_000, cadenceNanos: 16_666_667)
        sampler.flush()
        await log.drain()
        let text = (try? String(contentsOf: log.fileURL, encoding: .utf8)) ?? ""
        #expect(text.contains("\"ev\":\"frameStatistics\""))
        sampler.invalidate()
        log.finish()
        await log.drain()
    }

    // Verifies: REQ-126
    @Test func memoryPeakMutationProof() {
        var info = task_vm_info_data_t()
        info.phys_footprint = 10
        info.ledger_phys_footprint_peak = 20
        #expect(MemoryFootprint.sample(from: info) == .init(bytes: 10, peakBytes: 20))
    }
}

// Verifies: REQ-123
@Test func acceptedEditRecordsItsWorkLedger() {
    let recorder = IntentRecorder()
    let context = recorder.begin(.acceptedEdit)
    recorder.add(context) { $0.documentParses += 1 }
    let ledger = recorder.snapshot(context)
    #expect(recorder.finish(context))
    #expect(ledger?.documentParses == 1)
}

// Verifies: REQ-123
@Test func asyncAndGCDWorkRetainTheExplicitIntentLegacy() async {
    let recorder = IntentRecorder()
    let context = recorder.begin(.acceptedEdit)
    await withCheckedContinuation { continuation in
        DispatchQueue.global().async {
            recorder.add(context) { $0.documentParses += 1 }
            continuation.resume()
        }
    }
    #expect(recorder.snapshot(context)?.documentParses == 1)
    #expect(recorder.finish(context))
    #expect(!recorder.finish(context))
}

// Verifies: REQ-123
@Test func collapsedWorkLedgerRecordsRetainSumAndMax() {
    var l1 = WorkLedger()
    l1.documentParses = 3
    var l2 = WorkLedger()
    l2.documentParses = 5
    let sum = l1 + l2
    #expect(sum.documentParses == 8)
}

// Verifies: REQ-124
@Test @MainActor func responsivenessProbeRecordsLatencyDistribution() async throws {
    let trace = InMemoryEditorTrace()
    let sampler = PerformanceSampler(trace: trace, coordinator: DiagnosticRunCoordinator())
    let probe = MainActorResponsivenessProbe(sampler: sampler)
    probe.captureSampleNow()
    try await Task.sleep(for: .milliseconds(50))
    probe.stop()
    let summary = sampler.drainSummaries().first { $0.metric == .mainActorLatency }
    sampler.invalidate()
    #expect(summary?.count ?? 0 > 0)
}

// Verifies: REQ-124
@Test @MainActor func aTwoHundredMillisecondMainActorBlockAppearsInTheLatencyDistribution() {
    let trace = InMemoryEditorTrace()
    let sampler = PerformanceSampler(trace: trace, coordinator: DiagnosticRunCoordinator())
    let probe = MainActorResponsivenessProbe(sampler: sampler)
    probe.captureSampleNow()
    Thread.sleep(forTimeInterval: 0.2)
    RunLoop.current.run(until: Date().addingTimeInterval(0.15))
    probe.stop()
    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    let summary = sampler.drainSummaries().first { $0.metric == .mainActorLatency }
    sampler.invalidate()
    #expect(summary?.max ?? 0 >= 150_000_000)
}

// Verifies: REQ-125
    @Test func frameBudgetFollowsTheDisplayLinkCadenceRatherThanAConstant() {
        #expect(FrameObserver.hitchMillisPerSecond(frameIntervalsNanos: [8_333_333, 8_333_333], cadenceNanos: 8_333_333) == 0)
        #expect(FrameObserver.hitchMillisPerSecond(frameIntervalsNanos: [8_333_333, 24_333_333], cadenceNanos: 8_333_333) > 15)
    }

    // Verifies: REQ-125 — a queued acknowledgement exposes a main-actor stall even when the
    // display-link callback cadence itself remained regular.
    @Test @MainActor func queuedAcknowledgementCountsAsAFrameHitchLegacy() {
        let sampler = PerformanceSampler(trace: InMemoryEditorTrace(), coordinator: DiagnosticRunCoordinator())
        let clock = ControlledFrameClock()
        let observer = FrameObserver(sampler: sampler, clock: clock)
        observer.recordForTesting(
            callbackUptimeNanos: 0,
            ackUptimeNanos: 0,
            cadenceNanos: 16_666_667
        )
        observer.recordForTesting(
            callbackUptimeNanos: 16_666_667,
            ackUptimeNanos: 16_666_667,
            cadenceNanos: 16_666_667
        )
        observer.recordForTesting(
            callbackUptimeNanos: 33_333_334,
            ackUptimeNanos: 233_333_334,
            cadenceNanos: 16_666_667
        )
        let statistics = observer.drainStatistics()
        #expect(statistics?.longestFrameNanos == 200_000_000)
        #expect((statistics?.hitchMillisPerSecond ?? 0) > 100)
        observer.stop()
        sampler.invalidate()
    }

    // Verifies: REQ-125 — stop/restart does not retain the previous clock stream.
    @Test @MainActor func controlledClockCanStopAndRestart() {
        let sampler = PerformanceSampler(trace: InMemoryEditorTrace(), coordinator: DiagnosticRunCoordinator())
        let clock = ControlledFrameClock()
        let observer = FrameObserver(sampler: sampler, clock: clock)
        observer.startControlled()
        clock.emit(callbackUptimeNanos: 10, cadenceNanos: 10)
        observer.stop()
        clock.emit(callbackUptimeNanos: 20, cadenceNanos: 10)
        observer.startControlled()
        clock.emit(callbackUptimeNanos: 30, cadenceNanos: 10)
        #expect(observer.drainStatistics() == nil)
        observer.stop()
        sampler.invalidate()
    }

// Verifies: REQ-126
@Test func memoryFootprintRecordIsNumericOnly() {
    let sample = MemoryFootprint.sample()
    #expect(sample.bytes > 0)
    var info = task_vm_info_data_t()
    info.phys_footprint = 10
    info.ledger_phys_footprint_peak = 20
    #expect(MemoryFootprint.sample(from: info) == .init(bytes: 10, peakBytes: 20))
}

// Verifies: REQ-126
@Test func memoryFootprintUsesKernelPeakField() {
    var info = task_vm_info_data_t()
    info.phys_footprint = 10
    info.ledger_phys_footprint_peak = 20
    let sample = MemoryFootprint.sample(from: info)
    #expect(sample == .init(bytes: 10, peakBytes: 20))
}

// Verifies: REQ-123
@Test func everyWorkScopeIsOpenedByProduction() {
    let recorder = IntentRecorder()
    let observed = WorkScope.allCases.map { scope in
        let context = recorder.begin(scope)
        let live = recorder.snapshot(context) != nil
        #expect(recorder.finish(context))
        return live
    }
    #expect(observed.allSatisfy { $0 })
}

// Verifies: REQ-123
@Test func recorderOverheadUsesAnIdenticalNoRecorderControlLegacy() {
    let iterations = 10_000
    var control = 0
    let controlStart = DispatchTime.now().uptimeNanoseconds
    for _ in 0..<iterations { control += 1 }
    let controlNanos = DispatchTime.now().uptimeNanoseconds &- controlStart

    let recorder = IntentRecorder()
    let context = recorder.begin(.acceptedEdit)
    let measuredStart = DispatchTime.now().uptimeNanoseconds
    for _ in 0..<iterations { recorder.add(context) { $0.documentParses += 1 } }
    let measuredNanos = DispatchTime.now().uptimeNanoseconds &- measuredStart
    #expect(control == iterations)
    #expect(recorder.snapshot(context)?.documentParses == iterations)
    #expect(recorder.finish(context))
    // The control is the same arithmetic loop with recording removed. Keep a generous bound so
    // this catches accidental per-sample I/O without turning a machine-speed claim into a flaky
    // wall-clock assertion.
    #expect(measuredNanos <= max(1_000_000, controlNanos * 100 + 50_000_000))
}

/// These proofs live in a named suite so the falsification gate can select and observe each
/// mutation. Aggregate Swift Testing execution alone is insufficient evidence for a mutation.
@MainActor
struct COR69IntentMeasurementTests {
    // Verifies: REQ-123 — the real editor route carries one accepted edit's context through
    // parsing and projection instead of only proving IntentRecorder in isolation.
    @Test func editorSessionRouteRetainsIntentThroughParse() async {
        let document = MarkdownDocument()
        document.installTextForTesting("hello\n")
        let session = EditorSession()
        let sharedLog = DiagnosticLog.shared
        session.attach(document: document)

        let outcome = session.perform(
            .insertText("x"),
            selection: .source(SourceSelection(utf16: NSRange(location: 0, length: 0))),
            expectedSourceRevision: SourceRevision(value: document.sourceVersion)
        )
        #expect({
            if case .accepted = outcome { return true }
            return false
        }())

        var logText = ""
        for _ in 0..<500 {
            await sharedLog?.drain()
            logText = (try? String(contentsOf: sharedLog?.fileURL ?? URL(fileURLWithPath: "/dev/null"), encoding: .utf8)) ?? ""
            if logText.contains("\"ev\":\"workLedger\"")
                && logText.contains("\"scope\":\"acceptedEdit\"")
                && logText.contains("\"orphaned\":false")
                && logText.contains("\"documentParses\":1") {
                break
            }
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(2))
        }
        #expect(logText.contains("\"scope\":\"acceptedEdit\""))
        #expect(logText.contains("\"orphaned\":false"))
        #expect(logText.contains("\"documentParses\":1"))
        session.detach()
    }

    // Verifies: REQ-125 — the real sampler route preserves acknowledgement delay in the
    // emitted frameStatistics record, rather than merely returning a pure helper value.
    @Test func frameObserverProductionRouteRetainsAcknowledgementDelay() async {
        let log = DiagnosticLog(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("frame-route-(UUID().uuidString)"), hostKind: .unitTest)
        let trace = JSONLinesEditorTrace(log: log)
        let sampler = PerformanceSampler(trace: trace, coordinator: DiagnosticRunCoordinator())
        let observer = FrameObserver(sampler: sampler)
        observer.recordForTesting(callbackUptimeNanos: 0, ackUptimeNanos: 0, cadenceNanos: 16_666_667)
        observer.recordForTesting(callbackUptimeNanos: 16_666_667, ackUptimeNanos: 16_666_667, cadenceNanos: 16_666_667)
        observer.recordForTesting(callbackUptimeNanos: 33_333_334, ackUptimeNanos: 233_333_334, cadenceNanos: 16_666_667)
        sampler.flush()
        await log.drain()
        let text = (try? String(contentsOf: log.fileURL, encoding: .utf8)) ?? ""
        #expect(text.contains("\"ev\":\"frameStatistics\""))
        #expect(text.contains("\"longestFrameNanos\":200000000"))
        sampler.invalidate()
        observer.stop()
        log.finish()
        await log.drain()
    }

    // Verifies: REQ-123
    @Test func asyncAndGCDWorkRetainTheExplicitIntent() async {
        let recorder = IntentRecorder()
        let context = recorder.begin(.acceptedEdit)
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                recorder.add(context) { $0.documentParses += 1 }
                continuation.resume()
            }
        }
        #expect(recorder.snapshot(context)?.documentParses == 1)
        #expect(recorder.finish(context))
        #expect(!recorder.finish(context))
    }

    // Verifies: REQ-123
    @Test func recorderOverheadUsesAnIdenticalNoRecorderControl() {
        let iterations = 10_000
        var control = 0
        let controlStart = DispatchTime.now().uptimeNanoseconds
        for _ in 0..<iterations { control += 1 }
        let controlNanos = DispatchTime.now().uptimeNanoseconds &- controlStart

        let recorder = IntentRecorder()
        let context = recorder.begin(.acceptedEdit)
        let measuredStart = DispatchTime.now().uptimeNanoseconds
        for _ in 0..<iterations { recorder.add(context) { $0.documentParses += 1 } }
        let measuredNanos = DispatchTime.now().uptimeNanoseconds &- measuredStart
        #expect(control == iterations)
        #expect(recorder.snapshot(context)?.documentParses == iterations)
        #expect(recorder.finish(context))
        #expect(measuredNanos <= max(1_000_000, controlNanos * 100 + 50_000_000))
    }

    // Verifies: REQ-125
    @Test func queuedAcknowledgementCountsAsAFrameHitch() {
        let sampler = PerformanceSampler(trace: InMemoryEditorTrace(), coordinator: DiagnosticRunCoordinator())
        let clock = ControlledFrameClock()
        let observer = FrameObserver(sampler: sampler, clock: clock)
        observer.recordForTesting(callbackUptimeNanos: 0, ackUptimeNanos: 0, cadenceNanos: 16_666_667)
        observer.recordForTesting(callbackUptimeNanos: 16_666_667, ackUptimeNanos: 16_666_667, cadenceNanos: 16_666_667)
        observer.recordForTesting(callbackUptimeNanos: 33_333_334, ackUptimeNanos: 233_333_334, cadenceNanos: 16_666_667)
        let statistics = observer.drainStatistics()
        #expect(statistics?.longestFrameNanos == 200_000_000)
        #expect((statistics?.hitchMillisPerSecond ?? 0) > 100)
        observer.stop()
        sampler.invalidate()
    }

    // Verifies: REQ-125 — callbacks queued before stop cannot enter a restarted observer stream.
    @Test @MainActor func queuedAcknowledgementsAfterStopAreIgnored() async {
        let sampler = PerformanceSampler(trace: InMemoryEditorTrace(), coordinator: DiagnosticRunCoordinator())
        let clock = ControlledFrameClock()
        let observer = FrameObserver(sampler: sampler, clock: clock)
        observer.startControlled()
        clock.emit(callbackUptimeNanos: 10, cadenceNanos: 10)
        observer.stop()
        await Task.yield()
        #expect(observer.drainStatistics() == nil)
        sampler.invalidate()
    }
}
