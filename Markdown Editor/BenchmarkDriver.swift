import AppKit
import Foundation

nonisolated struct BenchmarkCaseOutcome: Sendable, Equatable {
    let progress: Int
    let errors: Int
    let timeoutCount: Int
    let unknownActionCount: Int
    let duplicateSampleCount: Int
    let actionContractFailureCount: Int

    init(
        progress: Int,
        errors: Int,
        timeoutCount: Int,
        unknownActionCount: Int,
        duplicateSampleCount: Int,
        actionContractFailureCount: Int = 0
    ) {
        self.progress = progress
        self.errors = errors
        self.timeoutCount = timeoutCount
        self.unknownActionCount = unknownActionCount
        self.duplicateSampleCount = duplicateSampleCount
        self.actionContractFailureCount = actionContractFailureCount
    }
}

nonisolated enum BenchmarkActionResult: String, Codable, Sendable {
    case accepted
    case started
    case refused
    case disabled
}

nonisolated struct BenchmarkActionObservation: Codable, Sendable, Equatable {
    let mode: EditorMode?
    let action: String
    let expected: BenchmarkActionResult
    let observed: BenchmarkActionResult
}

/// Process-level benchmark driver, reachable only through `--benchmark-manifest`.
///
/// The manifest carries matrix parameters only. `PerformanceCorpus` and `Scenario.allCases` are
/// the single authorities for fixture and action enumeration; the shell harness never recreates
/// corpus text or command loops.
/// // REQ-128; ARC-Q12.
@MainActor
enum BenchmarkDriver {
    enum Scenario: String, CaseIterable, Codable, Sendable {
        case typeProse, typeInTable, typeAdjacentMarkup, applyCommands, toggleModes
        case scrollDocument, undoRedoStorm, openAndIdle, soak
    }

    struct Manifest: Codable, Sendable, Equatable {
        let durationSeconds: Double
        let intervalMillis: Double
        let sizes: [Int]
        let resultDirectory: URL

        var resultDirectoryURL: URL {
            resultDirectory.isFileURL ? resultDirectory : URL(fileURLWithPath: resultDirectory.path)
        }
    }

    struct Configuration: Sendable {
        let scenario: Scenario
        let corpus: PerformanceCorpus
        let size: Int
        let duration: Duration
        let interval: Duration
        let resultURL: URL?
    }

    private struct MetricResult: Codable, Sendable {
        let name: String
        let count: Int
        let p50Nanos: UInt64
        let p95Nanos: UInt64
        let maxNanos: UInt64
        let budgetExceeded: Bool
    }

    private struct CaseResult: Codable, Sendable {
        let scenario: Scenario
        let corpus: PerformanceCorpus
        let size: Int
        let passed: Bool
        let actionAttempts: Int
        let accepted: Int
        let started: Int
        let refused: Int
        let disabled: Int
        let progress: Int
        let errors: Int
        let timeoutCount: Int
        let unknownActionCount: Int
        let duplicateSampleCount: Int
        let actionContractFailureCount: Int
        let actionOutcomes: [BenchmarkActionObservation]
        let expectedActionAttemptsMinimum: Int
        let expectedProgressMinimum: Int
        let metrics: [MetricResult]
    }

    private struct CaseKey: Codable, Sendable, Equatable {
        let scenario: Scenario
        let corpus: PerformanceCorpus
        let size: Int
    }

    private struct BenchmarkSummary: Codable, Sendable {
        let expectedCases: [CaseKey]
        let completedCases: [CaseKey]
    }

    /// Per-iteration action evidence. The process harness serializes the aggregate, while the
    /// internal route seam lets component proofs exercise the same production action owner.
    struct Counters: Sendable {
        var actionAttempts = 0
        var accepted = 0
        var started = 0
        var refused = 0
        var disabled = 0
        var progress = 0
        var errors = 0
        var timeoutCount = 0
        var unknownActionCount = 0
        var duplicateSampleCount = 0
        var actionContractFailures = 0
        var actionOutcomes: [BenchmarkActionObservation] = []

        init(progress: Int = 0) {
            self.progress = progress
        }

