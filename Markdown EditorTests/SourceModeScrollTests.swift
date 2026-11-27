//
//  SourceModeScrollTests.swift
//  Markdown EditorTests
//

import AppKit
import Foundation
import Testing
@testable import Markdown_Editor

/// Switching modes shows the part of the document the session says it is showing.
///
/// // Verifies: REQ-086; ARC-Q08 — a mode change restores that mode's own scroll state.
///
/// COR-93: the first switch into Source opened halfway down the file. Session state and the clip
/// view both said the offset was zero, and both were telling the truth: AppKit had parked the
/// Source text view at `frame.origin.y == -1044` inside its clip view — it is laid out while
/// hidden — so a clip-bounds origin of zero meant "1044 points into the document". Session scroll
/// state is now an offset from the top of the document, which is what "zero" was always meant to
/// mean.
@MainActor
struct SourceModeScrollTests {

    /// The placement measured in the running application: an 861-point clip over a 2122-point
    /// document, document view parked at y = -1044.
    private static let observedParkedOrigin: CGFloat = -1044

    private struct Host {
        let document: MarkdownDocument
        let session: EditorSession
        let host: EditorHostView.HostCoordinator
        let root: NSView
        let window: NSWindow
    }

    private static func makeHost() -> Host {
        let document = MarkdownDocument()
        document.installTextForTesting(
            (1...200).map { "Line \($0) of a document taller than any window.\n" }.joined()
        )
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
        // A real window: scroll views in an off-window hierarchy never lay out, and the contract
        // under test is about laid-out geometry.
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        window.contentView = root
        host.buildEditors(in: root)
        return Host(document: document, session: session, host: host, root: root, window: window)
    }

    /// One editor-host update pass, in the order `EditorHostView.updateNSView` performs it.
    private static func hostUpdate(_ h: Host) {
        h.session.withViewReconciliation {
            h.host.refreshVisibleEditor()
            h.host.applyModeIfChanged(h.session.mode)
        }
        h.root.layoutSubtreeIfNeeded()
        if let text = h.host.sourceText, let container = text.textContainer {
            text.layoutManager?.ensureLayout(for: container)
        }
        h.root.layoutSubtreeIfNeeded()
    }

    /// The rect of the document's first line, in the text view's own coordinates.
    private static func firstLineRect(_ text: NSTextView) -> NSRect {
        guard let layoutManager = text.layoutManager, let container = text.textContainer else {
            return .zero
        }
        layoutManager.ensureLayout(for: container)
        let rect = layoutManager.boundingRect(
            forGlyphRange: NSRange(location: 0, length: 1),
            in: container
        )
        let origin = text.textContainerOrigin
        return rect.offsetBy(dx: origin.x, dy: origin.y)
    }

    // The defect, reproduced: with the document view parked where the running application put it,
    // restoring the session's zero offset as a raw clip-bounds origin scrolls 1044 points past
    // the first line. `visibleRect` is AppKit's own answer to "what is on screen", so this asserts
    // what a reader sees rather than restating the implementation.
    // Verifies: REQ-086 — a zero Source offset shows the top of the document.
    @Test func switchingIntoSourceShowsTheTopEvenWhenAppKitParksTheDocumentView() throws {
        let h = Self.makeHost()
        Self.hostUpdate(h)
        let text = try #require(h.host.sourceText)
        text.setFrameOrigin(NSPoint(x: text.frame.origin.x, y: Self.observedParkedOrigin))

        h.session.setMode(.source)
        Self.hostUpdate(h)

        try #require(
            text.frame.origin.y != 0,
            "AppKit reset the parked document origin; this test can no longer see the defect"
        )
        #expect(h.session.sourceModeState.scrollOffset == .zero)
        #expect(
            text.visibleRect.intersects(Self.firstLineRect(text)),
            "Source opened at \(text.visibleRect.origin.y) in the document instead of the top"
        )
    }

    // The same contract in the other direction: what the session records for a real scroll
    // position is what a later switch back into Source puts on screen.
    // Verifies: REQ-086 — a recorded Source scroll position survives a round trip.
    @Test func aRecordedSourceScrollPositionSurvivesARoundTrip() throws {
        let h = Self.makeHost()
        Self.hostUpdate(h)
        h.session.setMode(.source)
        Self.hostUpdate(h)

        let text = try #require(h.host.sourceText)
        let scroll = try #require(h.host.sourceScroll)
        try #require(
            text.frame.height > scroll.contentSize.height,
            "the fixture is not taller than the window; no scroll position can be recorded"
        )
        text.setFrameOrigin(NSPoint(x: text.frame.origin.x, y: Self.observedParkedOrigin))

        // A real user scroll: move the clip, then record it the way the bounds observer does.
        EditorHostView.HostCoordinator.restoreScrollOffset(CGPoint(x: 0, y: 300), in: scroll)
        let recorded = EditorHostView.HostCoordinator.scrollOffset(in: scroll)
        #expect(recorded == CGPoint(x: 0, y: 300))
        let visibleAfterScroll = text.visibleRect

        h.session.updateSourceModeState { $0.scrollOffset = recorded }
        h.session.setMode(.wysiwyg)
        Self.hostUpdate(h)
        h.session.setMode(.source)
        Self.hostUpdate(h)

        #expect(text.visibleRect.origin.y == visibleAfterScroll.origin.y)
    }
}
