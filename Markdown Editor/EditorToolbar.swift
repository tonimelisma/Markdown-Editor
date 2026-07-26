//
//  EditorToolbar.swift
//  Markdown Editor
//

import AppKit
import SwiftUI

/// Shared formatting toolbar for Source and WYSIWYG.
///
/// // REQ-058/082: same commands in both modes; Add Image… via COR-02.
struct EditorToolbar: View {
    @ObservedObject var document: MarkdownDocument
    @ObservedObject var session: EditorSession

    var body: some View {
        HStack(spacing: 8) {
            Picker("Mode", selection: modeBinding) {
                Text("WYSIWYG").tag(EditorMode.wysiwyg)
                Text("Source").tag(EditorMode.source)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 200)

            Divider().frame(height: 18)

            Menu("Paragraph") {
                Button("Paragraph") { run(.setParagraph) }
                ForEach(1...6, id: \.self) { level in
                    Button("Heading \(level)") { run(.setHeading(level: level)) }
                }
            }

            Button("B") { run(.toggleBold) }.fontWeight(.bold).help("Bold")
            Button("I") { run(.toggleItalic) }.italic().help("Italic")
            Button("S") { run(.toggleStrikethrough) }.help("Strikethrough")
            Button("`</>`") { run(.toggleInlineCode) }.help("Inline Code")
            Button("Link") { promptLink() }.help("Link")

            Divider().frame(height: 18)

            Button("• List") { run(.toggleUnorderedList) }
            Button("1. List") { run(.toggleOrderedList) }
            Button("☑ Task") { run(.toggleTaskList) }
            Button("Quote") { run(.toggleBlockQuote) }
            Button("Code") { run(.toggleCodeBlock) }

            Spacer()

            Button("Add Image…") {
                Task { await session.addImages() }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private var modeBinding: Binding<EditorMode> {
        Binding(
            get: { session.mode },
            set: { session.setMode($0) }
        )
    }

    private func currentSelection() -> EditorSelection {
        // REQ-052/058: mode-local typed selection; offset zero is valid.
        switch session.mode {
        case .source:
            return .source(session.sourceModeState.selection)
        case .wysiwyg:
            if let selection = session.wysiwygModeState.selection {
                return .projection(selection)
            }
            // No current presentation selection — empty projection caret if editable.
            if let presentation = session.presentation,
               case .editable(let id) = session.wysiwygModeState.availability,
               id == presentation.id {
                return .projection(
                    ProjectionSelection(
                        utf16: NSRange(location: 0, length: 0),
                        revision: presentation.projectionRevision
                    )
                )
            }
            return .source(session.sourceModeState.selection)
        }
    }

    private func run(_ command: SemanticCommand) {
        _ = session.perform(
            command,
            selection: currentSelection(),
            expectedSourceRevision: SourceRevision(value: document.sourceVersion)
        )
    }

    private func promptLink() {
        let alert = NSAlert()
        alert.messageText = "Add Link"
        alert.informativeText = "Enter a URL. Leave empty to remove a Markdown link around the selection."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        alert.accessoryView = field
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }
        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        run(.setLink(destination: value.isEmpty ? nil : value))
    }
}