        static func +(lhs: Counters, rhs: Counters) -> Counters {
            var result = lhs
            result.actionAttempts += rhs.actionAttempts
            result.accepted += rhs.accepted
            result.started += rhs.started
            result.refused += rhs.refused
            result.disabled += rhs.disabled
            result.progress += rhs.progress
            result.errors += rhs.errors
            result.timeoutCount += rhs.timeoutCount
            result.unknownActionCount += rhs.unknownActionCount
            result.duplicateSampleCount += rhs.duplicateSampleCount
            result.actionContractFailures += rhs.actionContractFailures
            result.actionOutcomes.append(contentsOf: rhs.actionOutcomes)
            return result
        }

        mutating func record(
            mode: EditorMode?,
            action: String,
            expected: BenchmarkActionResult,
            observed: BenchmarkActionResult
        ) {
            actionAttempts += 1
            actionOutcomes.append(BenchmarkActionObservation(
                mode: mode,
                action: action,
                expected: expected,
                observed: observed
            ))
            if expected != observed {
                actionContractFailures += 1
                errors += 1
            }
            switch observed {
            case .accepted:
                accepted += 1
                progress += 1
            case .started:
                started += 1
                progress += 1
            case .refused:
                refused += 1
            case .disabled:
                disabled += 1
            }
        }
    }

    private static var configurations: [Configuration] = []

    nonisolated static func accepts(_ outcome: BenchmarkCaseOutcome) -> Bool {
        outcome.errors == 0
            && outcome.timeoutCount == 0
            && outcome.unknownActionCount == 0
            && outcome.duplicateSampleCount == 0
            && outcome.actionContractFailureCount == 0
            && outcome.progress > 0
    }

    private static func minimumActionAttempts(for scenario: Scenario) -> Int {
        switch scenario {
        case .typeProse, .typeInTable, .typeAdjacentMarkup: return 1
        case .applyCommands: return EditorCommand.allCases.count * 2
        case .toggleModes: return 1
        case .scrollDocument: return 1
        case .undoRedoStorm: return 300
        case .openAndIdle: return 1
        case .soak: return minimumActionAttempts(for: .typeProse) + minimumActionAttempts(for: .toggleModes) + minimumActionAttempts(for: .undoRedoStorm)
        }
    }

    private static func minimumProgress(for scenario: Scenario) -> Int {
        1
    }

    private static func expectedOutcome(
        for command: EditorCommand,
        controller: EditorCommandController
    ) -> BenchmarkActionResult {
        if case .disabled = controller.availability(for: command) {
            return .disabled
        }
        switch command {
        case .addImage, .editLink:
            return .started
        case .removeLink:
            // The benchmark selection is the first four UTF-16 units of each corpus. None of
            // the closed corpus fixtures begins with a complete link destination, so the
            // command's enabled-but-refused outcome is the expected contract for this input.
            return .refused
        default:
            return .accepted
        }
    }

    private static func prepareBenchmarkSelection(
        mode: EditorMode,
        session: EditorSession,
        document: MarkdownDocument
    ) {
        let length = (document.text as NSString).length
        let sourceSelection = SourceSelection(
            utf16: NSRange(location: 0, length: min(4, length)),
            affinity: .downstream
        )
        session.updateSourceModeState { $0.selection = sourceSelection }
        guard mode == .wysiwyg,
              let presentation = session.presentation,
              case .exact(let projected) = presentation.coordinateMap.projectionRange(
                forSource: sourceSelection.range.utf16,
                affinity: sourceSelection.affinity
              ) else { return }
        session.updateWYSIWYGModeState {
            $0.selection = ProjectionSelection(
                utf16: projected,
                revision: presentation.projectionRevision,
                affinity: sourceSelection.affinity
            )
        }
    }

    private static func editWasAccepted(_ outcome: EditorEditOutcome) -> Bool {
        if case .accepted = outcome { return true }
        return false
    }

    static var isRequested: Bool {
        CommandLine.arguments.contains("--benchmark")
            || CommandLine.arguments.contains("--benchmark-manifest")
    }

