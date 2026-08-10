import AppKit
import Foundation

/// Process-level benchmark driver, reachable only via --benchmark.
///
/// // REQ-128.
nonisolated enum BenchmarkDriver {
    enum Scenario: String, CaseIterable {
        case typeProse, typeInTable, typeAdjacentMarkup, applyCommands, toggleModes, scrollDocument, undoRedoStorm, openAndIdle, soak
    }

    static func runIfRequested() -> Bool {
        let args = CommandLine.arguments
        guard let idx = args.firstIndex(of: "--benchmark"), idx + 1 < args.count else { return false }
        let scenarioRaw = args[idx + 1]
        let scenario = Scenario(rawValue: scenarioRaw) ?? .typeProse
        let corpusRaw = args.firstIndex(of: "--corpus").flatMap { args.indices.contains($0+1) ? args[$0+1] : nil } ?? "structuredProse"
        let corpus = PerformanceCorpus(rawValue: corpusRaw) ?? .structuredProse
        let size = args.firstIndex(of: "--size").flatMap { Int(args[$0+1]) } ?? 100_000
        let source = corpus.source(utf16Target: size)
        print("benchmark scenario=\(scenario.rawValue) corpus=\(corpus.rawValue) size=\(size) sourceLength=\((source as NSString).length)")
        return true
    }
}
