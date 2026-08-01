//
//  MarkdownAST.swift
//  Markdown Editor
//

import Foundation

/// Stable identifier for a node within one parsed tree.
///
/// // REQ-054/085: value AST — no C pointers escape the parser wrapper.
nonisolated struct MarkdownNodeID: Hashable, Sendable, Equatable {
    let rawValue: UInt64
}

nonisolated enum MarkdownListKind: Sendable, Equatable {
    case bullet
    case ordered(start: Int, delimiter: OrderedDelimiter)
}

nonisolated enum OrderedDelimiter: Sendable, Equatable {
    case period
    case paren
}

nonisolated enum MarkdownListMarker: Sendable, Equatable {
    case dash
    case plus
    case asterisk
    case other
}

nonisolated struct MarkdownListInfo: Sendable, Equatable {
    let kind: MarkdownListKind
    let tight: Bool
    let marker: MarkdownListMarker
}

nonisolated enum TableAlignment: Sendable, Equatable {
    case none
    case left
    case center
    case right
}

/// One-based UTF-8 line/byte-column source span from cmark-gfm.
///
/// // REQ-054/055: positions are copied from C nodes immediately.
nonisolated struct SourcePosition: Sendable, Equatable {
    let startLine: Int
    let startColumn: Int
    let endLine: Int
    let endColumn: Int

    static let unknown = SourcePosition(startLine: 0, startColumn: 0, endLine: 0, endColumn: 0)

    var isKnown: Bool { startLine > 0 && endLine > 0 }
}

nonisolated enum MarkdownNodeKind: Sendable, Equatable {
    case document
    case blockQuote
    case list(MarkdownListInfo)
    case item(taskChecked: Bool?)
    case codeBlock(info: String, literal: String, fenced: Bool, fenceChar: Character?, fenceLength: Int)
    case htmlBlock(literal: String)
    case paragraph
    case heading(level: Int)
    case thematicBreak
    case text(String)
    case softBreak
    case lineBreak
    case code(literal: String)
    case htmlInline(literal: String)
    case emphasis
    case strong
    case link(destination: String, title: String)
    case image(destination: String, title: String)
    case strikethrough
    case table(columnCount: Int, alignments: [TableAlignment])
    case tableRow(isHeader: Bool)
    case tableCell
    case unsupported(typeName: String)
}

/// Immutable Swift value node copied from cmark — no C lifetime.
nonisolated struct MarkdownNode: Sendable, Equatable {
    let id: MarkdownNodeID
    let kind: MarkdownNodeKind
    let position: SourcePosition
    let children: [MarkdownNode]
}

/// Complete parse result for one source version.
///
/// // REQ-054: Result&lt;MarkdownTree, MarkdownParseFailure&gt; is the only parser output.
nonisolated struct MarkdownTree: Sendable, Equatable {
    let sourceVersion: UInt64
    let root: MarkdownNode
}

nonisolated enum MarkdownParseFailure: Error, Sendable, Equatable {
    case cancelled
    case allocationFailed
    case extensionUnavailable(String)
    case emptyDocumentNode
}
