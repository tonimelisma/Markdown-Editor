//
//  EditorMenuCommandTests.swift
//  Markdown EditorTests
//

import Testing
@testable import Markdown_Editor

@MainActor
struct EditorMenuCommandTests {
    // Verifies: REQ-058/108; ARC-024 — menu and toolbar are two presentations of one command set.
    @Test func menuAndToolbarExposeTheSameSemanticCommandSet() {
        let toolbar = Set(EditorToolbarController.defaultCommands)
        let menu = Set(EditorMenuCommands.commandOrder)
        #expect(toolbar.isSubset(of: menu))
        // Every closed command reaches the menu bar: a toolbar-only command would leave the
        // action unreachable for keyboard-only and accessibility use.
        #expect(menu == Set(EditorCommand.allCases))
        #expect(EditorMenuCommands.commandOrder.count == EditorCommand.allCases.count)
    }

    // Verifies: REQ-058 — approved shortcuts only, and no collision with standard document keys.
    @Test func approvedShortcutsCoverBoldItalicAndLinkOnly() {
        #expect(EditorMenuCommands.shortcuts[.bold] == "b")
        #expect(EditorMenuCommands.shortcuts[.italic] == "i")
        #expect(EditorMenuCommands.shortcuts[.editLink] == "k")
        #expect(EditorMenuCommands.shortcuts.count == 3)
        // Standard macOS document/edit shortcuts stay with AppKit.
        let reserved: Set<Character> = ["n", "o", "s", "p", "w", "z", "x", "c", "v", "a", "f"]
        #expect(Set(EditorMenuCommands.shortcuts.values).isDisjoint(with: reserved))
    }
}
