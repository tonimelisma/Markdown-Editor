//
//  UndoActionName.swift
//  Markdown Editor
//

import Foundation

/// The user-visible name of an undoable operation, as it appears in "Undo …" and "Redo …".
///
/// // REQ-011; ARC-028. These are strings macOS shows in the Edit menu, and before COR-92 they
/// // were literals spread across six files: `"Delete"` at four sites, `"Insert Image"` at four,
/// // `"Typing"` at three, and the semantic names one each. Source mode and WYSIWYG mode plan
/// // edits through separate domains that must nonetheless agree — the same keystroke has to read
/// // "Undo Typing" in both — and nothing tied the two sets of literals together.
///
/// A closed set so a new undoable operation must name itself here, where a reader can see the
/// whole vocabulary at once and `UndoActionNameTests` can prove it is unique and non-empty.
nonisolated enum UndoActionName: String, CaseIterable, Sendable {
    // Primitive text edits. Shared by both editors.
    case typing = "Typing"
    case delete = "Delete"
    case paste = "Paste"

    // Inline formatting.
    case bold = "Bold"
    case italic = "Italic"
    case strikethrough = "Strikethrough"
    case inlineCode = "Inline Code"
    case link = "Link"
    case removeLink = "Remove Link"

    // Block structure.
    case paragraph = "Paragraph"
    case heading = "Heading"
    case quote = "Quote"
    case codeBlock = "Code Block"
    case unorderedList = "Unordered List"
    case orderedList = "Ordered List"
    case taskList = "Task List"
    case toggleTask = "Toggle Task"

    // Tables and images.
    case editCell = "Edit Cell"
    case insertImage = "Insert Image"

    /// The string handed to `UndoManager.setActionName(_:)`.
    var title: String { rawValue }
}