    static func runIfRequested() -> Bool {
        if let manifestIndex = CommandLine.arguments.firstIndex(of: "--benchmark-manifest"),
           CommandLine.arguments.indices.contains(manifestIndex + 1),
           let data = try? Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[manifestIndex + 1])),
           let manifest = try? JSONDecoder().decode(Manifest.self, from: data) {
            configurations = configurations(from: manifest)
            return !configurations.isEmpty
        }
        guard let config = configuration(arguments: CommandLine.arguments) else { return false }
        configurations = [config]
        return true
    }

    nonisolated static func configurations(from manifest: Manifest) -> [Configuration] {
        PerformanceCorpus.allCases.flatMap { corpus in
            manifest.sizes.flatMap { size in
                Scenario.allCases.map { scenario in
                    Configuration(
                        scenario: scenario,
                        corpus: corpus,
                        size: max(1, size),
                        duration: .milliseconds(max(1, Int(manifest.durationSeconds * 1_000))),
                        interval: .milliseconds(max(1, Int(manifest.intervalMillis))),
                        resultURL: manifest.resultDirectoryURL
                            .appendingPathComponent("\(scenario.rawValue)-\(corpus.rawValue)-\(size).json")
                    )
                }
            }
        }
    }

    /// Legacy one-case parser remains a component seam; production benchmark scripts use the
    /// manifest parser above so no shell-side corpus or action authority remains.
    nonisolated static func configuration(arguments: [String]) -> Configuration? {
        guard let index = arguments.firstIndex(of: "--benchmark"),
              arguments.indices.contains(index + 1) else { return nil }
        func value(after flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
            return arguments[index + 1]
        }
        let scenario = Scenario(rawValue: arguments[index + 1]) ?? .typeProse
        let corpus = PerformanceCorpus(rawValue: value(after: "--corpus") ?? "") ?? .structuredProse
        let size = max(1, Int(value(after: "--size") ?? "100000") ?? 100_000)
        let seconds = max(1, Double(value(after: "--duration") ?? "5") ?? 5)
        let intervalMillis = max(1, Double(value(after: "--interval-ms") ?? "120") ?? 120)
        return Configuration(
            scenario: scenario,
            corpus: corpus,
            size: size,
            duration: .milliseconds(Int(seconds * 1_000)),
            interval: .milliseconds(Int(intervalMillis)),
            resultURL: nil
        )
    }

    static func run() async {
        guard !configurations.isEmpty,
              let controller = editorController() else { return }
        guard let session = controller.session, let document = controller.document else { return }

        try? await Task.sleep(for: .seconds(1))
        var completedCases: [CaseKey] = []
        for configuration in configurations where !Task.isCancelled {
            document.installTextForBenchmark(configuration.corpus.source(utf16Target: configuration.size))
            session.resetBenchmarkTransientState()
            try? await Task.sleep(for: .milliseconds(500))
            await waitForBenchmarkPresentation(session: session, document: document)
            // Discard work caused by installing the next fixture or by the preceding case. A
            // case's metrics must describe its own scenario, not cross-case reconciliation.
            session.performanceSampler?.drainSummaries()
            if configuration.scenario == .typeProse {
                guard let sourceCoordinator = sourceCoordinator(in: controller.presentingWindow?.contentView) else {
                    fatalError("benchmark: source coordinator is not attached to the editor window")
                }
                session.setMode(.source)
                await waitForBenchmarkSource(sourceCoordinator, document: document)
                guard let highlightTask = sourceCoordinator.highlight(debounced: false) else {
                    fatalError("benchmark: source coordinator could not schedule highlighting")
                }
                await highlightTask.value
                // The initial cache seed measures document-open styling, not ordinary typing.
                // Drain it before scenario actions so sourceHighlightCompute evidence describes
                // the incremental edit route promised by COR-72.
                session.performanceSampler?.drainSummaries()
            }
            var counters = Counters()
            let deadline = ContinuousClock.now + configuration.duration
            repeat {
                counters = counters + runOnce(configuration.scenario, controller: controller, session: session, document: document, corpus: configuration.corpus, size: configuration.size)
                try? await Task.sleep(for: configuration.interval)
            } while ContinuousClock.now < deadline && !Task.isCancelled

            let metrics = session.performanceSampler?.drainSummaries().map {
                MetricResult(
                    name: metricName($0.metric), count: $0.count,
                    p50Nanos: $0.p50, p95Nanos: $0.p95, maxNanos: $0.max,
                    budgetExceeded: $0.p95 > (PerformanceSampler.budgetNanos[$0.metric] ?? .max)
                )
            } ?? []
            let result = CaseResult(
                scenario: configuration.scenario,
                corpus: configuration.corpus,
                size: configuration.size,
                passed: accepts(BenchmarkCaseOutcome(
                    progress: counters.progress,
                    errors: counters.errors,
                    timeoutCount: counters.timeoutCount,
                    unknownActionCount: counters.unknownActionCount,
                    duplicateSampleCount: counters.duplicateSampleCount,
                    actionContractFailureCount: counters.actionContractFailures
                )),
                actionAttempts: counters.actionAttempts,
                accepted: counters.accepted,
                started: counters.started,
                refused: counters.refused,
                disabled: counters.disabled,
                progress: counters.progress,
                errors: counters.errors,
                timeoutCount: counters.timeoutCount,
                unknownActionCount: counters.unknownActionCount,
                duplicateSampleCount: counters.duplicateSampleCount,
                actionContractFailureCount: counters.actionContractFailures,
                actionOutcomes: counters.actionOutcomes,
                expectedActionAttemptsMinimum: minimumActionAttempts(for: configuration.scenario),
                expectedProgressMinimum: minimumProgress(for: configuration.scenario),
                metrics: metrics
            )
            if let resultURL = configuration.resultURL {
                do {
                    try FileManager.default.createDirectory(at: resultURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                    let data = try JSONEncoder().encode(result)
                    try data.write(to: resultURL, options: .atomic)
                    completedCases.append(CaseKey(scenario: configuration.scenario, corpus: configuration.corpus, size: configuration.size))
                } catch {
                    fatalError("benchmark result write failed: \(error.localizedDescription)")
                }
            }
        }

        if let first = configurations.first, let summaryURL = first.resultURL?.deletingLastPathComponent().appendingPathComponent("benchmark-summary.json") {
            let summary = BenchmarkSummary(
                expectedCases: configurations.map { CaseKey(scenario: $0.scenario, corpus: $0.corpus, size: $0.size) },
                completedCases: completedCases
            )
            do {
                try JSONEncoder().encode(summary).write(to: summaryURL, options: .atomic)
            } catch {
                fatalError("benchmark summary write failed: \(error.localizedDescription)")
            }
        }

        DiagnosticRunCoordinator.shared.flushAndInvalidateAll()
        DiagnosticLog.shared?.finishSynchronously()
        document.updateChangeCount(.changeCleared)
        NSApp.terminate(nil)
        // The benchmark is a process-level command-line verification. In a headless launch
        // SwiftUI/AppKit can return from terminate without draining the application event loop,
        // leaving the already-complete matrix process alive indefinitely. The durable runEnd
        // record has been synchronously written above, so terminate this verification process
        // explicitly rather than making Scripts/benchmark.sh guess whether the matrix finished.
        Foundation.exit(EXIT_SUCCESS)
    }

    static func runOnce(
        _ scenario: Scenario,
        controller: EditorCommandController,
        session: EditorSession,
        document: MarkdownDocument,
        corpus: PerformanceCorpus,
        size: Int
    ) -> Counters {
        switch scenario {
        case .typeProse, .typeInTable, .typeAdjacentMarkup:
            session.setMode(.source)
            let requested = corpus.source(utf16Target: min(size, 4_096))
            let payload: String = switch scenario {
            case .typeInTable: "| \(requested.replacingOccurrences(of: "\n", with: " ")) |"
            case .typeAdjacentMarkup: "**\(requested.prefix(64))**"
            default: String(requested.prefix(128))
            }
            let iterations = min(100, max(1, size / 2_500))
            var result = Counters()
            for _ in 0..<iterations {
                let outcome = session.perform(
                    .insertText(payload),
                    selection: .source(session.sourceModeState.selection),
                    expectedSourceRevision: SourceRevision(value: document.sourceVersion)
                )
                result.record(
                    mode: .source,
                    action: "insertText",
                    expected: .accepted,
                    observed: editWasAccepted(outcome) ? .accepted : .refused
                )
            }
            return result

        case .applyCommands:
            var result = Counters()
            for mode in [EditorMode.source, .wysiwyg] {
                for command in EditorCommand.allCases {
                    session.setMode(mode)
                    prepareBenchmarkSelection(mode: mode, session: session, document: document)
                    let expected = expectedOutcome(for: command, controller: controller)
                    let observed: BenchmarkActionResult
                    switch controller.perform(command) {
                    case .accepted: observed = .accepted
                    case .started: observed = .started
                    case .refused: observed = .refused
                    case .disabled: observed = .disabled
                    }
                    result.record(
                        mode: mode,
                        action: String(describing: command),
                        expected: expected,
                        observed: observed
                    )
                }
            }
            return result

        case .toggleModes:
            var result = Counters()
            for _ in 0..<40 {
                let next = session.mode == .source ? EditorMode.wysiwyg : .source
                session.setMode(next)
                result.record(
                    mode: next,
                    action: "toggleMode",
                    expected: .accepted,
                    observed: session.mode == next ? .accepted : .refused
                )
            }
            return result

        case .scrollDocument:
            session.setMode(.wysiwyg)
            var result = Counters()
            let windows = controller.presentingWindow.map { [$0] } ?? NSApp.windows
            let scrolls = windows.flatMap({ scrollViews(in: $0.contentView) })
            guard !scrolls.isEmpty else {
                result.record(mode: .wysiwyg, action: "scrollDocument", expected: .refused, observed: .refused)
                return result
            }
            let hasScrollableDocument = scrolls.contains { scrollView in
                waitForBenchmarkScrollLayout(in: scrollView)
                return canReachBenchmarkBottom(in: scrollView)
            }
            for scrollView in scrolls {
                waitForBenchmarkScrollLayout(in: scrollView)
                let maxY = measuredMaxScrollY(in: scrollView)
                guard maxY > 0 else { continue }
                for _ in 0..<8 {
                    let before = scrollView.contentView.bounds.origin.y
                    scrollView.contentView.setBoundsOrigin(NSPoint(x: 0, y: maxY))
                    // TextKit can clamp a measured used-rect height to a slightly smaller
                    // scrollable document frame. The invariant is real movement, not exact
                    // equality with a derived CGFloat target.
                    let moved = scrollView.contentView.bounds.origin.y > before + 0.5
                    scrollView.contentView.setBoundsOrigin(.zero)
                    if moved {
                        result.progress += 1
                        break
                    }
                    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.025))
                    scrollView.layoutSubtreeIfNeeded()
                    scrollView.documentView?.layoutSubtreeIfNeeded()
                }
                if result.progress > 0 { break }
            }
            result.record(
                mode: .wysiwyg,
                action: "scrollDocument",
                expected: hasScrollableDocument ? .accepted : .refused,
                observed: result.progress > 0 ? .accepted : .refused
            )
            return result

        case .undoRedoStorm:
            session.setMode(.source)
            var result = Counters()
            for _ in 0..<100 {
                let before = document.sourceVersion
                let outcome = session.perform(
                    .insertText("x"), selection: .source(session.sourceModeState.selection),
                    expectedSourceRevision: SourceRevision(value: document.sourceVersion),
                    grouping: .discrete
                )
                result.record(
                    mode: .source,
                    action: "insertText",
                    expected: .accepted,
                    observed: editWasAccepted(outcome) && document.sourceVersion != before ? .accepted : .refused
                )
            }
            for _ in 0..<100 {
                let before = document.sourceVersion
                document.undoManager?.undo()
                result.record(
                    mode: .source,
                    action: "undo",
                    expected: .accepted,
                    observed: document.sourceVersion != before ? .accepted : .refused
                )
            }
            for _ in 0..<100 {
                let before = document.sourceVersion
                document.undoManager?.redo()
                result.record(
                    mode: .source,
                    action: "redo",
                    expected: .accepted,
                    observed: document.sourceVersion != before ? .accepted : .refused
                )
            }
            return result

        case .openAndIdle:
            let ready = session.presentation?.sourceRevision.value == document.sourceVersion
            var result = Counters()
            result.record(
                mode: session.mode,
                action: "openAndIdle",
                expected: .accepted,
                observed: ready ? .accepted : .refused
            )
            return result

        case .soak:
            return runOnce(.typeProse, controller: controller, session: session, document: document, corpus: corpus, size: size)
                + runOnce(.toggleModes, controller: controller, session: session, document: document, corpus: corpus, size: size)
                + runOnce(.undoRedoStorm, controller: controller, session: session, document: document, corpus: corpus, size: size)
        }
    }

    private static func editorController() -> EditorCommandController? {
        NSApp.windows.compactMap { ($0.toolbar?.delegate as? EditorToolbarController)?.commandController }.first
    }

    private static func sourceCoordinator(in view: NSView?) -> SourceEditor.Coordinator? {
        guard let view else { return nil }
        if let sourceText = view as? MarkdownSourceTextView {
            return sourceText.sourceCoordinator
        }
        return view.subviews.lazy.compactMap { sourceCoordinator(in: $0) }.first
    }

    private static func metricName(_ metric: PerformanceSampler.Metric) -> String {
        switch metric {
        case .nativeInputCallback: return "nativeInputCallback"
        case .modeTransition: return "modeTransition"
        case .parseProjection: return "parseProjection"
        case .imageResolution: return "imageResolution"
        case .authoritativeApplication: return "authoritativeApplication"
        case .layoutApplication: return "layoutApplication"
        case .mainActorLatency: return "mainActorLatency"
        case .sourceHighlightApplication: return "sourceHighlightApplication"
        case .sourceHighlightCompute: return "sourceHighlightCompute"
        case .semanticCommand: return "semanticCommand"
        }
    }

    private static func scrollViews(in view: NSView?) -> [NSScrollView] {
        guard let view else { return [] }
        return (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap(scrollViews(in:))
    }

    private static func waitForBenchmarkScrollLayout(in scrollView: NSScrollView) {
        // Presentation installation is asynchronous. Give AppKit a bounded opportunity to
        // deliver its normal layout/display work before classifying a scroll as a no-op; this
        // preserves the no-progress error while avoiding a false error during a real transition.
        for _ in 0..<8 {
            scrollView.layoutSubtreeIfNeeded()
            scrollView.documentView?.layoutSubtreeIfNeeded()
            scrollView.displayIfNeeded()
            scrollView.documentView?.displayIfNeeded()
            if measuredMaxScrollY(in: scrollView) > 0 { return }
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.025))
        }
    }

    private static func canReachBenchmarkBottom(in scrollView: NSScrollView) -> Bool {
        let maxY = measuredMaxScrollY(in: scrollView)
        guard maxY > 0 else { return false }
        for _ in 0..<8 {
            let before = scrollView.contentView.bounds.origin.y
            scrollView.contentView.setBoundsOrigin(NSPoint(x: 0, y: maxY))
            // The scroll view is the authority for the reachable offset; measuredMaxScrollY
            // is only a candidate target and may exceed the clamped frame for large layouts.
            let moved = scrollView.contentView.bounds.origin.y > before + 0.5
            scrollView.contentView.setBoundsOrigin(.zero)
            if moved { return true }
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.025))
            scrollView.layoutSubtreeIfNeeded()
            scrollView.documentView?.layoutSubtreeIfNeeded()
        }
        return false
    }

    private static func waitForBenchmarkPresentation(session: EditorSession, document: MarkdownDocument) async {
        for _ in 0..<200 {
            if session.presentation?.sourceRevision.value == document.sourceVersion { return }
            try? await Task.sleep(for: .milliseconds(25))
        }
    }

    private static func waitForBenchmarkSource(
        _ coordinator: SourceEditor.Coordinator,
        document: MarkdownDocument
    ) async {
        for _ in 0..<200 {
            if coordinator.textView?.string == document.text { return }
            try? await Task.sleep(for: .milliseconds(25))
        }
        fatalError("benchmark: source editor did not receive the benchmark document")
    }

    private static func measuredMaxScrollY(in scrollView: NSScrollView) -> CGFloat {
        guard let documentView = scrollView.documentView else { return 0 }
        let renderedHeight: CGFloat
        if let textView = documentView as? NSTextView,
           let layoutManager = textView.layoutManager,
           let textContainer = textView.textContainer {
            let used = layoutManager.usedRect(for: textContainer)
            renderedHeight = max(
                textView.bounds.height,
                textView.frame.height,
                used.maxY + textView.textContainerInset.height * 2
            )
        } else {
            renderedHeight = documentView.bounds.height
        }
        return max(0, renderedHeight - scrollView.contentView.bounds.height)
    }
}
