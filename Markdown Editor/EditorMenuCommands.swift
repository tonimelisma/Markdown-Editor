//
//  EditorMenuCommands.swift
//  Markdown Editor
//

import SwiftUI

struct EditorCommandControllerKey: FocusedValueKey {
    typealias Value = EditorCommandController
}

extension FocusedValues {
    var editorCommandController: EditorCommandController? {
        get { self[EditorCommandControllerKey.self] }
        set { self[EditorCommandControllerKey.self] = newValue }
    }
}

@MainActor
struct EditorMenuCommands: Commands {
    static let commandOrder: [EditorCommand] = [
        .bold, .italic, .strikethrough, .inlineCode, .editLink, .removeLink, .paragraph,
        .heading(1), .heading(2), .heading(3), .heading(4), .heading(5), .heading(6),
        .unorderedList, .orderedList, .taskList, .blockQuote, .codeBlock, .addImage
    ]

    @FocusedValue(\.editorCommandController) private var controller

    var body: some Commands {
        CommandMenu("Format") {
            Button("Bold") { _ = controller?.perform(.bold) }
                .keyboardShortcut("b")
                .disabled(!isEnabled(.bold))
            Button("Italic") { _ = controller?.perform(.italic) }
                .keyboardShortcut("i")
                .disabled(!isEnabled(.italic))
            Button("Strikethrough") { _ = controller?.perform(.strikethrough) }
                .disabled(!isEnabled(.strikethrough))
            Button("Inline Code") { _ = controller?.perform(.inlineCode) }
                .disabled(!isEnabled(.inlineCode))
            Button("Edit Link…") { _ = controller?.perform(.editLink) }
                .keyboardShortcut("k")
                .disabled(!isEnabled(.editLink))
            Button("Remove Link") { _ = controller?.perform(.removeLink) }
                .disabled(!isEnabled(.removeLink))
            Divider()
            Button("Paragraph") { _ = controller?.perform(.paragraph) }
                .disabled(!isEnabled(.paragraph))
            ForEach(1...6, id: \.self) { level in
                Button("Heading \(level)") { _ = controller?.perform(.heading(level)) }
                    .disabled(!isEnabled(.heading(level)))
            }
            Divider()
            Button("Bulleted List") { _ = controller?.perform(.unorderedList) }
                .disabled(!isEnabled(.unorderedList))
            Button("Numbered List") { _ = controller?.perform(.orderedList) }
                .disabled(!isEnabled(.orderedList))
            Button("Task List") { _ = controller?.perform(.taskList) }
                .disabled(!isEnabled(.taskList))
            Button("Block Quote") { _ = controller?.perform(.blockQuote) }
                .disabled(!isEnabled(.blockQuote))
            Button("Code Block") { _ = controller?.perform(.codeBlock) }
                .disabled(!isEnabled(.codeBlock))
            Button("Add Image…") { _ = controller?.perform(.addImage) }
                .disabled(!isEnabled(.addImage))
        }
    }

    private func isEnabled(_ command: EditorCommand) -> Bool {
        controller?.availability(for: command).isEnabled ?? false
    }
}
