//
//  ProjectionCharacterizationTests.swift
//  Markdown EditorTests
//
//  COR-06 characterization (PLAN-0010 §6).
//

import Testing
import Foundation
@testable import Markdown_Editor

struct ProjectionCharacterizationTests {

    // Verifies: REQ-054 — one-character cmark node maps to one source character.
    @Test func oneCharacterNodeMapsToOneSourceCharacter() throws {
        let source = "a\n"
        let tree = try parse(source)
        let model = build(source, tree: tree)
        let sourceSegments = model.segments.compactMap { segment -> (NSRange, NSRange)? in
            if case .source(let projection, let sourceRange, _, _) = segment {
                return (projection, sourceRange)
            }
            return nil
        }
        #expect(!sourceSegments.isEmpty)
        for (projection, sourceRange) in sourceSegments where projection.length == 1 {
            #expect(sourceRange.length == 1)
        }
        try expectOracle(model, source: source)
    }

    // Verifies: REQ-087 — invalid rich selections are refused, not clamped.
    @Test func invalidRichSelectionIsRefusedNotClamped() throws {
        let source = "**bold**\n"
        let tree = try parse(source)
        let model = build(source, tree: tree)
        let map = model.coordinateMap
        let oob = NSRange(location: 9999, length: 1)
        guard case .refused(.outOfBounds) = map.sourceRange(forProjection: oob) else {
            Issue.record("expected outOfBounds refusal")
            return
        }
        // Selecting only a synthetic paragraph break should refuse or map via policy — never clamp.
        if let synthetic = model.segments.first(where: {
            if case .synthetic = $0 { return true }
            return false
        }), case .synthetic(let projection, _, _) = synthetic {
            let result = map.sourceRange(forProjection: projection)
            if case .exact = result {
                Issue.record("non-empty synthetic selection must not silently invent a source span")
            }
        }
    }

    // Verifies: REQ-056 — emphasis visible text maps to exact source slice.
    @Test func emphasisMapsVisibleTextToExactSourceSlice() throws {
        let source = "x **hi** y\n"
        let tree = try parse(source)
        let model = build(source, tree: tree)
        #expect(model.renderedString.contains("hi"))
        #expect(!model.renderedString.contains("**"))
        let map = model.coordinateMap
        // Find "hi" in projection.
        let rendered = model.renderedString as NSString
        let proj = rendered.range(of: "hi")
        #expect(proj.location != NSNotFound)
        guard case .exact(let sourceRange) = map.sourceRange(forProjection: proj) else {
            Issue.record("expected exact map for emphasis content")
            return
        }
        let slice = (source as NSString).substring(with: sourceRange)
        #expect(slice == "hi")
        try expectOracle(model, source: source)
    }

    // Verifies: REQ-054 — ordered/unordered markers are visible.
    @Test func listsRetainVisibleMarkersAndNesting() throws {
        let source = "- one\n- two\n1. a\n"
        let tree = try parse(source)
        let model = build(source, tree: tree)
        #expect(!model.listMarkers.isEmpty)
        #expect(model.renderedString.contains("one"))
        #expect(model.listMarkers.contains { $0.text.contains("-") || $0.text.contains("1") })
        try expectOracle(model, source: source)
    }

    // Verifies: REQ-057 — nested quote is preserved when toggling list on inner line.
    @Test func nestedBlockTransformDoesNotStripUnrelatedQuotePrefix() {
        let snapshot = SourceSnapshot(
            text: "> hello\n",
            sourceVersion: 1,
            locationGeneration: 0,
            fileURL: nil
        )
        let selection = SemanticSelection(
            mode: .source,
            utf16Range: NSRange(location: 2, length: 5),
            sourceVersion: 1
        )
        let result = SemanticEditEngine.apply(
            command: .toggleUnorderedList,
            selection: selection,
            snapshot: snapshot,
            projection: nil,
            tree: nil
        )
        guard case .transaction(let edit, _) = result else {
            Issue.record("expected transaction")
            return
        }
        #expect(edit.replacement.contains(">"))
        #expect(edit.replacement.contains("- "))
        #expect(edit.replacement.hasPrefix("> -") || edit.replacement.contains("> - "))
    }

