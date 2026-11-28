//
//  EditorToolbarConstructionTests.swift
//  Markdown EditorTests
//

import AppKit
import Testing
@testable import Markdown_Editor

@MainActor
struct EditorToolbarConstructionTests {
    // Validates: REQ-058, REQ-108 — native toolbar items, native overflow, no in-document control row.
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

    // Validates: REQ-108 — in a window too narrow for the toolbar, every item AppKit moves into the
    // overflow (») menu is there as a menu item that does something. The mode control had no
    // menu form, so a narrow window's overflow menu had no way to switch modes.
    @Test func everyToolbarItemHasAWorkingOverflowForm() {
        let controller = EditorToolbarController()
        let toolbar = NSToolbar(identifier: EditorToolbarController.toolbarIdentifier)
        for identifier in controller.toolbarAllowedItemIdentifiers(toolbar)
        where identifier != .flexibleSpace && identifier != .space {
            let item = controller.toolbar(toolbar, itemForItemIdentifier: identifier, willBeInsertedIntoToolbar: true)
            let form = item?.menuFormRepresentation
            #expect(form != nil, "\(identifier) has no overflow menu form")
            let acts = form?.action != nil || !(form?.submenu?.items.allSatisfy { $0.action == nil } ?? true)
            #expect(acts, "\(identifier)'s overflow menu item does nothing")
        }
    }

    // Validates: REQ-108 — grouped Paragraph/Structure controls expose a real visible toolbar
    // menu; an overflow-only menu representation would silently execute just the default tag.
    @Test func groupedToolbarCommandsUseVisibleMenuItems() {
        let controller = EditorToolbarController()
        let toolbar = NSToolbar(identifier: EditorToolbarController.toolbarIdentifier)
        for identifier in [EditorToolbarController.paragraphIdentifier, EditorToolbarController.structureIdentifier] {
            let item = controller.toolbar(toolbar, itemForItemIdentifier: identifier, willBeInsertedIntoToolbar: true)
            let grouped = item as? NSMenuToolbarItem
            #expect(grouped.map { !$0.menu.items.isEmpty } == true)
        }
    }

    // Validates: REQ-108; ARC-024 — each document window owns its own toolbar and controller, so
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

    // Validates: REQ-108 — the mode control shows the mode the editor is in, after a click on it
    // and after a change from elsewhere (the View menu, its shortcut). The control followed
    // `session.mode` from a `$mode` sink, which runs before the property changes, so every change
    // left the previous mode selected. No test looked at the control after a change; the UI probe
    // of PR #97 (run 45942394078) saw it, pressing Source and capturing Source text under a
    // selected WYSIWYG segment.
    @Test func theModeControlFollowsTheMode() throws {
        let document = MarkdownDocument()
        document.installTextForTesting("Hello.\n")
        let session = EditorSession()
        session.attach(document: document)
        defer { session.detach() }
        let commands = EditorCommandController()
        commands.bind(document: document, session: session, actionRouter: EditorActionRouter(), window: nil)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 480),
            styleMask: [.titled], backing: .buffered, defer: true
        )
        let toolbar = EditorToolbarController()
        toolbar.commandController = commands
        toolbar.install(on: window)
        let item = try #require(
            window.toolbar?.items.first { $0.itemIdentifier == EditorToolbarController.modeIdentifier },
            "the installed toolbar has no mode item"
        )
        let segmented = try #require(item.view as? NSSegmentedControl)
        #expect(segmented.selectedSegment == 0)

        // A click: the control selects the segment, then sends its action.
        segmented.selectedSegment = 1
        segmented.sendAction(segmented.action, to: segmented.target)
        #expect(session.mode == .source, "the click did not change the mode")
        #expect(segmented.selectedSegment == 1, "the control snapped back after a click on Source")

        // A change from outside the control, as the View menu makes.
        _ = commands.perform(.wysiwygMode)
        #expect(session.mode == .wysiwyg)
        #expect(segmented.selectedSegment == 0, "the control kept Source after the menu chose WYSIWYG")
        _ = commands.perform(.sourceMode)
        #expect(segmented.selectedSegment == 1, "the control kept WYSIWYG after the menu chose Source")
    }

    // Validates: REQ-058, REQ-108; COR-28 — every toolbar item the controller vends carries an image.
    //
    // An NSToolbarItem with neither an image nor a view draws as an empty control with a label
    // beneath it, which is exactly how Bold, Italic, and Link rendered in the REQ-104 capture at
    // 88b7bd3. The suite above asserted ownership, identifiers, and labels — never appearance —
    // so a blank button satisfied every existing proof.
    @Test func everyToolbarCommandItemCarriesAnImage() {
        let controller = EditorToolbarController()
        let toolbar = NSToolbar(identifier: EditorToolbarController.toolbarIdentifier)
        for identifier in controller.toolbarAllowedItemIdentifiers(toolbar)
        where identifier != .flexibleSpace && identifier != .space {
            guard let item = controller.toolbar(
                toolbar, itemForItemIdentifier: identifier, willBeInsertedIntoToolbar: true
            ) else {
                Issue.record("no item for \(identifier)")
                continue
            }
            // The mode item is a segmented control, which supplies its own presentation.
            if item.view is NSSegmentedControl { continue }
            #expect(item.image != nil, "\(identifier) renders as a blank button")
            #expect(!item.label.isEmpty, "\(identifier) has no label")
        }
    }

    // Validates: REQ-032, REQ-058; COR-28 — every command resolves to a real SF Symbol on this
    // deployment target, so the fallback path is never silently the shipping one.
    @Test func everyCommandSymbolResolvesOnThisPlatform() {
        for command in EditorCommand.allCases {
            let name = EditorToolbarController.symbolName(for: command)
            #expect(
                NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil,
                "\(command) maps to unavailable symbol \(name)"
            )
        }
    }

    // Validates: REQ-058 — the formatting row is gone from document content entirely.
    @Test func documentContentContainsNoFormattingControlRow() throws {
        let contentView = try String(
            contentsOf: productionSourceFiles().first { $0.lastPathComponent == "ContentView.swift" }!,
            encoding: .utf8
        )
        #expect(!contentView.contains("EditorToolbar("))
        #expect(!contentView.contains("Button(\"Bold\""))
        // That the command surface instead reaches the window through the toolbar controller is
        // proved by `eachWindowInstallsItsOwnToolbar` above, which installs one and inspects the
        // window's real toolbar. Asserting the call's spelling here added nothing.
    }
}
