//
//  FormalGFMDialect.swift
//  Markdown Editor
//

import Foundation
import cmark_gfm

/// The one production declaration of the MVP Markdown dialect.
///
/// // REQ-047/054: the pinned formal GFM 0.29-gfm contract is closed. Adding an extension or
/// parser option requires a fixture and requirements update rather than a silent parser change.
nonisolated enum FormalGFMDialect {
    static let name = "formal-gfm-0.29-gfm"
    static let pinnedRevision = "5d9bdaa4228b381639fff09403e39a04926e2dbe"
    static let enabledExtensions = ["table", "tasklist", "strikethrough", "autolink", "tagfilter"]
    static let unsupportedWritingExtensions = ["footnotes", "highlight", "superscript", "subscript"]
    static let parserOptions = Int32(CMARK_OPT_STRIKETHROUGH_DOUBLE_TILDE)

    static func accepts(extensions: [String]) -> Bool {
        let allowed = Set(enabledExtensions)
        return extensions.allSatisfy { allowed.contains($0) }
    }

    static func preservesUnsupportedLinkLiteral(source: String, destination: String) -> Bool {
        let footnoteLike = source.hasPrefix("[^") && (source.hasSuffix("]") || source.hasSuffix("]()"))
        return destination.isEmpty && footnoteLike
    }
}