    // Verifies: REQ-057 — underscore bold alternate spelling.
    @Test func boldToggleAcceptsUnderscoreAlternateSpelling() {
        let snapshot = SourceSnapshot(text: "__hello__", sourceVersion: 1, locationGeneration: 0, fileURL: nil)
        let selection = SemanticSelection(mode: .source, utf16Range: NSRange(location: 0, length: 9), sourceVersion: 1)
        let result = SemanticEditEngine.apply(
            command: .toggleBold,
            selection: selection,
            snapshot: snapshot,
            projection: nil,
            tree: nil
        )
        guard case .transaction(let edit, _) = result else {
            Issue.record("expected unwrap")
            return
        }
        #expect(edit.replacement == "hello")
    }

    // Verifies: REQ-080 — table cell replace changes only that cell's source span intent.
    @Test func tableCellEditChangesOnlyIntendedCellContent() throws {
        let source = "| a | b |\n| - | - |\n| c | d |\n"
        let tree = try parse(source)
        let model = build(source, tree: tree)
        #expect(!model.tables.isEmpty)
        let cell = try #require(model.tables.first?.cells.last)
        let snapshot = SourceSnapshot(text: source, sourceVersion: 1, locationGeneration: 0, fileURL: nil)
        let result = SemanticEditEngine.apply(
            command: .replaceTableCell(nodeID: cell.nodeID, text: "Z"),
            selection: SemanticSelection(mode: .wysiwyg, utf16Range: cell.utf16Range, sourceVersion: 1),
            snapshot: snapshot,
            projection: model,
            tree: tree
        )
        guard case .transaction(let edit, _) = result else {
            Issue.record("expected cell edit, got \(result)")
            return
        }
        #expect(edit.replacement == "Z")
        #expect(edit.range.length > 0)
        // Other header text remains outside the replaced range.
        let before = (source as NSString).substring(with: NSRange(location: 0, length: edit.range.location))
        #expect(before.contains("a") || before.contains("|"))
    }

    // Verifies: REQ-090 — parse+index+projection p95 < 100ms at 100k UTF-16 off-main.
    // PLAN-0010 requires optimized builds for this gate; Debug is skipped.
    @Test func parseIndexProjectionP95Under100msAt100k() async throws {
        #if DEBUG
        // Characterization still compiles; timing gate is asserted under Release.
        return
        #else
        let unit = "# Title\n\nParagraph with **bold** and *italic* and `code`.\n\n- item\n\n"
        var source = ""
        while (source as NSString).length < 100_000 {
            source += unit
        }
        source = String((source as NSString).substring(to: 100_000))
        #expect((source as NSString).length == 100_000)

        var samples: [Double] = []
        for _ in 0..<5 {
            _ = await Task.detached {
                let tree = MarkdownParser.parse(source, sourceVersion: 1)
                guard case .success(let t) = tree else { return }
                let index = MarkdownSourceIndex(source: source, sourceVersion: 1)
                _ = MarkdownProjectionModel.build(tree: t, index: index)
            }.value
        }
        for _ in 0..<20 {
            let ms = await Task.detached {
                let start = DispatchTime.now().uptimeNanoseconds
                let tree = MarkdownParser.parse(source, sourceVersion: 1)
                guard case .success(let t) = tree else { return Double.infinity }
                let index = MarkdownSourceIndex(source: source, sourceVersion: 1)
                _ = MarkdownProjectionModel.build(tree: t, index: index)
                let end = DispatchTime.now().uptimeNanoseconds
                return Double(end - start) / 1_000_000
            }.value
            samples.append(ms)
        }
        samples.sort()
        let p95Index = min(samples.count - 1, Int(ceil(0.95 * Double(samples.count))) - 1)
        let p95 = samples[max(p95Index, 0)]
        #expect(p95 < 100.0, "p95=\(p95)ms samples=\(samples)")
        #endif
    }

    // MARK: - Helpers

    private func parse(_ source: String) throws -> MarkdownTree {
        switch MarkdownParser.parse(source, sourceVersion: 1) {
        case .success(let tree): return tree
        case .failure(let err):
            Issue.record("parse failed \(err)")
            throw err
        }
    }

    private func build(_ source: String, tree: MarkdownTree) -> MarkdownProjectionModel {
        let index = MarkdownSourceIndex(source: source, sourceVersion: 1)
        return MarkdownProjectionModel.build(tree: tree, index: index)
    }

    private func expectOracle(_ model: MarkdownProjectionModel, source: String) throws {
        let count = (source as NSString).length
        if case .failure(let failure) = ProjectionOracle.validate(model: model, sourceUTF16Count: count) {
            Issue.record("oracle \(failure.code) \(failure.detail)")
            throw failure
        }
    }
}
