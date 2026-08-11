//
//  EditorMenuCommandTests.swift
//  Markdown EditorTests
//

import Testing
import SwiftUI
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
    @Test func approvedShortcutsCoverTheClosedCommandSurface() {
        #expect(EditorMenuCommands.shortcuts[.bold]?.key == KeyEquivalent("b"))
        #expect(EditorMenuCommands.shortcuts[.italic]?.key == KeyEquivalent("i"))
        #expect(EditorMenuCommands.shortcuts[.editLink]?.key == KeyEquivalent("k"))
        #expect(EditorMenuCommands.shortcuts[.heading(6)]?.key == KeyEquivalent("6"))
        #expect(EditorMenuCommands.shortcuts.count == 19)
        #expect(EditorMenuCommands.shortcuts[.strikethrough]?.modifiers.contains(.shift) == true)
        #expect(EditorMenuCommands.shortcuts[.codeBlock]?.modifiers.contains(.control) == true)
    }
}
