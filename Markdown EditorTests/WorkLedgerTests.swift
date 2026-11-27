import Foundation
import MachO
import Testing
import AppKit
import Synchronization
import UniformTypeIdentifiers
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

    // Verifies: REQ-123 — work replaced by newer demand is superseded, recorded without a fault;
    // work that ends incomplete for any other reason is still an orphan. Both were faults, so
    // every document open and every burst of fast typing logged one.
    @Test func supersededWorkIsNotAnOrphan() {
        let recorder = IntentRecorder()
        let reports = Mutex<[(Bool, DiagnosticSymbol?)]>([])
        recorder.setReporter { _, _, orphaned, reason in reports.withLock { $0.append((orphaned, reason)) } }
        let replaced = recorder.begin(.reconciliation)
        #expect(recorder.finish(replaced, superseded: true))
        let abandoned = recorder.begin(.reconciliation)
        #expect(recorder.finish(abandoned, orphaned: true))
        let seen = reports.withLock { $0 }
        #expect(seen.count == 2)
        #expect(seen.first.map { !$0.0 && $0.1 == .superseded } == true, "superseded work was reported as \(String(describing: seen.first))")
        #expect(seen.last.map { $0.0 && $0.1 == .cancelled } == true, "abandoned work was reported as \(String(describing: seen.last))")
    }

    // Verifies: REQ-123 — a parse cancelled because a newer one was scheduled is superseded. The
    // opening parse was cancelled this way on every open, and recorded a fault each time.
    @Test func anOpeningParseReplacedByANewerOneIsSuperseded() async {
        let reports = Mutex<[(WorkScope, Bool, DiagnosticSymbol?)]>([])
        let document = MarkdownDocument()
        document.installTextForTesting("# Title\n\nBody.\n")
        let session = EditorSession()
        session.intentRecorder.setReporter { context, _, orphaned, reason in
            reports.withLock { $0.append((context.scope, orphaned, reason)) }
        }
        session.attach(document: document)
        defer { session.detach() }
        session.scheduleParse()
        for _ in 0..<400 where !reports.withLock({ $0.contains { $0.0 == .documentOpen } }) {
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(5))
        }
        let open = reports.withLock { $0.first { $0.0 == .documentOpen } }
        #expect(open != nil, "the opening intent never finished")
        #expect(open.map { !$0.1 } == true, "the replaced opening parse was recorded as an orphan: \(String(describing: open))")
    }

    // Verifies: REQ-123 — binding a window re-parses only when the window's scale differs from
    // the one the scheduled parse decoded images for. It compared with the previous window, and
    // the first window has none, so every open parsed twice.
    @Test func aWindowAtTheParsedScaleNeedsNoSecondParse() {
        #expect(!EditorSession.needsRescaleParse(scheduled: 2, window: 2))
        #expect(EditorSession.needsRescaleParse(scheduled: 2, window: 1))
        #expect(!EditorSession.needsRescaleParse(scheduled: nil, window: 1))
    }

    // Verifies: REQ-123 — a presentation adapter lease keeps downstream attributed work inside
    // the originating intent until the adapter releases it.
    @Test func presentationLeaseDefersTerminalLedger() {
        let recorder = IntentRecorder()
        let context = recorder.begin(.documentOpen)
        #expect(recorder.retain(context))
        recorder.add(context) { $0.attributedBuilds += 1 }
        #expect(recorder.finish(context))
        #expect(recorder.snapshot(context)?.attributedBuilds == 1)
        #expect(recorder.finish(context))
        #expect(recorder.snapshot(context) == nil)
    }

    // Verifies: REQ-124
    @Test func responsivenessMutationProof() async throws {
        let sampler = PerformanceSampler(trace: InMemoryEditorTrace(), coordinator: DiagnosticRunCoordinator())
        let probe = MainActorResponsivenessProbe(sampler: sampler, modalSessions: AppModalSession())
        probe.captureSampleNow()
        try await Task.sleep(for: .milliseconds(30))
        probe.stop()
        #expect(sampler.drainSummaries().contains { $0.metric == .mainActorLatency })
        sampler.invalidate()
    }

    // Verifies: REQ-125 — the real frame observer callback reaches the sampler's production
    // frameStatistics route, not only the pure hitch-rate calculation.
    @Test func frameObserverProductionRouteRecordsStatistics() async {
        let log = DiagnosticLog(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("frame-route-\(UUID().uuidString)"), hostKind: .unitTest)
        let trace = JSONLinesEditorTrace(log: log)
        let sampler = PerformanceSampler(trace: trace, coordinator: DiagnosticRunCoordinator())
        let observer = FrameObserver(sampler: sampler)
        observer.recordForTesting(
            callbackUptimeNanos: 0,
            ackUptimeNanos: 0,
            cadenceNanos: 16_666_667
        )
        observer.recordForTesting(
            callbackUptimeNanos: 1_000_000_000,
            ackUptimeNanos: 1_000_000_000,
            cadenceNanos: 16_666_667
        )
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
    let probe = MainActorResponsivenessProbe(sampler: sampler, modalSessions: AppModalSession())
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
    let probe = MainActorResponsivenessProbe(sampler: sampler, modalSessions: AppModalSession())
    probe.captureSampleNow()
    Thread.sleep(forTimeInterval: 0.2)
    RunLoop.current.run(until: Date().addingTimeInterval(0.15))
    probe.stop()
    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    let summary = sampler.drainSummaries().first { $0.metric == .mainActorLatency }
    sampler.invalidate()
    #expect(summary?.max ?? 0 >= 150_000_000)
}

