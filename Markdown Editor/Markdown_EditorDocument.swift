//
//  Markdown_EditorDocument.swift
//  Markdown Editor
//
//  Created by Toni Melisma on 7/21/26.
//

import SwiftUI
import UniformTypeIdentifiers

// REQ-001: documents are UTF-8 plain-text Markdown (.md / .markdown). The type is
// already declared by the system (net.daringfireball.markdown) and conforms to plain text.
extension UTType {
    static var markdown: UTType { UTType(importedAs: "net.daringfireball.markdown") }
}

nonisolated struct Markdown_EditorDocument: FileDocument {
    var text: String

    // REQ-002: a new document starts empty.
    init(text: String = "") {
        self.text = text
    }

    // REQ-001: read and write Markdown files only.
    static let readableContentTypes: [UTType] = [.markdown]
    static let writableContentTypes: [UTType] = [.markdown]

    // Testable seam: decode/encode the raw file bytes independently of SwiftUI's
    // Read/WriteConfiguration, so the document's behavior can be unit-tested directly.

    // REQ-004: invalid UTF-8 is a read error, never silent corruption.
    init(data: Data) throws {
        guard let string = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.text = string
    }

    // REQ-007: encode as UTF-8; unedited content round-trips byte-for-byte, so existing
    // line endings are preserved and nothing is normalized on save.
    func data() -> Data {
        Data(text.utf8)
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        try self.init(data: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data())
    }
}
