//
//  ProjectionAndSemanticEditTests.swift
//  Markdown EditorTests
//

import XCTest
@testable import Markdown_Editor

final class ProjectionAndSemanticEditTests: XCTestCase {
    // Verifies: REQ-056
    func testProjectionOmitsParsedDelimiters() throws {
        let source = "# Title\nThis has **bold** and *italic* and ~~strike~~ and `code` and [link](https://a.test)\n"
        let tree = try XCTUnwrap(MarkdownParser.parse(source, sourceVersion: 1).get())
        let index = MarkdownSourceIndex(source: source, sourceVersion: 1)
        let model = MarkdownProjectionModel.build(tree: tree, index: index)
        let rendered = model.renderedString
        XCTAssertFalse(rendered.contains("**"))
        XCTAssertFalse(rendered.contains("~~"))
        XCTAssertFalse(rendered.contains("`"))
        XCTAssertFalse(rendered.contains("[link]("))
        XCTAssertFalse(rendered.contains("# Title"))
        XCTAssertTrue(rendered.contains("Title"))
        XCTAssertTrue(rendered.contains("bold"))
        XCTAssertTrue(model.runs.contains { $0.styles.contains(.strong) })
        XCTAssertTrue(model.runs.contains { $0.linkDestination == "https://a.test" })
    }

    // Verifies: REQ-055
    func testUnsupportedAndHTMLRemainLiteral() throws {
        let source = "==mark==\n\n<div>raw</div>\n"
        let tree = try XCTUnwrap(MarkdownParser.parse(source, sourceVersion: 0).get())
        let index = MarkdownSourceIndex(source: source, sourceVersion: 0)
        let model = MarkdownProjectionModel.build(tree: tree, index: index)
        XCTAssertTrue(model.renderedString.contains("==mark==") || model.renderedString.contains("mark"))
        XCTAssertTrue(model.renderedString.contains("<div>raw</div>") || model.runs.contains(where: \.isLiteralFallback))
    }

    // Verifies: REQ-057/058
    func testBoldTogglePreservesSpellingWhenSafe() {
        let snapshot = SourceSnapshot(text: "hello world", sourceVersion: 3, locationGeneration: 0, fileURL: nil)
        let selection = TestSelection(mode: .source, utf16Range: NSRange(location: 0, length: 5), sourceVersion: 3)
        let result = SemanticEditEngine.apply(
            command: .toggleBold,
            selection: selection,
            snapshot: snapshot,
            projection: nil,
            tree: nil
        )
        guard case .mutation(let mutation) = result else {
            return XCTFail("expected mutation")
        }
        XCTAssertEqual(mutation.replacement, "**hello**")
        let wrapped = SourceSnapshot(text: "**hello** world", sourceVersion: 4, locationGeneration: 0, fileURL: nil)
        let sel2 = TestSelection(mode: .source, utf16Range: NSRange(location: 0, length: 9), sourceVersion: 4)
        let result2 = SemanticEditEngine.apply(command: .toggleBold, selection: sel2, snapshot: wrapped, projection: nil, tree: nil)
        guard case .mutation(let mutation2) = result2 else {
            return XCTFail("expected unwrap")
        }
        XCTAssertEqual(mutation2.replacement, "hello")
    }

    // Verifies: REQ-057
    func testStrikethroughUsesDoubleTildeOnly() {
        let snapshot = SourceSnapshot(text: "strike", sourceVersion: 1, locationGeneration: 0, fileURL: nil)
        let selection = TestSelection(mode: .source, utf16Range: NSRange(location: 0, length: 6), sourceVersion: 1)
        let result = SemanticEditEngine.apply(command: .toggleStrikethrough, selection: selection, snapshot: snapshot, projection: nil, tree: nil)
        guard case .mutation(let mutation) = result else {
            return XCTFail("expected mutation")
        }
        XCTAssertEqual(mutation.replacement, "~~strike~~")
        let tree = MarkdownParser.parse(mutation.replacement, sourceVersion: 0)
        guard case .success(let t) = tree else { return XCTFail("reparse") }
        XCTAssertTrue(contains(t.root) { if case .strikethrough = $0.kind { return true }; return false })
    }

    // Verifies: REQ-078
    func testTaskTogglePatchesMarker() throws {
        let source = "- [ ] buy milk\n"
        let tree = try XCTUnwrap(MarkdownParser.parse(source, sourceVersion: 1).get())
        let index = MarkdownSourceIndex(source: source, sourceVersion: 1)
        let model = MarkdownProjectionModel.build(tree: tree, index: index)
        let task = try XCTUnwrap(model.attachments.first { if case .task = $0.kind { return true }; return false })
        let snapshot = SourceSnapshot(text: source, sourceVersion: 1, locationGeneration: 0, fileURL: nil)
        let selection = TestSelection(
            mode: .wysiwyg,
            utf16Range: NSRange(location: task.utf16Location, length: 1),
            sourceVersion: 1
        )
        let result = SemanticEditEngine.apply(
            command: .toggleTask(nodeID: task.nodeID),
            selection: selection,
            snapshot: snapshot,
            projection: model,
            tree: tree
        )
        guard case .mutation(let mutation) = result else {
            return XCTFail("expected task toggle mutation, got \(result)")
        }
        XCTAssertTrue(mutation.replacement.contains("[x]") || mutation.replacement.contains("[X]"))
    }

    // Verifies: REQ-087
    func testStaleVersionRefused() {
        let snapshot = SourceSnapshot(text: "abc", sourceVersion: 2, locationGeneration: 0, fileURL: nil)
        let selection = TestSelection(mode: .source, utf16Range: NSRange(location: 0, length: 1), sourceVersion: 1)
        let result = SemanticEditEngine.apply(command: .toggleBold, selection: selection, snapshot: snapshot, projection: nil, tree: nil)
        guard case .refused(.staleVersion) = result else {
            return XCTFail("expected staleVersion")
        }
    }

    // Verifies: REQ-052/086
    @MainActor
    func testModeToggleDoesNotChangeSource() {
        let document = MarkdownDocument()
        document.installTextForTesting("# Hello\n")
        let session = EditorSession()
        session.attach(document: document)
        let before = document.text
        let version = document.sourceVersion
        session.setMode(.source)
        session.setMode(.wysiwyg)
        XCTAssertEqual(document.text, before)
        XCTAssertEqual(document.sourceVersion, version)
        XCTAssertEqual(session.mode, .wysiwyg)
    }

    // Verifies: REQ-083
    @MainActor
    func testUndoAcrossModesRestoresSource() {
        let document = MarkdownDocument()
        document.installTextForTesting("hello")
        let session = EditorSession()
        session.attach(document: document)
        let selection = TestSelection(mode: .source, utf16Range: NSRange(location: 0, length: 5), sourceVersion: document.sourceVersion)
        _ = session.perform(.toggleBold, selection: selection)
        XCTAssertEqual(document.text, "**hello**")
        session.setMode(.wysiwyg)
        document.undoManager?.undo()
        XCTAssertEqual(document.text, "hello")
    }

    private func contains(_ node: MarkdownNode, where predicate: (MarkdownNode) -> Bool) -> Bool {
        if predicate(node) { return true }
        return node.children.contains { contains($0, where: predicate) }
    }
}
