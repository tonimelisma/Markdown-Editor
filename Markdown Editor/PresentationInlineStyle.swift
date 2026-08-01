//
//  PresentationInlineStyle.swift
//  Markdown Editor
//

import Foundation

/// AppKit-free inline meaning used by the attributed presentation builder.
nonisolated enum PresentationInlineStyle: Sendable, Equatable {
    case body
    case heading(level: Int)
    case emphasis
    case strong
    case strikethrough
    case inlineCode
    case link
    case blockQuote
    case literalHTML
}
