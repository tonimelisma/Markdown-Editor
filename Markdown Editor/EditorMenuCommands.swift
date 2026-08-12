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
    static let shortcuts: [EditorCommand: KeyboardShortcut] = [
        .sourceMode: KeyboardShortcut("2", modifiers: [.command, .control]),
        .wysiwygMode: KeyboardShortcut("1", modifiers: [.command, .control]),
        .paragraph: KeyboardShortcut("0"),
        .heading(1): KeyboardShortcut("1"),
        .heading(2): KeyboardShortcut("2"),
        .heading(3): KeyboardShortcut("3"),
        .heading(4): KeyboardShortcut("4"),
        .heading(5): KeyboardShortcut("5"),
        .heading(6): KeyboardShortcut("6"),
        .bold: KeyboardShortcut("b"),
        .italic: KeyboardShortcut("i"),
        .strikethrough: KeyboardShortcut("x", modifiers: [.command, .shift]),
        .inlineCode: KeyboardShortcut("c", modifiers: [.command, .control]),
        .editLink: KeyboardShortcut("k"),
        .unorderedList: KeyboardShortcut("7", modifiers: [.command, .shift]),
        .orderedList: KeyboardShortcut("8", modifiers: [.command, .shift]),
        .taskList: KeyboardShortcut("9", modifiers: [.command, .shift]),
        .blockQuote: KeyboardShortcut("q", modifiers: [.command, .control]),
        .codeBlock: KeyboardShortcut("c", modifiers: [.command, .control, .shift])
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
            menuButton("Bold", command: .bold)
            menuButton("Italic", command: .italic)
            Button("Strikethrough") { _ = controller?.perform(.strikethrough) }
                .disabled(!isEnabled(.strikethrough))
            Button("Inline Code") { _ = controller?.perform(.inlineCode) }
                .disabled(!isEnabled(.inlineCode))
            menuButton("Edit Link…", command: .editLink)
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

    @ViewBuilder
    private func menuButton(_ title: String, command: EditorCommand) -> some View {
        let button = Button(title) { _ = controller?.perform(command) }
        if let shortcut = Self.shortcuts[command] {
            button
                .keyboardShortcut(shortcut)
                .disabled(!isEnabled(command))
        } else {
            button.disabled(true)
        }
    }
}
