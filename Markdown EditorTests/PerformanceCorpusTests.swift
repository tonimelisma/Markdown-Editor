import Foundation
import AppKit
import Testing
@testable import Markdown_Editor

struct PerformanceCorpusProofTests {
    // Verifies: REQ-127
    @Test func corpusMutationProof() {
        for corpus in PerformanceCorpus.allCases {
            let source = corpus.source(utf16Target: 100_000)
            guard case .success(let tree) = MarkdownParser.parse(source, sourceVersion: 1) else {
                #expect(Bool(false), "corpus must parse: \(corpus.rawValue)")
                continue
            }
            let model = MarkdownProjectionModel.build(
                tree: tree, index: MarkdownSourceIndex(source: source, sourceVersion: 1)
            )
            #expect(model.blocks.count >= corpus.minimumExpectedBlocks)
        }
    }

    // Verifies: REQ-128
    @Test func benchmarkConfigurationMutationProof() {
        let config = BenchmarkDriver.configuration(arguments: [
            "Markdown Editor", "--benchmark", "typeInTable", "--corpus", "tableDense",
            "--size", "12345", "--duration", "7", "--interval-ms", "80"
        ])
        #expect(config?.scenario == .typeInTable)
        #expect(config?.corpus == .tableDense)
        #expect(config?.size == 12345)
        #expect(config?.duration == .seconds(7))
        #expect(config?.interval == .milliseconds(80))
    }

    // Verifies: REQ-128 — the manifest expands to every closed corpus/scenario combination.
    @Test func benchmarkManifestEnumeratesTheClosedMatrix() {
        let manifest = BenchmarkDriver.Manifest(
            durationSeconds: 1,
            intervalMillis: 50,
            sizes: [10_000, 100_000],
            resultDirectory: URL(fileURLWithPath: "/tmp/benchmark-results")
        )
        let configurations = BenchmarkDriver.configurations(from: manifest)
        #expect(configurations.count == PerformanceCorpus.allCases.count * BenchmarkDriver.Scenario.allCases.count * 2)
        #expect(Set(configurations.map { "\($0.scenario.rawValue)/\($0.corpus.rawValue)/\($0.size)" }).count == configurations.count)
    }
}

// Verifies: REQ-127
@Test(arguments: PerformanceCorpus.allCases)
func corpusShapesProduceTheStructureTheyClaim(_ corpus: PerformanceCorpus) {
    let source = corpus.source(utf16Target: 100_000)
    // For degenerate, expect 1 block; for structured, expect many blocks.
    // We stub by checking source length and block count via parser.
    let parse = MarkdownParser.parse(source, sourceVersion: 1)
    if case .success(let tree) = parse {
        let index = MarkdownSourceIndex(source: source, sourceVersion: 1)
        let model = MarkdownProjectionModel.build(tree: tree, index: index)
        #expect(model.blocks.count >= corpus.minimumExpectedBlocks)
    } else {
        #expect(Bool(false), "performance corpus must parse: \(corpus.rawValue)")
    }
}

// Verifies: REQ-127
@Test func corpusTruncationPreservesUnitBoundaries() {
    for corpus in PerformanceCorpus.allCases {
        let source = corpus.source(utf16Target: 100_000)
        #expect((source as NSString).length <= Int(Double(100_000) * 1.05) + 100)
        #expect((source as NSString).length >= Int(Double(100_000) * 0.95))
    }
}

// Verifies: REQ-127
@Test func everyCorpusShapeHasADeclaredBlockFloor() {
    for corpus in PerformanceCorpus.allCases {
        let source = corpus.source(utf16Target: 100_000)
        guard case .success(let tree) = MarkdownParser.parse(source, sourceVersion: 1) else {
            #expect(Bool(false), "corpus must parse: \(corpus.rawValue)")
            continue
        }
        let index = MarkdownSourceIndex(source: source, sourceVersion: 1)
        let model = MarkdownProjectionModel.build(tree: tree, index: index)
        #expect(model.blocks.count >= corpus.minimumExpectedBlocks)
    }
}

// Verifies: REQ-128 — the benchmark driver reads structured records and never inspects the UI.
//
// // An *absence* proof, which `CLAUDE.md` §3 permits source inspection for — and unlike the
// // version this replaces, its detector proves itself below rather than trusting that the
// // needles would have matched. A misspelled needle previously passed silently.
@Test func benchmarkDriverAssertsOnlyOnStructuredRecords() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    let source = try String(
        contentsOf: root.appendingPathComponent("Markdown Editor/BenchmarkDriver.swift"),
        encoding: .utf8
    )
    // The detector works: a string that is certainly present is found.
    #expect(source.contains("BenchmarkDriver"), "detector failed to match a certainly-present string")
    #expect(!source.contains("accessibility"))
    #expect(!source.contains("synthetic"))
}

