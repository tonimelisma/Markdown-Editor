//
//  EditorCommandControllerTests.swift
//  Markdown EditorTests
//

import AppKit
import Foundation
import Testing
import XCTest
@testable import Markdown_Editor

@MainActor
struct EditorCommandControllerTests {
    // Verifies: REQ-108; ARC-024 — one closed identifier per semantic command.
    @Test func everySemanticCommandHasOneClosedIdentifier() {
        #expect(Set(EditorCommand.allCases).count == EditorCommand.allCases.count)
        #expect(EditorCommand.allCases.contains(.addImage))
        #expect(EditorCommand.allCases.contains(.heading(6)))
    }

    @Test func disabledCommandDoesNotMutateDetachedController() {
        let controller = EditorCommandController()
        #expect(controller.availability(for: .bold) == .disabled(.noDocument))
        #expect(controller.perform(.bold) == .disabled(.noDocument))
    }

    // Verifies: REQ-058/108 — a formatting command routes through the bound window's own
    // document and session, and never reaches another window's document.
    @Test func controllerRoutesFormattingThroughBoundWindowSession() {
        let first = Fixture(text: "hello\n")
        first.selectSource(NSRange(location: 0, length: 5))
        #expect(first.controller.perform(.bold) == .accepted)
        #expect(first.document.text == "**hello**\n")

        let second = Fixture(text: "other\n")
        second.selectSource(NSRange(location: 0, length: 5))
        #expect(second.controller.perform(.italic) == .accepted)
        // The first document is untouched by the second window's command.
        #expect(first.document.text == "**hello**\n")
        #expect(second.document.text == "*other*\n")
        #expect(first.controller.document !== second.controller.document)

        first.tearDown()
        second.tearDown()
    }

    // Verifies: REQ-058 — WYSIWYG without a current presentation refuses rather than guessing.
    @Test func formattingIsDisabledWhileWYSIWYGHasNoCurrentPresentation() {
        let fixture = Fixture(text: "hello\n")
        fixture.session.setMode(.wysiwyg)
        #expect(fixture.session.presentation == nil)
        #expect(fixture.controller.availability(for: .bold) == .disabled(.unavailablePresentation))
        // Invoking it anyway must not mutate source.
        #expect(fixture.controller.perform(.bold) == .disabled(.unavailablePresentation))
        #expect(fixture.document.text == "hello\n")
        #expect(fixture.document.sourceVersion == 0)
        fixture.tearDown()
    }

    // Verifies: REQ-082/108 — Add Image is not advertised while WYSIWYG lacks the exact
    // source-domain insertion target that `EditorSession.addImages()` requires.
    @Test func addImageIsDisabledWhileWYSIWYGHasNoCurrentPresentation() {
        let fixture = Fixture(text: "hello\n")
        #expect(fixture.controller.availability(for: .addImage) == .enabled)
        fixture.session.setMode(.wysiwyg)
        #expect(fixture.session.presentation == nil)
        #expect(fixture.controller.availability(for: .addImage) == .disabled(.unavailablePresentation))
        #expect(fixture.controller.perform(.addImage) == .disabled(.unavailablePresentation))
        fixture.tearDown()
    }

    // Verifies: REQ-058 — link editing needs a real selection to describe.
    @Test func linkEditingIsDisabledWithoutASelection() {
        let fixture = Fixture(text: "hello\n")
        fixture.selectSource(NSRange(location: 0, length: 0))
        #expect(fixture.controller.availability(for: .editLink) == .disabled(.noSelection))
        #expect(!fixture.controller.linkSheetPresented)
        fixture.tearDown()
    }

