//
//  PresentationBlock.swift
//  Markdown Editor
//

import Foundation

/// AppKit-free block semantics carried by an immutable projection snapshot.
///
/// // REQ-105–107; ARC-018: layout decisions are derived from block meaning, not from a
/// delimiter-shaped string scan on the main actor.
nonisolated enum PresentationBlockKind: Sendable, Equatable {
    case paragraph
    case heading(level: Int)
    case listItem(kind: MarkdownListKind, nesting: Int, task: Bool)
    case blockQuote(depth: Int)
    case codeBlock(languageHintPresent: Bool)
    case table
    case tableRow(header: Bool)
    case tableCell(alignment: TableAlignment, header: Bool)
    case thematicBreak
    case image
    case literalHTML
}

nonisolated struct PresentationBlock: Sendable, Equatable {
    let nodeID: MarkdownNodeID
    let projectionRange: NSRange
    let sourceRange: NSRange?
    let kind: PresentationBlockKind
}
