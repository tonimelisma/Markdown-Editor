//
//  ProjectionCharacterizationTests.swift
//  Markdown EditorTests
//
//  Projection behavior characterization.
//

import Testing
import Foundation
@testable import Markdown_Editor

struct ProjectionCharacterizationTests {

    // Verifies: REQ-054/079 — link children preserve the same soft/hard break contract as
    // ordinary inline children.
    @Test func linksPreserveSoftAndHardBreakSemantics() throws {
        let softSource = "[one\ntwo](https://example.com)\n"
        let hardSource = "[one  \ntwo](https://example.com)\n"
        let soft = build(softSource, tree: try parse(softSource))
        let hard = build(hardSource, tree: try parse(hardSource))
        #expect(soft.renderedString == "one two\n")
        #expect(hard.renderedString == "one\ntwo\n")
        #expect(soft.segments.contains { if case .synthetic(_, .softLineBreak, _) = $0 { return true }; return false })
        #expect(hard.segments.contains { if case .synthetic(_, .hardLineBreak, _) = $0 { return true }; return false })
    }

    // Verifies: REQ-109 — a line break inserts where its line ends. cmark gives soft and hard
    // break nodes no source position, and their insertion location fell back to 0, the start of
    // the document: a provisional snapshot shifted that 0 with each keystroke typed before the
    // break, the parse put it back, and every such keystroke was recovered as a COR-71 fault.
    @Test func lineBreaksInsertWhereTheirLineEnds() throws {
        func insertions(_ source: String, _ kind: SyntheticKind) throws -> [SyntheticInsertionPolicy] {
            build(source, tree: try parse(source)).segments.compactMap {
                if case .synthetic(_, let k, let insertion) = $0, k == kind { return insertion }
                return nil
            }
        }
        // "first" spans UTF-16 7..<12 in "Intro\n\nfirst\nsecond\n"; the soft break follows it.
        #expect(try insertions("Intro\n\nfirst\nsecond\n", .softLineBreak) == [.atSourceLocation(12)])
        // A hard break may carry a position of its own; either way it is not the document's start.
        let hard = try insertions("Intro\n\nfirst\\\nsecond\n", .hardLineBreak)
        #expect(hard.count == 1 && !hard.contains(.atSourceLocation(0)), "hard break inserts at \(hard)")
    }

    // Verifies: REQ-080/105 — every semantic table cell is a distinct paragraph rather than a
    // tab-delimited span, allowing TextKit's paragraph-level table blocks to form columns.
    @Test func tableCellsUseParagraphSeparators() throws {
        let source = "| left | right |\n| - | - |\n| one | two |\n"
        let model = build(source, tree: try parse(source))
        #expect(!model.renderedString.contains("\t"))
        #expect(model.tables.first?.cells.count == 4)
    }

    // Verifies: REQ-087; ARC-009 — uneditable/refuse boundaries never invent source offset zero.
    @Test func uneditableBoundariesRefuseInsteadOfMappingToZero() {
        let uneditable = ProjectionCoordinateMap(
            segments: [
                .source(
                    projection: NSRange(location: 0, length: 1),
                    source: NSRange(location: 0, length: 1),
                    insertionBefore: 0,
                    insertionAfter: 1
                ),
                .uneditable(
                    projection: NSRange(location: 1, length: 1),
                    reason: .unsupported
                )
            ],
            projectionUTF16Count: 2,
            sourceUTF16Count: 2
        )
        if case .refused = uneditable.sourceRange(
            forProjection: NSRange(location: 2, length: 0),
            affinity: .downstream
        ) {
            // expected
        } else {
            Issue.record("trailing uneditable boundary must refuse")
        }

        let synthetic = ProjectionCoordinateMap(
            segments: [
                .synthetic(
                    projection: NSRange(location: 0, length: 1),
                    kind: .paragraphBreak,
                    insertion: .refuse
                )
            ],
            projectionUTF16Count: 1,
            sourceUTF16Count: 0
        )
        for location in 0...1 {
            if case .refused = synthetic.sourceRange(
                forProjection: NSRange(location: location, length: 0),
                affinity: .downstream
            ) {
                continue
            }
            Issue.record("refuse-policy boundary \(location) must refuse")
        }
    }

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
        let selection = TestSelection(
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
        guard case .mutation(let mutation) = result else {
            Issue.record("expected transaction")
            return
        }
        #expect(mutation.replacement == "> - hello\n")
    }

