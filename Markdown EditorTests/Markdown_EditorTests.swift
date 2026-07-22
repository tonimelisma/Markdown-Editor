//
//  Markdown_EditorTests.swift
//  Markdown EditorTests
//
//  Created by Toni Melisma on 7/21/26.
//

import Testing
import Foundation
import UniformTypeIdentifiers
@testable import Markdown_Editor

struct Markdown_EditorTests {

    // Verifies: REQ-002
    @Test func newDocumentIsEmpty() {
        #expect(Markdown_EditorDocument().text == "")
    }

    // Verifies: REQ-001
    @Test func readableAndWritableTypesAreMarkdown() {
        #expect(Markdown_EditorDocument.readableContentTypes.map(\.identifier)
            .contains("net.daringfireball.markdown"))
        #expect(Markdown_EditorDocument.writableContentTypes.map(\.identifier)
            .contains("net.daringfireball.markdown"))
    }

    // Verifies: REQ-003, REQ-007
    @Test func roundTripsUTF8ContentUnchanged() throws {
        let original = Data("# Title\n\nBody text with Ünïcödé.\n".utf8)
        let doc = try Markdown_EditorDocument(data: original)
        #expect(doc.text == "# Title\n\nBody text with Ünïcödé.\n")
        #expect(doc.data() == original)
    }

    // Verifies: REQ-007 — line endings preserved, no normalization.
    @Test func preservesCRLFLineEndings() throws {
        let crlf = Data("line one\r\nline two\r\n".utf8)
        let doc = try Markdown_EditorDocument(data: crlf)
        #expect(doc.data() == crlf)
    }

    // Verifies: REQ-004
    @Test func invalidUTF8ThrowsReadError() {
        let invalid = Data([0xFF, 0xFE, 0xFD])
        #expect(throws: CocoaError.self) {
            _ = try Markdown_EditorDocument(data: invalid)
        }
    }
}
