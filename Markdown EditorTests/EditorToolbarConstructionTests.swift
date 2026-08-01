//
//  EditorToolbarConstructionTests.swift
//  Markdown EditorTests
//

import AppKit
import Testing
@testable import Markdown_Editor

@MainActor
struct EditorToolbarConstructionTests {
    // Verifies: REQ-058/108 — native toolbar items, native overflow, no in-document control row.
    @Test func nativeToolbarUsesUntruncatedWindowItems() {
        let controller = EditorToolbarController()
        let toolbar = NSToolbar(identifier: EditorToolbarController.toolbarIdentifier)
        let allowed = controller.toolbarAllowedItemIdentifiers(toolbar)
        let defaults = controller.toolbarDefaultItemIdentifiers(toolbar)
        #expect(allowed.contains(EditorToolbarController.paragraphIdentifier))
        #expect(allowed.contains(EditorToolbarController.addImageIdentifier))
        #expect(defaults.contains(.flexibleSpace))
        #expect(EditorToolbarController.defaultCommands.contains(.editLink))
        // Every default item is buildable and carries an accessibility-visible label.
        for identifier in defaults where identifier != .flexibleSpace && identifier != .space {
            let item = controller.toolbar(toolbar, itemForItemIdentifier: identifier, willBeInsertedIntoToolbar: true)
            #expect(item != nil, "no item for \(identifier)")
            #expect(!(item?.label.isEmpty ?? true), "\(identifier) has no label")
        }
    }

    // Verifies: REQ-108; ARC-024 — each document window owns its own toolbar and controller, so
    // a command can never reach a different window's document.
    @Test func eachWindowInstallsItsOwnToolbar() {
        let first = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 480), styleMask: [.titled], backing: .buffered, defer: true)
        let second = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 480), styleMask: [.titled], backing: .buffered, defer: true)
        let firstController = EditorToolbarController()
        let secondController = EditorToolbarController()

        firstController.install(on: first)
        secondController.install(on: second)

        #expect(first.toolbar !== second.toolbar)
        #expect(first.toolbar?.delegate === firstController)
        #expect(second.toolbar?.delegate === secondController)

        // Installing again on the same window does not replace a live toolbar.
        let existing = first.toolbar
        firstController.install(on: first)
        #expect(first.toolbar === existing)
    }

    // Verifies: REQ-058 — the formatting row is gone from document content entirely.
    @Test func documentContentContainsNoFormattingControlRow() throws {
        let contentView = try String(
            contentsOf: productionSourceFiles().first { $0.lastPathComponent == "ContentView.swift" }!,
            encoding: .utf8
        )
        #expect(!contentView.contains("EditorToolbar("))
        #expect(!contentView.contains("Button(\"Bold\""))
        // Command surface reaches the window through the toolbar controller, not the content view.
        #expect(contentView.contains("toolbarController.install(on: window)"))
    }
}