// Verifies: REQ-124 — a hop that waited while the main thread ran one of AppKit's own loops is
// not a latency sample. Here every timer tick sees AppKit's loop, so a 200 ms block, which
// `aTwoHundredMillisecondMainActorBlockAppearsInTheLatencyDistribution` shows is counted in the
// default mode, leaves no sample of that size.
@Test @MainActor func aHopThatWaitedOnAppKitsOwnLoopIsNotALatencySample() async throws {
    let sampler = PerformanceSampler(trace: InMemoryEditorTrace(), coordinator: DiagnosticRunCoordinator())
    let probe = MainActorResponsivenessProbe(
        sampler: sampler,
        modalSessions: AppModalSession(),
        mainRunLoopMode: { "com.apple.HIServices.RunLoopSemaphore" }
    )
    probe.start()
    try await Task.sleep(for: .milliseconds(150))
    occupyMainActor(seconds: 0.25)
    try await Task.sleep(for: .milliseconds(150))
    probe.stop()
    let summary = sampler.drainSummaries().first { $0.metric == .mainActorLatency }
    sampler.invalidate()
    #expect((summary?.max ?? 0) < 150_000_000, "AppKit's wait was counted: \(String(describing: summary))")
}

// Verifies: REQ-124 — a hop that waited out an app-modal alert is not a latency sample. The
// main thread ran the alert, and the wait was the person reading it: tour 45974231615's
// bad-file alert alone put the p95 at 896 ms. The 200 ms block above, outside a session, is
// still counted.
@Test @MainActor func aHopThatWaitedOutAnAppModalAlertIsNotALatencySample() {
    let trace = InMemoryEditorTrace()
    let sampler = PerformanceSampler(trace: trace, coordinator: DiagnosticRunCoordinator())
    // Its own sessions: the app's shared one would reach every other test's probe.
    let sessions = AppModalSession()
    let probe = MainActorResponsivenessProbe(sampler: sampler, modalSessions: sessions)
    probe.captureSampleNow()
    sessions.around { Thread.sleep(forTimeInterval: 0.2) }
    RunLoop.current.run(until: Date().addingTimeInterval(0.15))
    probe.captureSampleNow()
    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    probe.stop()
    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    let summary = sampler.drainSummaries().first { $0.metric == .mainActorLatency }
    sampler.invalidate()
    #expect(summary?.count == 1, "samples: \(String(describing: summary))")
    #expect(summary?.max ?? .max < 150_000_000, "the alert's wait was counted: \(String(describing: summary))")
}

