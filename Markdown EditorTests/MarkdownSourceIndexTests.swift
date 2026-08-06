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

    // Verifies: REQ-055/078; ARC-007 — cmark reports a node whose content ends at a line boundary
    // as (next line, column 0). That maps to the previous line's content end and **not one byte
    // further**: the mapped span must stop after the item's own terminator, not absorb the blank
    // line that follows it.
    //
    // Rehearsed failing: with `column == 0` returning `lineStart` instead of `lineStart - 1`, the
    // caller's shared inclusive→exclusive `+ 1` produced "- [ ] Task\n\n". The task toggle still
    // worked, so only an exact-span assertion catches it.
    func testEndColumnZeroStopsAtThePreviousLineTerminator() throws {
        let source = "- [ ] Task\n\nTrailing paragraph.\n"
        let index = MarkdownSourceIndex(source: source, sourceVersion: 1)
        let tree = try XCTUnwrap(MarkdownParser.parse(source, sourceVersion: 1).get())
        let item = try XCTUnwrap(
            first(tree.root, where: { if case .item = $0.kind { return true }; return false }),
            "fixture produced no list item"
        )
        // Precondition: this fixture really does exercise the end-column-0 convention.
        XCTAssertEqual(item.position.endColumn, 0, "fixture no longer reproduces end_column == 0")

        let slice = try XCTUnwrap(index.substring(position: item.position).get())
        XCTAssertEqual(slice, "- [ ] Task\n")

        // The same convention under CRLF keeps the whole two-byte terminator and no more.
        let crlf = "- [ ] Task\r\n\r\nTrailing paragraph.\r\n"
        let crlfIndex = MarkdownSourceIndex(source: crlf, sourceVersion: 1)
        let crlfTree = try XCTUnwrap(MarkdownParser.parse(crlf, sourceVersion: 1).get())
        let crlfItem = try XCTUnwrap(
            first(crlfTree.root, where: { if case .item = $0.kind { return true }; return false })
        )
        if crlfItem.position.endColumn == 0 {
            let crlfSlice = try XCTUnwrap(crlfIndex.substring(position: crlfItem.position).get())
            XCTAssertEqual(crlfSlice, "- [ ] Task\r\n")
        }
    }

    private func first(_ node: MarkdownNode, where predicate: (MarkdownNode) -> Bool) -> MarkdownNode? {
        if predicate(node) { return node }
        for child in node.children {
            if let found = first(child, where: predicate) { return found }
        }
        return nil
    }
}