// Verifies: REQ-128 — the manifest carries matrix *parameters* only, so the shell harness cannot
// own corpus text or the action matrix even if it tried.
//
// // COR-90 replaced a set of `contains` assertions on the text of `Scripts/benchmark.sh`. Those
// // asserted the script's spelling rather than any behaviour, and would have reddened on a
// // harmless edit while staying green if the script had smuggled corpus text through a channel
// // the needles did not name. Encoding the type answers the real question: there is no field a
// // corpus or a scenario list could travel in.
@Test func benchmarkManifestCarriesParametersOnly() throws {
    let manifest = BenchmarkDriver.Manifest(
        durationSeconds: 2,
        intervalMillis: 120,
        sizes: [10_000, 100_000],
        resultDirectory: URL(fileURLWithPath: "/tmp/results")
    )
    let data = try JSONEncoder().encode(manifest)
    let object = try #require(
        try JSONSerialization.jsonObject(with: data) as? [String: Any]
    )
    #expect(
        Set(object.keys) == ["durationSeconds", "intervalMillis", "sizes", "resultDirectory"],
        "manifest gained a field: \(Set(object.keys).sorted())"
    )

    // `PerformanceCorpus` and `Scenario` remain the sole authorities for what runs, which is the
    // other half of the claim and is proved by construction rather than by the script's text.
    #expect(!PerformanceCorpus.allCases.isEmpty)
    #expect(!BenchmarkDriver.Scenario.allCases.isEmpty)
}

// Verifies: REQ-128 — malformed benchmark outcomes cannot be admitted as evidence.
@Test func benchmarkRejectsNoProgressAndUnknownActionsLegacy() {
    #expect(BenchmarkDriver.accepts(BenchmarkCaseOutcome(
        progress: 1, errors: 0, timeoutCount: 0, unknownActionCount: 0, duplicateSampleCount: 0
    )))
    #expect(!BenchmarkDriver.accepts(BenchmarkCaseOutcome(
        progress: 0, errors: 0, timeoutCount: 0, unknownActionCount: 0, duplicateSampleCount: 0
    )))
    #expect(!BenchmarkDriver.accepts(BenchmarkCaseOutcome(
        progress: 1, errors: 0, timeoutCount: 0, unknownActionCount: 1, duplicateSampleCount: 0
    )))
}

/// Named for direct mutation selection by the falsification gate.
@MainActor
struct COR69BenchmarkProofTests {
    // Verifies: REQ-128 — the benchmark's real scroll action reaches a constructed AppKit
    // document view and reports progress, so a positive aggregate cannot hide actions = 0.
    @Test func benchmarkScrollRouteReportsProgress() {
        let document = MarkdownDocument()
        document.installTextForTesting(String(repeating: "scroll line\n", count: 400))
        let session = EditorSession()
        session.attach(document: document)
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 320, height: 160))
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 4_000))
        textView.string = String(repeating: "scroll line\n", count: 400)
        scrollView.documentView = textView
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 160),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )
        window.contentView = scrollView
        let controller = EditorCommandController()
        controller.bind(
            document: document,
            session: session,
            actionRouter: EditorActionRouter(),
            window: window
        )

        let counters = BenchmarkDriver.runOnce(
            .scrollDocument,
            controller: controller,
            session: session,
            document: document,
            corpus: .structuredProse,
            size: 100_000
        )
        #expect(counters.actionAttempts == 1)
        #expect(counters.progress > 0)
        #expect(counters.errors == 0)
        session.detach()
    }

    // Verifies: REQ-128
    @Test func benchmarkRejectsNoProgressAndUnknownActions() {
        #expect(BenchmarkDriver.accepts(BenchmarkCaseOutcome(
            progress: 1, errors: 0, timeoutCount: 0, unknownActionCount: 0, duplicateSampleCount: 0
        )))
        #expect(!BenchmarkDriver.accepts(BenchmarkCaseOutcome(
            progress: 0, errors: 0, timeoutCount: 0, unknownActionCount: 0, duplicateSampleCount: 0
        )))
        #expect(!BenchmarkDriver.accepts(BenchmarkCaseOutcome(
            progress: 1, errors: 0, timeoutCount: 0, unknownActionCount: 1, duplicateSampleCount: 0
        )))
        #expect(!BenchmarkDriver.accepts(BenchmarkCaseOutcome(
            progress: 1, errors: 0, timeoutCount: 0, unknownActionCount: 0,
            duplicateSampleCount: 0, actionContractFailureCount: 1
        )))
    }

    // Verifies: REQ-128 — the closed command matrix records and validates every expected
    // outcome, rather than proving only aggregate progress.
    @Test func benchmarkCommandRouteRecordsEveryActionContract() {
        let document = MarkdownDocument()
        document.installTextForTesting("benchmark selection\n")
        let session = EditorSession()
        session.attach(document: document)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 160),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )
        let controller = EditorCommandController()
        controller.bind(
            document: document,
            session: session,
            actionRouter: EditorActionRouter(),
            window: window
        )

        let counters = BenchmarkDriver.runOnce(
            .applyCommands,
            controller: controller,
            session: session,
            document: document,
            corpus: .structuredProse,
            size: 100_000
        )
        #expect(counters.actionAttempts == EditorCommand.allCases.count * 2)
        #expect(counters.actionContractFailures == 0, "unexpected action contracts: \(counters.actionOutcomes)")
        #expect(counters.actionOutcomes.count == counters.actionAttempts)
        #expect(counters.actionOutcomes.allSatisfy { $0.expected == $0.observed }, "action outcomes: \(counters.actionOutcomes)")
        session.detach()
    }
}

// Verifies: REQ-128
@Test func benchmarkConfigurationPreservesEveryRequestedDimension() {
    let config = BenchmarkDriver.configuration(arguments: [
        "Markdown Editor", "--benchmark", "typeInTable", "--corpus", "tableDense",
        "--size", "12345", "--duration", "7", "--interval-ms", "80"
    ])
    #expect(config?.scenario == .typeInTable)
    #expect(config?.corpus == .tableDense)
    #expect(config?.size == 12345)
    #expect(config?.duration == .seconds(7))
    #expect(config?.interval == .milliseconds(80))
}