// Verifies: REQ-125
@Test @MainActor func frameBudgetFollowsTheDisplayLinkCadenceRatherThanAConstant() async {
    let sampler = PerformanceSampler(trace: InMemoryEditorTrace(), coordinator: DiagnosticRunCoordinator())
    let clock = ControlledFrameClock()
    let observer = FrameObserver(sampler: sampler, clock: clock)
    observer.startControlled()
    // The ticks are stamped a minute ahead, so every acknowledgement lands before its callback
    // and none counts as late: this measures cadence alone. Stamped "now", a parallel suite that
    // kept the main actor away for seconds made the acknowledgements late, and the test reported
    // an 83 ms/s hitch that was the suite's (CI 45974231640).
    let base = DispatchTime.now().uptimeNanoseconds + 60_000_000_000
    clock.emit(callbackUptimeNanos: base, cadenceNanos: 1_000_000_000)
    clock.emit(callbackUptimeNanos: base + 1_000_000_000, cadenceNanos: 1_000_000_000)
    clock.emit(callbackUptimeNanos: base + 3_000_000_000, cadenceNanos: 2_000_000_000)
    for _ in 0..<3 { await Task.yield() }
    let statistics = observer.drainStatistics()
    #expect(statistics?.framesObserved == 2)
    #expect((statistics?.longestFrameNanos ?? .max) >= 1_000_000_000)
    #expect(statistics?.longestFrameNanos == 2_000_000_000)
    #expect(statistics?.hitchMillisPerSecond == 0)
    observer.stop()
    sampler.invalidate()
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
    // Verifies: REQ-111 — cancelling the real parse owner emits the typed production cancellation
    // route, keeping the fast coverage gate independent of the excluded performance suite.
    @Test func parseCancellationRecordsProductionRoute() async {
        let document = MarkdownDocument()
        document.installTextForTesting(String(repeating: "# heading\n\nparagraph with enough structure to parse.\n", count: 20_000))
        let trace = InMemoryEditorTrace()
        document.trace = trace
        let session = EditorSession()
        session.attach(document: document)

        // `.parseCancelled` is emitted only from inside the detached parse task, at its
        // cancellation checkpoints. Cancelling before that task exists makes `cancel()` drop the
        // pending scheduler request instead, so no task ever runs and the event can never be
        // emitted. A single `Task.yield()` did not guarantee the task had started, which is why
        // this failed under parallel load and passed in isolation — and why widening the
        // observation window did not help: by then the outcome was already decided.
        //
        // Wait for the parse to actually be in flight, then cancel it.
        await waitUntil { trace.events.contains { if case .parseStarted = $0 { return true }; return false } }
        #expect(
            trace.events.contains { if case .parseStarted = $0 { return true }; return false },
            "parse never started, so there was nothing to cancel; events: \(trace.events)"
        )

        session.parseCoordinator.cancel()

        await waitUntil { trace.events.contains { if case .parseCancelled = $0 { return true }; return false } }
        #expect(trace.events.contains {
            if case .parseCancelled = $0 { return true }
            return false
        }, "events: \(trace.events)")
        session.detach()
    }

    /// Polls `condition` on the main actor until it holds or the bound elapses. Bounded, so a
    /// condition that never becomes true still fails the caller's `#expect` rather than hanging.
    private func waitUntil(
        timeoutSeconds: Double = 10,
        _ condition: () -> Bool
    ) async {
        let deadline = DispatchTime.now().uptimeNanoseconds + UInt64(timeoutSeconds * 1_000_000_000)
        while !condition() && DispatchTime.now().uptimeNanoseconds < deadline {
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(2))
        }
    }

    // Verifies: REQ-109 — the real WYSIWYG adapter records recovery when its applied TextKit
    // storage has drifted, without relying on the excluded performance-boundary suite.
    @Test func presentationDriftRecordsRecoveryProductionRoute() throws {
        let source = "Hello world.\n\nSecond paragraph.\n"
        let document = MarkdownDocument()
        document.installTextForTesting(source)
        let trace = InMemoryEditorTrace()
        document.trace = trace
        let session = EditorSession()
        session.attach(document: document)
        session.setMode(.wysiwyg)
        let index = MarkdownSourceIndex(source: source, sourceVersion: document.sourceVersion)
        let tree = try #require(MarkdownParser.parse(source, sourceVersion: document.sourceVersion).get())
        session.installProjectionForTesting(
            MarkdownProjectionModel.build(tree: tree, index: index),
            tree: tree
        )
        let placement = ImagePlacementController()
        let coordinator = WYSIWYGEditor.Coordinator(
            document: document,
            session: session,
            placementController: placement
        )
        let (textView, storage) = makeSpyBackedTextView()
        textView.delegate = coordinator
        textView.inputCoordinator = coordinator.input
        textView.documentActions = document
        textView.session = session
        textView.adapterCoordinator = coordinator
        coordinator.textView = textView
        coordinator.applyProjectionIfNeeded(reason: .reapplyIfDrift)
        storage.replaceCharacters(in: NSRange(location: 0, length: 5), with: "DRIFT")
        storage.resetSpy()
        coordinator.applyProjectionIfNeeded(reason: .reapplyIfDrift)
        #expect(trace.events.contains {
            if case .presentationRecovered = $0 { return true }
            return false
        }, "events: \(trace.events)")
        session.detach()
    }

    // Verifies: REQ-084 — the real WYSIWYG marked-text route emits composition start and its
    // terminal cancellation record through the production trace owner.
    @Test func compositionRoutesRecordProductionEvents() throws {
        let document = MarkdownDocument()
        document.installTextForTesting("ab\n")
        let trace = InMemoryEditorTrace()
        document.trace = trace
        let session = EditorSession()
        session.attach(document: document)
        session.setMode(.wysiwyg)
        let index = MarkdownSourceIndex(source: document.text, sourceVersion: document.sourceVersion)
        let tree = try #require(MarkdownParser.parse(document.text, sourceVersion: document.sourceVersion).get())
        session.installProjectionForTesting(
            MarkdownProjectionModel.build(
                tree: tree,
                index: index
            ),
            tree: tree
        )
        let placement = ImagePlacementController()
        let coordinator = WYSIWYGEditor.Coordinator(
            document: document,
            session: session,
            placementController: placement
        )
        let (textView, _) = makeSpyBackedTextView()
        textView.delegate = coordinator
        textView.inputCoordinator = coordinator.input
        textView.documentActions = document
        textView.session = session
        textView.adapterCoordinator = coordinator
        coordinator.textView = textView
        coordinator.applyProjectionIfNeeded(reason: .reapplyIfDrift)
        textView.setSelectedRange(NSRange(location: 2, length: 0))
        textView.setMarkedText(
            "日",
            selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: 2, length: 0)
        )
        textView.unmarkText()
        textView.unmarkText()
        #expect(trace.events.contains {
            if case .compositionBegan = $0 { return true }
            return false
        }, "events: \(trace.events)")
        #expect(trace.events.contains {
            if case .compositionCancelled = $0 { return true }
            return false
        }, "events: \(trace.events)")
        session.detach()
    }

    // Verifies: REQ-123 — the native AppKit source route stages the same accepted-edit intent
    // before the document publishes, so its parser work is not attributed to a new owner.
    @Test func nativeSourceRouteRetainsIntentThroughParse() async {
        let document = MarkdownDocument()
        document.installTextForTesting("hello\n")
        let session = EditorSession()
        session.attach(document: document)
        let placement = ImagePlacementController()
        placement.attach(actions: document)
        let coordinator = SourceEditor.Coordinator(
            document: document,
            placementController: placement,
            session: session
        )
        let mutation = SourceMutation(
            expectedRevision: document.sourceVersion,
            range: NSRange(location: 0, length: 1),
            expectedText: "h",
            replacement: "H",
            selectionBefore: SourceSelection(utf16: NSRange(location: 0, length: 1)),
            selectionAfter: SourceSelection(utf16: NSRange(location: 1, length: 0)),
            actionName: "Typing",
            grouping: .typing
        )
        session.captureSelection(.source(mutation.selectionBefore))
        #expect({
            if case .committed = coordinator.commitNativeMutation(mutation) { return true }
            return false
        }())

        let sharedLog = DiagnosticLog.shared
        var logText = ""
        for _ in 0..<500 {
            if let presentation = session.presentation,
               let intent = session.takePresentationIntent(for: presentation.id) {
                intent.recorder.finish(intent)
            }
            await sharedLog?.drain()
            logText = (try? String(contentsOf: sharedLog?.fileURL ?? URL(fileURLWithPath: "/dev/null"), encoding: .utf8)) ?? ""
            if logText.contains("\"scope\":\"acceptedEdit\"")
                && logText.contains("\"orphaned\":false")
                && logText.contains("\"documentParses\":1") {
                break
            }
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(2))
        }
        #expect(document.text == "Hello\n")
        #expect(logText.contains("\"scope\":\"acceptedEdit\""))
        #expect(logText.contains("\"orphaned\":false"))
        #expect(logText.contains("\"documentParses\":1"))
        session.detach()
    }

    // Verifies: REQ-123 — the production image-placement route publishes through the same
    // staged accepted-edit identity that the parser consumes, rather than opening a second
    // reconciliation owner at the document observer boundary.
    @Test func imagePlacementRouteRetainsIntentThroughParse() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("image-intent-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let documentURL = directory.appendingPathComponent("note.md")
        try Data().write(to: documentURL)

        let document = MarkdownDocument()
        document.installTextForTesting("")
        document.fileURL = documentURL
        let session = EditorSession()
        session.attach(document: document)
        let placement = ImagePlacementController()
        placement.session = session
        placement.attach(actions: document)

        let intent = session.intentRecorder.begin(.acceptedEdit)
        let target = ImagePlacementTarget(
            sourceSelection: SourceSelection(utf16: NSRange(location: 0, length: 0)),
            sourceRevision: SourceRevision(value: document.sourceVersion),
            locationGeneration: document.locationGeneration,
            operationID: UUID()
        )
        placement.handleImageAction(
            intent: ImagePlacementIntent(
                target: target,
                claims: [.bitmapData(try makePNGData(), providerName: "proof.png", declaredType: .png)]
            ),
            documentURL: documentURL,
            intentContext: intent
        )

        var presentationIntent: IntentContext?
        for _ in 0..<3_000 {
            if document.text == "![](assets/proof.png)",
               let presentation = session.presentation,
               presentation.sourceRevision.value == document.sourceVersion,
               let handedOff = session.takePresentationIntent(for: presentation.id) {
                presentationIntent = handedOff
                break
            }
            await Task.yield()
            try await Task.sleep(for: .milliseconds(5))
        }

        let ledger = session.intentRecorder.snapshot(intent)
        presentationIntent?.recorder.finish(presentationIntent!)
        for _ in 0..<3_000 where placement.phaseForTesting != .idle {
            await Task.yield()
            try await Task.sleep(for: .milliseconds(5))
        }

        #expect(presentationIntent?.id == intent.id)
        #expect(ledger?.documentParses == 1)
        #expect(document.text == "![](assets/proof.png)")
        #expect(placement.phaseForTesting == .idle)
        session.detach()
    }

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
            // This component proof owns the session but does not construct an EditorHost. Release
            // the production snapshot lease explicitly once the authoritative projection exists;
            // a real host performs the same release after applying attributed storage.
            if let presentation = session.presentation,
               let intent = session.takePresentationIntent(for: presentation.id) {
                intent.recorder.finish(intent)
            }
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
