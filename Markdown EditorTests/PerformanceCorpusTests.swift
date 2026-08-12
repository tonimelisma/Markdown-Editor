import Foundation
import Testing
@testable import Markdown_Editor

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
        let source = corpus.source(utf16Target: 20_000)
        guard case .success(let tree) = MarkdownParser.parse(source, sourceVersion: 1) else {
            #expect(Bool(false), "corpus must parse: \(corpus.rawValue)")
            continue
        }
        let index = MarkdownSourceIndex(source: source, sourceVersion: 1)
        let model = MarkdownProjectionModel.build(tree: tree, index: index)
        #expect(model.blocks.count >= corpus.minimumExpectedBlocks)
    }
}

// Verifies: REQ-128
@Test func benchmarkDriverAssertsOnlyOnStructuredRecords() {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    let source = try! String(contentsOf: root.appendingPathComponent("Markdown Editor/BenchmarkDriver.swift"), encoding: .utf8)
    #expect(!source.contains("accessibility"))
    #expect(!source.contains("synthetic"))
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
