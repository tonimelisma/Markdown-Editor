//
//  NewWindowReadinessTests.swift
//  Markdown EditorTests
//

import AppKit
import Foundation
import Testing
@testable import Markdown_Editor

/// A new window is ready to type in, as TextEdit's is. The agent-drive tour (45955987611) opened
/// the app with a plain launch and typed: nothing arrived, because no editor had keyboard focus,
/// and the formatting shortcuts it then pressed were refused as `ambiguousSelection`, because an
/// untouched caret had never been reported to the session.
@MainActor
struct NewWindowReadinessTests {

    private struct Host {
        let document: MarkdownDocument
        let session: EditorSession
        let host: EditorHostView.HostCoordinator
        let window: NSWindow
        let commands: EditorCommandController
    }

    private static func makeHost(text: String) -> Host {
        let document = MarkdownDocument()
        document.installTextForTesting(text)
        let session = EditorSession()
        session.attach(document: document)
        let placement = ImagePlacementController()
        placement.attach(actions: document)
        let router = EditorActionRouter()
        router.document = document
        router.placement = placement
        let host = EditorHostView.HostCoordinator(
            document: document,
            session: session,
            placementController: placement,
            actionRouter: router
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        window.contentView = root
        host.buildEditors(in: root)
        host.applyMode(session.mode, focus: false)
        let commands = EditorCommandController()
        commands.bind(document: document, session: session, actionRouter: router, window: window)
        return Host(document: document, session: session, host: host, window: window, commands: commands)
    }

    private static func poll(_ done: () -> Bool) async {
        for _ in 0..<400 where !done() {
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    // Validates: REQ-002/REQ-032 — a new window's page has keyboard focus.
    @Test func aNewWindowsPageHasKeyboardFocus() throws {
        let h = Self.makeHost(text: "")
        defer { h.session.detach() }
        h.host.focusVisibleEditorIfUnfocused()
        let page = try #require(h.host.wysiwygText)
        #expect(h.window.firstResponder === page, "the new window's first responder is \(String(describing: h.window.firstResponder))")
        #expect(h.window.initialFirstResponder === page)
    }

    // Validates: REQ-084 — closing the find bar gives the keyboard back to the page it searched.
    // Closed with Done it left no first responder, and the next keys went nowhere.
    @Test func closingTheFindBarReturnsTheKeyboardToThePage() throws {
        let h = Self.makeHost(text: "Milk and Eggs\n")
        defer { h.session.detach() }
        let scroll = try #require(h.host.wysiwygScroll)
        let page = try #require(h.host.wysiwygText)
        scroll.isFindBarVisible = true
        h.window.makeFirstResponder(nil)
        try #require(h.window.firstResponder === h.window, "the keyboard was not put nowhere")
        scroll.isFindBarVisible = false
        #expect(h.window.firstResponder === page, "the keyboard is with \(String(describing: h.window.firstResponder))")
    }

    // Validates: REQ-086 — the editor of the mode not shown never takes the keyboard. AppKit gave
    // it to the hidden Source page when the find bar closed, and keys went to a caret nobody saw.
    @Test func theHiddenEditorDeclinesTheKeyboard() throws {
        let h = Self.makeHost(text: "Milk and Eggs\n")
        defer { h.session.detach() }
        let hidden = try #require(h.host.sourceText)
        try #require(hidden.isHiddenOrHasHiddenAncestor, "the Source page is not hidden in WYSIWYG mode")
        // What matters is who holds the keyboard afterwards, not makeFirstResponder's return,
        // which reported success though the view declined (CI 45979591545).
        _ = h.window.makeFirstResponder(hidden)
        #expect(h.window.firstResponder !== hidden, "the hidden Source page took the keyboard")
    }

    // Validates: REQ-058/REQ-032 — the first command in a new window applies at the caret the page
    // shows. The caret had never moved, so no selection callback reported it, and the command was
    // refused.
    @Test func theFirstCommandInANewWindowApplies() async throws {
        let h = Self.makeHost(text: "Hello.\n")
        defer { h.session.detach() }
        await Self.poll { h.session.presentation != nil }
        try #require(h.session.presentation != nil, "the opening parse never landed")
        h.session.withViewReconciliation { h.host.refreshVisibleEditor() }
        h.host.focusVisibleEditorIfUnfocused()
        await Self.poll { h.session.wysiwygModeState.selection != nil }

        let selection = try #require(h.session.wysiwygModeState.selection, "the focused page's caret is not the session's")
        #expect(selection.range.utf16 == NSRange(location: 0, length: 0))
        let result = h.commands.perform(.heading(1))
        #expect(result == .accepted, "the first command was \(result)")
        #expect(h.document.text.hasPrefix("# Hello."), "the document reads \(h.document.text.debugDescription)")
    }
}
