//
//  LinkEditorSheetTests.swift
//  Markdown EditorTests
//

import AppKit
import SwiftUI
import Testing
@testable import Markdown_Editor

@MainActor
struct LinkEditorSheetTests {
    /// The sheet is a pure presentation of controller state: it owns no destination of its own,
    /// so a dismissal can never leave a half-applied edit behind.
    // Verifies: REQ-108
    @Test func sheetEditsControllerStateAndCommitsThroughTheCommandRoute() {
        let fixture = SheetFixture()
        #expect(fixture.controller.perform(.editLink) == .started)

        var committed = false
        var cancelled = false
        let sheet = LinkEditorSheet(
            destination: fixture.destinationBinding,
            onCommit: {
                committed = true
                fixture.controller.commitLink(destination: fixture.controller.linkDestination)
            },
            onCancel: {
                cancelled = true
                fixture.controller.cancelLink()
            }
        )

        // Typing into the field writes through to the controller, not to a private copy.
        sheet.destination = "https://example.com"
        #expect(fixture.controller.linkDestination == "https://example.com")

        sheet.onCommit()
        #expect(committed)
        #expect(!cancelled)
        #expect(fixture.document.text == "[hello](https://example.com)\n")
        #expect(!fixture.controller.linkSheetPresented)
        fixture.session.detach()
    }

    // Verifies: REQ-108 — cancel is inert; it must not reach the document at all.
    @Test func cancelLeavesSourceAndRevisionUnchanged() {
        let fixture = SheetFixture()
        #expect(fixture.controller.perform(.editLink) == .started)
        let sheet = LinkEditorSheet(
            destination: fixture.destinationBinding,
            onCommit: { fixture.controller.commitLink(destination: fixture.controller.linkDestination) },
            onCancel: { fixture.controller.cancelLink() }
        )
        sheet.destination = "https://example.com"
        sheet.onCancel()

        #expect(!fixture.controller.linkSheetPresented)
        #expect(fixture.document.text == "hello\n")
        #expect(fixture.document.sourceVersion == 0)
        fixture.session.detach()
    }

    @MainActor
    private final class SheetFixture {
        let document = MarkdownDocument()
        let session = EditorSession()
        let controller = EditorCommandController()

        init() {
            document.installTextForTesting("hello\n")
            session.attach(document: document)
            session.setMode(.source)
            session.updateSourceModeState { $0.selection = SourceSelection(utf16: NSRange(location: 0, length: 5)) }
            controller.bind(
                document: document,
                session: session,
                actionRouter: EditorActionRouter(),
                window: nil
            )
        }

        var destinationBinding: Binding<String> {
            Binding(
                get: { [controller] in controller.linkDestination },
                set: { [controller] in controller.updateLinkDestination($0) }
            )
        }
    }
}
