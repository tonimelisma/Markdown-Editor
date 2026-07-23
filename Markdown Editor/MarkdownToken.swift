//
//  MarkdownToken.swift
//  Markdown Editor
//

import Foundation

// REQ-041/042/043: the kinds of Markdown source elements the highlighter styles.
// `nonisolated` + `Sendable` so tokens cross the MarkdownHighlighter actor boundary
// cleanly under the project's default-MainActor isolation (ADR-0010).
nonisolated enum TokenStyle: Sendable, Hashable {
    case heading(level: Int)
    case bold
    case italic
    case inlineCode
    case codeBlock
    case link
    case image
    case listMarker
    case taskMarker
    case blockquote
    case table
    case strikethrough
    case thematicBreak
    case footnote
    case highlight
    case superscript
    case subscriptStyle
}

// A styled source range. Value type; crosses the actor boundary.
nonisolated struct Token: Sendable, Hashable {
    let range: NSRange
    let style: TokenStyle
}
