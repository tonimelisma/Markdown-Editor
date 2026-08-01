//
//  EditorToolbarConstructionTests.swift
//  Markdown EditorTests
//

import AppKit
import Testing
@testable import Markdown_Editor

@MainActor
struct EditorToolbarConstructionTests {
    @Test func nativeToolbarUsesUntruncatedWindowItems() {
        let controller = EditorToolbarController()
        let toolbar = NSToolbar(identifier: EditorToolbarController.toolbarIdentifier)
        let allowed = controller.toolbarAllowedItemIdentifiers(toolbar)
        let defaults = controller.toolbarDefaultItemIdentifiers(toolbar)
        #expect(allowed.contains(EditorToolbarController.paragraphIdentifier))
        #expect(allowed.contains(EditorToolbarController.addImageIdentifier))
        #expect(defaults.contains(.flexibleSpace))
        #expect(EditorToolbarController.defaultCommands.contains(.editLink))
    }
}
