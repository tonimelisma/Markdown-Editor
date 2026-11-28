//
//  EditorMenuCommandTests.swift
//  Markdown EditorTests
//

import AppKit
import Testing
import SwiftUI
@testable import Markdown_Editor

@MainActor
struct EditorMenuCommandTests {
    // Validates: REQ-058, REQ-108; ARC-024 — menu and toolbar are two presentations of one command set.
    @Test func menuAndToolbarExposeTheSameSemanticCommandSet() {
        let toolbar = Set(EditorToolbarController.defaultCommands)
        let menu = Set(EditorMenuCommands.commandOrder)
        #expect(toolbar.isSubset(of: menu))
        // Every closed command reaches the menu bar: a toolbar-only command would leave the
        // action unreachable for keyboard-only and accessibility use.
        #expect(menu == Set(EditorCommand.allCases))
        #expect(EditorMenuCommands.commandOrder.count == EditorCommand.allCases.count)
    }

    // Validates: REQ-058 — approved shortcuts only, and no collision with standard document keys.
    @Test func approvedShortcutsCoverTheClosedCommandSurface() {
        #expect(EditorMenuCommands.shortcuts[.bold]?.key == KeyEquivalent("b"))
        #expect(EditorMenuCommands.shortcuts[.italic]?.key == KeyEquivalent("i"))
        #expect(EditorMenuCommands.shortcuts[.editLink]?.key == KeyEquivalent("k"))
        #expect(EditorMenuCommands.shortcuts[.heading(6)]?.key == KeyEquivalent("6"))
        #expect(EditorMenuCommands.shortcuts.count == 19)
        #expect(EditorMenuCommands.shortcuts[.strikethrough]?.modifiers.contains(.shift) == true)
        #expect(EditorMenuCommands.shortcuts[.codeBlock]?.modifiers.contains(.control) == true)
    }

    // Validates: REQ-058, REQ-108; ARC-024 — the menu bar reaches the commands of the key document
    // window. Document windows are AppKit windows, and the `@FocusedValue` the menu read never
    // reached it from them: agent-drive run 45944610103 found "WYSIWYG Mode" disabled with the View
    // menu open, and cmd-I did nothing. The menu now reads the key window's controller through
    // the toolbar delegate that window owns.
    @Test func theMenuReachesTheKeyDocumentWindowsCommands() {
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

        #expect(KeyWindowCommands.controller(of: window) === commands)
        #expect(KeyWindowCommands.controller(of: nil) == nil)
        let registry = KeyWindowCommands(observingKeyWindow: false)
        registry.refresh(keyWindow: window)
        #expect(registry.controller === commands, "the key document window's commands were not published")
        #expect(registry.enabled.contains(.sourceMode))
        registry.refresh(keyWindow: nil)
        #expect(registry.controller == nil, "a window that is no longer key kept the menu bar")
        #expect(registry.enabled.isEmpty)
    }

    // Validates: REQ-058, REQ-108 — the menu's availability follows the key window's state after the
    // menu was built. Formatting is unavailable in WYSIWYG before the first parse lands, and the
    // menu decided `.disabled` once, at the window's set-up: cmd-I was refused for good
    // (agent-drive run 45945859891). Leaving WYSIWYG for Source makes formatting available.
    @Test func theMenuFollowsAvailabilityAfterItWasBuilt() async {
        let document = MarkdownDocument()
        document.installTextForTesting("Hello.\n")
        let session = EditorSession()
        session.attach(document: document)
        defer { session.detach() }
        session.setMode(.wysiwyg)
        session.presentation = nil
        let commands = EditorCommandController()
        commands.bind(document: document, session: session, actionRouter: EditorActionRouter(), window: nil)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 480),
            styleMask: [.titled], backing: .buffered, defer: true
        )
        let toolbar = EditorToolbarController()
        toolbar.commandController = commands
        toolbar.install(on: window)
        let registry = KeyWindowCommands(observingKeyWindow: false)
        registry.refresh(keyWindow: window)
        #expect(!registry.enabled.contains(.italic), "italic was available with no presentation in WYSIWYG")

        session.setMode(.source)
        for _ in 0..<50 where !registry.enabled.contains(.italic) {
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(5))
        }
        #expect(registry.enabled.contains(.italic), "the menu kept italic disabled after it became available")
    }
}
