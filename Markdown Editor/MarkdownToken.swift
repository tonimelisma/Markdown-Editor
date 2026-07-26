//
//  MarkdownToken.swift
//  Markdown Editor
//

import Foundation

// REQ-041/043/047: the kinds of CommonMark/formal-GFM source elements the highlighter
// styles. Lexical presentation aid only — not a conforming parser.
// `nonisolated` + `Sendable` so tokens cross the MarkdownHighlighter actor boundary
// cleanly under the project's default-main-actor isolation.
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
}

// A styled source range. Value type; crosses the actor boundary.
nonisolated struct Token: Sendable, Hashable {
    let range: NSRange
    let style: TokenStyle
}
