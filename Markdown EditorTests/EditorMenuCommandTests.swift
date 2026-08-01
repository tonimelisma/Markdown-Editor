//
//  EditorMenuCommandTests.swift
//  Markdown EditorTests
//

import Testing
@testable import Markdown_Editor

@MainActor
struct EditorMenuCommandTests {
    @Test func menuAndToolbarExposeTheSameSemanticCommandSet() {
        let toolbar = Set(EditorToolbarController.defaultCommands)
        let menu = Set(EditorMenuCommands.commandOrder)
        #expect(toolbar.isSubset(of: menu))
        #expect(menu.contains(.bold))
        #expect(menu.contains(.italic))
        #expect(menu.contains(.editLink))
        #expect(menu.contains(.addImage))
    }
}
