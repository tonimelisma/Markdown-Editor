//
//  EditorCommand.swift
//  Markdown Editor
//

import Foundation

nonisolated enum EditorCommand: Hashable, Sendable, CaseIterable {
    case sourceMode
    case wysiwygMode
    case paragraph
    case heading(Int)
    case bold
    case italic
    case strikethrough
    case inlineCode
    case editLink
    case removeLink
    case unorderedList
    case orderedList
    case taskList
    case blockQuote
    case codeBlock
    case addImage

    static var allCases: [EditorCommand] {
        [.sourceMode, .wysiwygMode, .paragraph] + (1...6).map { .heading($0) } + [
            .bold, .italic, .strikethrough, .inlineCode, .editLink, .removeLink,
            .unorderedList, .orderedList, .taskList, .blockQuote, .codeBlock, .addImage
        ]
    }

    var semanticCommand: SemanticCommand? {
        switch self {
        case .paragraph: return .setParagraph
        case .heading(let level): return .setHeading(level: level)
        case .bold: return .toggleBold
        case .italic: return .toggleItalic
        case .strikethrough: return .toggleStrikethrough
        case .inlineCode: return .toggleInlineCode
        case .removeLink: return .setLink(destination: nil)
        case .unorderedList: return .toggleUnorderedList
        case .orderedList: return .toggleOrderedList
        case .taskList: return .toggleTaskList
        case .blockQuote: return .toggleBlockQuote
        case .codeBlock: return .toggleCodeBlock
        case .sourceMode, .wysiwygMode, .editLink, .addImage: return nil
        }
    }
}
