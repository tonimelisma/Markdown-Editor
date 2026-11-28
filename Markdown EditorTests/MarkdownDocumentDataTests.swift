//
//  MarkdownDocumentDataTests.swift
//  Markdown EditorTests
//

import Testing
import Foundation
import UniformTypeIdentifiers
@testable import Markdown_Editor

struct MarkdownDocumentDataTests {

    // Validates: REQ-002
    @Test func newDocumentIsEmpty() {
        #expect(MarkdownDocumentData().text == "")
    }

    // Validates: REQ-001 / REQ-015
    @Test func markdownUTTypeIdentifier() {
        #expect(MarkdownContentType.identifier == "net.daringfireball.markdown")
        #expect(MarkdownContentType.utType.identifier == "net.daringfireball.markdown")
    }

    // Validates: REQ-003, REQ-007, REQ-015
    @Test func roundTripsUTF8ContentUnchanged() throws {
        let original = Data("# Title\n\nBody text with Ünïcödé.\n".utf8)
        let doc = try MarkdownDocumentData(data: original)
        #expect(doc.text == "# Title\n\nBody text with Ünïcödé.\n")
        #expect(doc.data() == original)
    }

    // Validates: REQ-007 / REQ-015 — line endings preserved, no normalization.
    @Test func preservesCRLFLineEndings() throws {
        let crlf = Data("line one\r\nline two\r\n".utf8)
        let doc = try MarkdownDocumentData(data: crlf)
        #expect(doc.data() == crlf)
    }

    // Validates: REQ-007 / REQ-015 — a leading UTF-8 BOM is preserved.
    @Test func preservesUTF8BOM() throws {
        let withBOM = Data([0xEF, 0xBB, 0xBF]) + Data("# Title\n".utf8)
        let doc = try MarkdownDocumentData(data: withBOM)
        #expect(doc.data() == withBOM)
    }

    // Validates: REQ-003 / REQ-015 — a 0-byte file reads as empty and round-trips.
    @Test func readsEmptyFile() throws {
        let doc = try MarkdownDocumentData(data: Data())
        #expect(doc.text.isEmpty)
        #expect(doc.data() == Data())
    }

    // Validates: REQ-004 / REQ-015
    @Test func invalidUTF8ThrowsReadError() {
        let invalid = Data([0xFF, 0xFE, 0xFD])
        #expect(throws: CocoaError.self) {
            _ = try MarkdownDocumentData(data: invalid)
        }
    }

    // Validates: REQ-015 — zero-edit and repeated encode stay byte-identical.
    @Test func zeroEditAndRepeatedSnapshotsAreStable() throws {
        let original = Data("hello\r\n世界\n".utf8)
        let first = try MarkdownDocumentData(data: original)
        let second = try MarkdownDocumentData(data: first.data())
        let third = try MarkdownDocumentData(data: second.data())
        #expect(first.data() == original)
        #expect(second.data() == original)
        #expect(third.data() == original)
        #expect(first == second)
        #expect(second == third)
    }
}
