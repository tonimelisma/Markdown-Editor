//
//  PresentationAttachment.swift
//  Markdown Editor
//

import Foundation

nonisolated enum PresentationDecorationKind: Sendable, Equatable {
    case blockQuoteRule
    case codeBlockBackground
    case thematicSeparator
}

nonisolated struct PresentationDecoration: Sendable, Equatable {
    let range: NSRange
    let kind: PresentationDecorationKind
}
