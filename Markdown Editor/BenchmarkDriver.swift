import AppKit
import Foundation

/// Process-level benchmark driver, reachable only through `--benchmark`.
///
/// It drives the same window-owned session and command controller as ordinary application use;
/// it never synthesizes events or reads view pixels. The only output consumed by the harness is
/// the structured diagnostic log produced by the normal production routes.
///
/// // REQ-128; ARC-Q12.
@MainActor
enum BenchmarkDriver {
    enum Scenario: String, CaseIterable, Sendable {
        case typeProse, typeInTable, typeAdjacentMarkup, applyCommands, toggleModes
        case scrollDocument, undoRedoStorm, openAndIdle, soak
    }

    struct Configuration: Sendable {
        let scenario: Scenario
        let corpus: PerformanceCorpus
        let size: Int
        let duration: Duration
        let interval: Duration
    }

    private static var configuration: Configuration?

    static var isRequested: Bool {
        CommandLine.arguments.contains("--benchmark")
    }

    static func runIfRequested() -> Bool {
        guard let index = CommandLine.arguments.firstIndex(of: "--benchmark"),
              CommandLine.arguments.indices.contains(index + 1) else { return false }
        let scenario = Scenario(rawValue: CommandLine.arguments[index + 1]) ?? .typeProse
        let corpusName = value(after: "--corpus") ?? PerformanceCorpus.structuredProse.rawValue
        let corpus = PerformanceCorpus(rawValue: corpusName) ?? .structuredProse
        let size = max(1, Int(value(after: "--size") ?? "100000") ?? 100_000)
        let seconds = max(1, Double(value(after: "--duration") ?? "5") ?? 5)
        let intervalMillis = max(1, Double(value(after: "--interval-ms") ?? "120") ?? 120)
        configuration = Configuration(
            scenario: scenario,
            corpus: corpus,
            size: size,
            duration: .milliseconds(Int(seconds * 1_000)),
            interval: .milliseconds(Int(intervalMillis))
        )
        return true
    }

    static func run() async {
        guard let configuration else { return }
        // Let the fixture's first authoritative projection land before measuring the scenario.
        try? await Task.sleep(for: .seconds(1))
        let deadline = ContinuousClock.now + configuration.duration
        repeat {
            runOnce(configuration.scenario)
            try? await Task.sleep(for: configuration.interval)
        } while ContinuousClock.now < deadline && !Task.isCancelled

        DiagnosticRunCoordinator.shared.flushAndInvalidateAll()
        DiagnosticLog.shared?.finishSynchronously()
        // The benchmark intentionally mutates its fixture. Mark that benchmark run clean before
        // terminating so AppKit does not open a save-confirmation panel in the headless process.
        // Ordinary user documents never pass through this driver and retain normal save prompts.
        for document in NSDocumentController.shared.documents {
            document.updateChangeCount(.changeCleared)
        }
        NSApp.terminate(nil)
    }

    private static func runOnce(_ scenario: Scenario) {
        guard let controller = NSApp.windows
            .compactMap({ ($0.toolbar?.delegate as? EditorToolbarController)?.commandController })
            .first,
            let session = controller.session,
            let document = controller.document else { return }

        switch scenario {
        case .typeProse, .typeInTable, .typeAdjacentMarkup:
            session.setMode(.source)
            for _ in 0..<40 {
                let selection = session.sourceModeState.selection
                _ = session.perform(
                    .insertText("x"),
                    selection: .source(selection),
                    expectedSourceRevision: SourceRevision(value: document.sourceVersion)
                )
            }
        case .applyCommands:
            for mode in [EditorMode.source, .wysiwyg] {
                session.setMode(mode)
                // Add Image owns an asynchronous NSOpenPanel and Edit Link owns a modal sheet;
                // neither can complete in a process-level, non-UI benchmark. Their routes are
                // covered by the component suites; every deterministic editor route remains in
                // this liveness matrix.
                for command in EditorCommand.allCases where command != .addImage && command != .editLink {
                    _ = controller.perform(command)
                }
            }
        case .toggleModes:
            for _ in 0..<40 {
                session.setMode(session.mode == .source ? .wysiwyg : .source)
            }
        case .scrollDocument:
            for scrollView in scrollViews(in: NSApp.windows.first?.contentView) {
                let maxY = max(0, scrollView.documentView?.bounds.height ?? 0 - scrollView.contentView.bounds.height)
                scrollView.contentView.setBoundsOrigin(NSPoint(x: 0, y: maxY))
                scrollView.contentView.setBoundsOrigin(.zero)
            }
        case .undoRedoStorm:
            session.setMode(.source)
            for _ in 0..<100 {
                let selection = session.sourceModeState.selection
                _ = session.perform(
                    .insertText("x"),
                    selection: .source(selection),
                    expectedSourceRevision: SourceRevision(value: document.sourceVersion)
                )
            }
            for _ in 0..<100 { document.undoManager?.undo() }
            for _ in 0..<100 { document.undoManager?.redo() }
        case .openAndIdle:
            break
        case .soak:
            runOnce(.typeProse)
            runOnce(.toggleModes)
            runOnce(.undoRedoStorm)
        }
    }

    private static func value(after flag: String) -> String? {
        guard let index = CommandLine.arguments.firstIndex(of: flag),
              CommandLine.arguments.indices.contains(index + 1) else { return nil }
        return CommandLine.arguments[index + 1]
    }

    private static func scrollViews(in view: NSView?) -> [NSScrollView] {
        guard let view else { return [] }
        return (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap(scrollViews(in:))
    }
}
