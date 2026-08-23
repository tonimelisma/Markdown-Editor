//
//  UndoActionNameTests.swift
//  Markdown EditorTests
//

import Foundation
import Testing
@testable import Markdown_Editor

/// The undo vocabulary is closed, unique, and shared by both editors.
///
/// // Verifies: REQ-011; ARC-028 — Source mode and WYSIWYG mode plan edits through separate
/// domains, and the same operation must read the same way in the Edit menu from either. Before
/// COR-92 these were literals at nineteen sites across seven files, with `"Delete"` alone
/// appearing four times; nothing tied the two domains' copies together.
struct UndoActionNameTests {

    /// Two operations sharing a title would make "Undo Delete" ambiguous about what it undoes.
    @Test func everyActionNameIsUniqueAndPresentable() {
        let titles = UndoActionName.allCases.map(\.title)
        #expect(!titles.isEmpty)
        // Compiler-guaranteed, not test-guaranteed: Swift rejects duplicate raw values, so a
        // mutation introducing one fails to build rather than reddening here. Kept because it
        // states the intent for a reader, and would become load-bearing if `title` ever stopped
        // being the raw value. Falsification confirmed the distinction.
        #expect(Set(titles).count == titles.count, "two undo actions share a title")
        for title in titles {
            #expect(!title.isEmpty)
            // AppKit composes "Undo " + title, so a lowercase or padded title reads wrong in the
            // menu. This is the kind of drift nineteen scattered literals invited.
            #expect(title == title.trimmingCharacters(in: .whitespaces), "\(title) is padded")
            #expect(title.first?.isUppercase == true, "\(title) does not start with a capital")
        }
    }

    /// Every semantic formatting command's undo name is in the vocabulary, so no command can
    /// register an edit the Edit menu cannot describe.
    @Test func everySemanticCommandNameIsInTheVocabulary() {
        // `SemanticCommand` carries associated values and is not Hashable, so this lists the
        // names rather than keying a dictionary by command. A new command that needs a new name
        // fails to compile against this enum until it adds one.
        let semantic: [UndoActionName] = [
            .bold, .italic, .strikethrough, .inlineCode,
            .paragraph, .heading, .quote, .codeBlock,
            .unorderedList, .orderedList, .taskList, .toggleTask,
            .link, .removeLink, .editCell,
        ]
        for name in semantic {
            #expect(UndoActionName.allCases.contains(name), "\(name) is not in the vocabulary")
        }
        // Nothing in the vocabulary is orphaned: every case is either a semantic command name or
        // one of the primitive edits below.
        let primitives: [UndoActionName] = [.typing, .delete, .paste, .insertImage]
        let accounted = Set(semantic + primitives)
        #expect(
            accounted == Set(UndoActionName.allCases),
            "unaccounted undo names: \(Set(UndoActionName.allCases).subtracting(accounted))"
        )
    }

    /// The primitive edits both editors share.
    @Test func bothEditorsShareThePrimitiveEditNames() {
        #expect(UndoActionName.typing.title == "Typing")
        #expect(UndoActionName.delete.title == "Delete")
        #expect(UndoActionName.paste.title == "Paste")
        #expect(UndoActionName.insertImage.title == "Insert Image")
    }
}
