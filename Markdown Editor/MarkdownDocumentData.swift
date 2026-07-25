//
//  MarkdownDocumentData.swift
//  Markdown Editor
//

import Foundation
import UniformTypeIdentifiers

/// Canonical Markdown UTI used for document open/save.
///
/// Prefer this helper over `UTType.markdown` — newer SDKs also declare that name and make
/// a same-named extension ambiguous.
enum MarkdownContentType {
    static let identifier = "net.daringfireball.markdown"

    nonisolated static var utType: UTType {
        UTType(importedAs: identifier)
    }
}

/// Pure byte contract for Markdown documents — isolated from AppKit lifecycle.
///
/// // REQ-015: UTF-8 / empty / BOM / CRLF / Unicode / invalid-UTF-8 / zero-edit fidelity.
nonisolated struct MarkdownDocumentData: Sendable, Equatable {
    var text: String

    // REQ-002: a new document starts empty.
    init(text: String = "") {
        self.text = text
    }

    // REQ-004: invalid UTF-8 is a read error, never silent corruption.
    // REQ-007 / INV-2: `String(validating:as:)` preserves a leading BOM (which
    // `String(data:encoding:)` would silently strip) while still rejecting invalid UTF-8.
    init(data: Data) throws {
        guard let string = String(validating: data, as: UTF8.self) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.text = string
    }

    // REQ-007: encode as UTF-8; unedited content round-trips byte-for-byte.
    func data() -> Data {
        Data(text.utf8)
    }
}