    // Verifies: REQ-057 — underscore bold alternate spelling.
    @Test func boldToggleAcceptsUnderscoreAlternateSpelling() {
        let snapshot = SourceSnapshot(text: "__hello__", sourceVersion: 1, locationGeneration: 0, fileURL: nil)
        let selection = TestSelection(mode: .source, utf16Range: NSRange(location: 0, length: 9), sourceVersion: 1)
        let result = SemanticEditEngine.apply(
            command: .toggleBold,
            selection: selection,
            snapshot: snapshot,
            projection: nil,
            tree: nil
        )
        guard case .mutation(let mutation) = result else {
            Issue.record("expected unwrap")
            return
        }
        #expect(mutation.replacement == "hello")
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
            selection: TestSelection(mode: .wysiwyg, utf16Range: cell.utf16Range, sourceVersion: 1),
            snapshot: snapshot,
            projection: model,
            tree: tree
        )
        guard case .mutation(let mutation) = result else {
            Issue.record("expected cell edit, got \(result)")
            return
        }
        #expect(mutation.replacement == "Z")
        #expect(mutation.range.length > 0)
        // Other header text remains outside the replaced range.
        let before = (source as NSString).substring(with: NSRange(location: 0, length: mutation.range.location))
        #expect(before.contains("a") || before.contains("|"))
    }

    // Verifies: REQ-080
    @Test func tableCellClearEmptyTextIsAccepted() {
        let source = "| a | b |\n| - | - |\n| c | d |\n"
        guard case .success(let tree) = MarkdownParser.parse(source, sourceVersion: 1) else {
            Issue.record("parse failed")
            return
        }
        let model = build(source, tree: tree)
        guard let cell = model.tables.first?.cells.last else {
            Issue.record("missing cell")
            return
        }
        let snapshot = SourceSnapshot(text: source, sourceVersion: 1, locationGeneration: 0, fileURL: nil)
        let result = SemanticEditEngine.apply(
            command: .replaceTableCell(nodeID: cell.nodeID, text: ""),
            selection: TestSelection(mode: .wysiwyg, utf16Range: cell.utf16Range, sourceVersion: 1),
            snapshot: snapshot,
            projection: model,
            tree: tree
        )
        guard case .mutation(let mutation) = result else {
            Issue.record("expected empty cell clear, got \(result)")
            return
        }
        #expect(mutation.replacement.isEmpty)
    }

    // Verifies: REQ-080/087
    @Test func tableCellEditRefusesStructuralBreakers() {
        let source = "| a | b |\n| - | - |\n| c | d |\n"
        guard case .success(let tree) = MarkdownParser.parse(source, sourceVersion: 1) else {
            Issue.record("parse failed")
            return
        }
        let model = build(source, tree: tree)
        let cell = model.tables.first?.cells.last
        guard let cell else {
            Issue.record("missing cell")
            return
        }
        let snapshot = SourceSnapshot(text: source, sourceVersion: 1, locationGeneration: 0, fileURL: nil)
        let pipe = SemanticEditEngine.apply(
            command: .replaceTableCell(nodeID: cell.nodeID, text: "x|y"),
            selection: TestSelection(mode: .wysiwyg, utf16Range: cell.utf16Range, sourceVersion: 1),
            snapshot: snapshot,
            projection: model,
            tree: tree
        )
        guard case .refused = pipe else {
            Issue.record("expected refusal for pipe, got \(pipe)")
            return
        }
    }

    // Verifies: REQ-080
    @Test func tableCellAllowsEscapedPipe() {
        let source = "| a | b |\n| - | - |\n| c | d |\n"
        guard case .success(let tree) = MarkdownParser.parse(source, sourceVersion: 1) else {
            Issue.record("parse failed")
            return
        }
        let model = build(source, tree: tree)
        let cell = model.tables.first?.cells.last
        guard let cell else {
            Issue.record("missing cell")
            return
        }
        let snapshot = SourceSnapshot(text: source, sourceVersion: 1, locationGeneration: 0, fileURL: nil)
        let result = SemanticEditEngine.apply(
            command: .replaceTableCell(nodeID: cell.nodeID, text: "x\\|y"),
            selection: TestSelection(mode: .wysiwyg, utf16Range: cell.utf16Range, sourceVersion: 1),
            snapshot: snapshot,
            projection: model,
            tree: tree
        )
        guard case .mutation = result else {
            Issue.record("expected transaction for escaped pipe, got \(result)")
            return
        }
    }

    // Verifies: REQ-057
    @Test func inlineWrapPostconditionRequiresNodeAtEditedSpan() {
        let snapshot = SourceSnapshot(
            text: "**already** plain\n",
            sourceVersion: 1,
            locationGeneration: 0,
            fileURL: nil
        )
        // Wrapping "plain" must succeed because a strong node covers that span after edit.
        let ok = InlineEditPlanner.wrap(
            snapshot: snapshot,
            range: NSRange(location: 12, length: 5),
            delimiters: [("**", "**"), ("__", "__")],
            action: "Bold"
        ) { kind in
            if case .strong = kind { return true }
            return false
        }
        guard case .mutation = ok else {
            Issue.record("expected wrap of plain text, got \(ok)")
            return
        }
    }

    // Verifies: REQ-084
    @Test func orderedMarkersIncrementAndTrailingCaretMapsAfterMarker() throws {
        let source = "1. a\n2. b\n"
        let tree = try parse(source)
        let model = build(source, tree: tree)
        #expect(model.listMarkers.map(\.text) == ["1. ", "2. "])
        // Caret at end of first marker in projection.
        guard let first = model.listMarkers.first else {
            Issue.record("missing marker")
            return
        }
        let afterMarker = NSRange(location: NSMaxRange(first.utf16Range), length: 0)
        guard case .exact(let sourceCaret) = model.coordinateMap.sourceRange(
            forProjection: afterMarker,
            affinity: .downstream
        ) else {
            Issue.record("expected exact caret map after marker")
            return
        }
        // Source after "1. " is offset 3.
        #expect(sourceCaret.location == 3)
        try expectOracle(model, source: source)
    }

    // Verifies: REQ-084
    @Test func inlineCodeContentSourceExcludesBackticks() throws {
        let source = "a `xy` b\n"
        let tree = try parse(source)
        let model = build(source, tree: tree)
        let rendered = model.renderedString as NSString
        let proj = rendered.range(of: "xy")
        #expect(proj.location != NSNotFound)
        guard case .exact(let sourceRange) = model.coordinateMap.sourceRange(forProjection: proj) else {
            Issue.record("expected exact map for code literal")
            return
        }
        #expect((source as NSString).substring(with: sourceRange) == "xy")
        #expect(sourceRange.length == 2)
        try expectOracle(model, source: source)
    }

    // Verifies: REQ-084
    @Test func selectionAcrossParagraphBreakMapsContiguousSource() throws {
        let source = "one\n\ntwo\n"
        let tree = try parse(source)
        let model = build(source, tree: tree)
        let rendered = model.renderedString as NSString
        let start = rendered.range(of: "one").location
        let end = NSMaxRange(rendered.range(of: "two"))
        let cross = NSRange(location: start, length: end - start)
        guard case .exact(let sourceRange) = model.coordinateMap.sourceRange(forProjection: cross) else {
            Issue.record("expected bridged mapping across synthetic break")
            return
        }
        #expect(sourceRange.length > 0)
        try expectOracle(model, source: source)
    }

    // Verifies: REQ-084 — selection from list marker through item text maps to source.
    @Test func selectionStartingOnListMarkerMapsToSource() throws {
        let source = "1. a\n"
        let tree = try parse(source)
        let model = build(source, tree: tree)
        guard let marker = model.listMarkers.first else {
            Issue.record("missing list marker")
            return
        }
        let rendered = model.renderedString as NSString
        let textRange = rendered.range(of: "a")
        #expect(textRange.location != NSNotFound)
        let selection = NSRange(
            location: marker.utf16Range.location,
            length: NSMaxRange(textRange) - marker.utf16Range.location
        )
        #expect(selection.length > 0)
        let result = model.coordinateMap.sourceRange(forProjection: selection)
        guard case .exact(let sourceRange) = result else {
            Issue.record("expected exact map for marker-through-text selection, got \(result)")
            return
        }
        #expect((source as NSString).substring(with: sourceRange).contains("a"))
        try expectOracle(model, source: source)
    }

    // Verifies: REQ-090 — parse+index+projection p95 < 100ms at 100k UTF-16 off-main.
    // The performance requirement applies to optimized builds; Debug is skipped.
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
        let evidence = recordPerformanceEvidence(
            name: "parse-index-projection",
            corpus: source,
            warmups: 5,
            samples: samples
        )
        #expect(evidence.failures.isEmpty, "performance evidence failures: \(evidence.failures)")
        #expect(evidence.samples.count > 0)
        if let p95 = evidence.p95 {
            #expect(p95 < 100.0, "p95=\(p95)ms samples=\(evidence.samples)")
        }
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