    // Verifies: REQ-108 — sheet commit, removal, and cancel are exact and window-scoped.
    @Test func linkSheetCommitRemoveAndCancelAreWindowScoped() {
        let fixture = Fixture(text: "hello\n")
        fixture.selectSource(NSRange(location: 0, length: 5))
        #expect(fixture.controller.perform(.editLink) == .started)
        #expect(fixture.controller.linkSheetPresented)
        fixture.controller.updateLinkDestination("https://example.com")
        fixture.controller.commitLink(destination: fixture.controller.linkDestination)
        #expect(fixture.document.text == "[hello](https://example.com)\n")
        #expect(!fixture.controller.linkSheetPresented)

        // A partial selection is ambiguous, so removal refuses rather than guessing a boundary.
        fixture.selectSource(NSRange(location: 1, length: 5))
        fixture.controller.commitLink(destination: "   ")
        #expect(fixture.document.text == "[hello](https://example.com)\n")

        // An empty destination over the exact link removes it rather than writing an empty one.
        fixture.selectSource(NSRange(location: 0, length: 28))
        fixture.controller.commitLink(destination: "   ")
        #expect(fixture.document.text == "hello\n")

        // Cancel on a second window changes nothing at all.
        let other = Fixture(text: "world\n")
        other.selectSource(NSRange(location: 0, length: 5))
        #expect(other.controller.perform(.editLink) == .started)
        other.controller.cancelLink()
        #expect(!other.controller.linkSheetPresented)
        #expect(other.document.text == "world\n")
        #expect(other.document.sourceVersion == 0)

        fixture.tearDown()
        other.tearDown()
    }

    // Verifies: REQ-108 — a detached session disables every command and dismisses its sheet.
    @Test func detachDisablesEveryCommandAndClosesTheSheet() {
        let fixture = Fixture(text: "hello\n")
        fixture.selectSource(NSRange(location: 0, length: 5))
        #expect(fixture.controller.perform(.editLink) == .started)
        fixture.session.detach()
        fixture.controller.cancelLink()
        #expect(!fixture.controller.linkSheetPresented)
        for command in EditorCommand.allCases where command.semanticCommand != nil {
            #expect(fixture.controller.perform(command) != .accepted, "\(command) mutated after detach")
        }
        #expect(fixture.document.text == "hello\n")
    }

    /// One document, session, router, and controller — the same objects a single window owns.
    @MainActor
    private final class Fixture {
        let document = MarkdownDocument()
        let session = EditorSession()
        let router = EditorActionRouter()
        let controller = EditorCommandController()

        init(text: String) {
            document.installTextForTesting(text)
            session.attach(document: document)
            // Source mode is the deterministic starting point: WYSIWYG availability depends on
            // an asynchronous authoritative parse that a synchronous test must not race.
            session.setMode(.source)
            controller.bind(document: document, session: session, actionRouter: router, window: nil)
        }

        func selectSource(_ range: NSRange) {
            session.updateSourceModeState { $0.selection = SourceSelection(utf16: range) }
        }

        func tearDown() {
            session.detach()
        }
    }
}

@MainActor
final class WYSIWYGListCommandRegressionTests: XCTestCase {
    // Verifies: REQ-058/057/087; ARC-005/007/009 — a current WYSIWYG paragraph selection
    // reaches the list planner through the same window command controller without a guessed map.
    func testUnorderedListAcceptsOrdinaryParagraphSelection() throws {
        let document = MarkdownDocument()
        document.installTextForTesting("First paragraph.\n\nSecond paragraph.\n")
        let session = EditorSession()
        session.attach(document: document)
        session.setMode(.wysiwyg)
        defer { session.detach() }

        let tree = try XCTUnwrap(MarkdownParser.parse(document.text, sourceVersion: document.sourceVersion).get())
        let model = MarkdownProjectionModel.build(
            tree: tree,
            index: MarkdownSourceIndex(source: document.text, sourceVersion: document.sourceVersion)
        )
        session.installProjectionForTesting(model, tree: tree)
        let presentation = try XCTUnwrap(session.presentation)
        session.updateWYSIWYGModeState {
            $0.selection = ProjectionSelection(
                utf16: NSRange(location: 0, length: 16),
                revision: presentation.projectionRevision
            )
        }
        let classification = ProjectionSelectionClassifier.classify(
            selection: NSRange(location: 0, length: 16),
            affinity: .downstream,
            snapshot: presentation
        )
        XCTAssertEqual(classification, .identityText(sourceRange: NSRange(location: 0, length: 16)))

        let controller = EditorCommandController()
        controller.bind(
            document: document,
            session: session,
            actionRouter: EditorActionRouter(),
            window: nil
        )

        XCTAssertEqual(controller.perform(.unorderedList), .accepted)
        XCTAssertEqual(document.text, "- First paragraph.\n\nSecond paragraph.\n")
        let restored = try XCTUnwrap(session.wysiwygModeState.selection)
        XCTAssertEqual(restored.range.utf16.length, 0)
        XCTAssertEqual(restored.range.revision.snapshotID, session.presentation?.id)
    }
}
