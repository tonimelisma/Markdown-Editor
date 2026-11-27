//
//  SourceModeStylingTests.swift
//  Markdown EditorTests
//

import AppKit
import Foundation
import Testing
@testable import Markdown_Editor

/// Source mode styles every line after the text changed while it was not showing.
///
/// Agent-drive run 45945859891 typed into the first heading in WYSIWYG and switched to Source:
/// every paragraph below was drawn in the heading's font. The host replaces the Source storage
/// with the canonical text, which gives every character the first character's attributes, and
/// the incremental highlighter, still holding its line cache, restyled only the heading line.
@MainActor
struct SourceModeStylingTests {

    private static func font(_ text: NSTextView, at location: Int) -> NSFont? {
        text.textStorage?.attribute(.font, at: location, effectiveRange: nil) as? NSFont
    }

    private static func update(_ host: EditorHostView.HostCoordinator, _ session: EditorSession) {
        session.withViewReconciliation {
            host.refreshVisibleEditor()
            host.applyModeIfChanged(session.mode)
        }
    }

    /// Polls, bounded in main-actor turns, until `done` holds.
    private static func poll(_ done: () -> Bool) async {
        for _ in 0..<400 where !done() {
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    // Verifies: REQ-040 — a body line keeps body type in Source mode after the document changed
    // under it, as an edit in WYSIWYG changes it.
    @Test func everyLineIsRestyledAfterTheTextChangedElsewhere() async throws {
        let document = MarkdownDocument()
        document.installTextForTesting("# Title\n\nBody text.\n")
        let session = EditorSession()
        session.attach(document: document)
        defer { session.detach() }
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
        session.setMode(.source)
        Self.update(host, session)
        let text = try #require(host.sourceText)

        func headingAndBodyDiffer() -> Bool {
            let body = (text.string as NSString).range(of: "Body").location
            guard body != NSNotFound,
                  let heading = Self.font(text, at: 2),
                  let bodyFont = Self.font(text, at: body) else { return false }
            return heading.pointSize > bodyFont.pointSize
        }
        await Self.poll(headingAndBodyDiffer)
        try #require(headingAndBodyDiffer(), "the first highlight never set the heading apart from the body")

        // The canonical text changes while Source is not the editor that changed it.
        document.installTextForTesting("# ATitle\n\nBody text.\n")
        Self.update(host, session)
        try #require(text.string == document.text, "the host did not bring the new text into Source")
        await Self.poll(headingAndBodyDiffer)

        let body = (text.string as NSString).range(of: "Body").location
        #expect(
            headingAndBodyDiffer(),
            "the body line is drawn at \(Self.font(text, at: body)?.pointSize ?? 0) pt, the heading's size"
        )
    }
}
