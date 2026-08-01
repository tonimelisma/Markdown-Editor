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
    /// Every command the menu bar presents. Mode lives in View, formatting in Format, but both
    /// are presentations of the one command model — so this list must cover the toolbar's.
    static let commandOrder: [EditorCommand] = [
        .wysiwygMode, .sourceMode,
        .bold, .italic, .strikethrough, .inlineCode, .editLink, .removeLink, .paragraph,
        .heading(1), .heading(2), .heading(3), .heading(4), .heading(5), .heading(6),
        .unorderedList, .orderedList, .taskList, .blockQuote, .codeBlock, .addImage
    ]

    /// The approved shortcuts. Declared once so menu construction and the conformance test read
    /// the same table, and so an added shortcut cannot silently shadow a standard AppKit key.
    static let shortcuts: [EditorCommand: Character] = [
        .bold: "b",
        .italic: "i",
        .editLink: "k"
    ]

    @FocusedValue(\.editorCommandController) private var controller

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Button("WYSIWYG Mode") { _ = controller?.perform(.wysiwygMode) }
                .disabled(!isEnabled(.wysiwygMode))
            Button("Source Mode") { _ = controller?.perform(.sourceMode) }
                .disabled(!isEnabled(.sourceMode))
            Divider()
        }
        CommandMenu("Format") {
            Button("Bold") { _ = controller?.perform(.bold) }
                .keyboardShortcut(KeyEquivalent(Self.shortcuts[.bold]!))
                .disabled(!isEnabled(.bold))
            Button("Italic") { _ = controller?.perform(.italic) }
                .keyboardShortcut(KeyEquivalent(Self.shortcuts[.italic]!))
                .disabled(!isEnabled(.italic))
            Button("Strikethrough") { _ = controller?.perform(.strikethrough) }
                .disabled(!isEnabled(.strikethrough))
            Button("Inline Code") { _ = controller?.perform(.inlineCode) }
                .disabled(!isEnabled(.inlineCode))
            Button("Edit Link…") { _ = controller?.perform(.editLink) }
                .keyboardShortcut(KeyEquivalent(Self.shortcuts[.editLink]!))
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
