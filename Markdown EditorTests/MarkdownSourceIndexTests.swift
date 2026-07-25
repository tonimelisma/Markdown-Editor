//
//  MarkdownSourceIndexTests.swift
//  Markdown EditorTests
//

import XCTest
@testable import Markdown_Editor

final class MarkdownSourceIndexTests: XCTestCase {
    // Verifies: REQ-055
    func testASCIIAndEmojiMappings() throws {
        let source = "# Hi 🇺🇸 café\n**bold**"
        let index = MarkdownSourceIndex(source: source, sourceVersion: 1)
        let tree = try XCTUnwrap(MarkdownParser.parse(source, sourceVersion: 1).get())
        guard let heading = first(tree.root, where: { if case .heading = $0.kind { return true }; return false }) else {
            return XCTFail("missing heading")
        }
        let slice = try XCTUnwrap(index.substring(position: heading.position).get())
        XCTAssertTrue(slice.contains("Hi"))
        let utf16 = try XCTUnwrap(index.utf16Range(for: heading.position).get())
        XCTAssertEqual((source as NSString).substring(with: utf16), slice)
    }

    // Verifies: REQ-055/087
    func testOutOfBoundsProducesTypedFailure() {
        let index = MarkdownSourceIndex(source: "abc", sourceVersion: 0)
        let result = index.utf8Offset(line: 99, column: 1)
        guard case .failure(.outOfBoundsLine) = result else {
            return XCTFail("expected outOfBoundsLine, got \(result)")
        }
    }

    // Verifies: REQ-055
    func testCRLFAndBOM() throws {
        let source = "\u{FEFF}line1\r\nline2"
        let index = MarkdownSourceIndex(source: source, sourceVersion: 0)
        XCTAssertGreaterThanOrEqual(index.lineCount, 2)
        let off = try XCTUnwrap(index.utf8Offset(line: 2, column: 1).get())
        XCTAssertGreaterThan(off, 0)
    }

    private func first(_ node: MarkdownNode, where predicate: (MarkdownNode) -> Bool) -> MarkdownNode? {
        if predicate(node) { return node }
        for child in node.children {
            if let found = first(child, where: predicate) { return found }
        }
        return nil
    }
}
