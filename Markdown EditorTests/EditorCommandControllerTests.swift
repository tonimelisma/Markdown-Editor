//
//  EditorCommandControllerTests.swift
//  Markdown EditorTests
//

import Foundation
import Testing
@testable import Markdown_Editor

@MainActor
struct EditorCommandControllerTests {
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

    @Test func controllerRoutesFormattingThroughBoundWindowSession() {
        let firstDocument = MarkdownDocument()
        firstDocument.installTextForTesting("hello\n")
        let firstSession = EditorSession()
        firstSession.attach(document: firstDocument)
        firstSession.updateSourceModeState { $0.selection = SourceSelection(utf16: NSRange(location: 0, length: 5)) }
        let first = EditorCommandController()
        let firstRouter = EditorActionRouter()
        first.bind(document: firstDocument, session: firstSession, actionRouter: firstRouter, window: nil)
        #expect(first.perform(.bold) == .accepted)
        #expect(firstDocument.text.contains("**hello**"))

        let secondDocument = MarkdownDocument()
        secondDocument.installTextForTesting("other\n")
        let secondSession = EditorSession()
        secondSession.attach(document: secondDocument)
        let second = EditorCommandController()
        let secondRouter = EditorActionRouter()
        second.bind(document: secondDocument, session: secondSession, actionRouter: secondRouter, window: nil)
        #expect(second.document === secondDocument)
        #expect(first.document !== second.document)
        firstSession.detach()
        secondSession.detach()
    }

    @Test func linkSheetCancelAndCommitAreWindowScoped() {
        let document = MarkdownDocument()
        document.installTextForTesting("hello\n")
        let session = EditorSession()
        session.attach(document: document)
        session.updateSourceModeState { $0.selection = SourceSelection(utf16: NSRange(location: 0, length: 5)) }
        let controller = EditorCommandController()
        controller.bind(document: document, session: session, actionRouter: EditorActionRouter(), window: nil)
        #expect(controller.perform(.editLink) == .started)
        #expect(controller.linkSheetPresented)
        controller.updateLinkDestination("https://example.com")
        controller.commitLink(destination: controller.linkDestination)
        #expect(document.text == "[hello](https://example.com)\n")

        let untouchedDocument = MarkdownDocument()
        untouchedDocument.installTextForTesting("world\n")
        let untouchedSession = EditorSession()
        untouchedSession.attach(document: untouchedDocument)
        untouchedSession.updateSourceModeState { $0.selection = SourceSelection(utf16: NSRange(location: 0, length: 5)) }
        let untouchedController = EditorCommandController()
        untouchedController.bind(
            document: untouchedDocument,
            session: untouchedSession,
            actionRouter: EditorActionRouter(),
            window: nil
        )
        #expect(untouchedController.perform(.editLink) == .started)
        untouchedController.cancelLink()
        #expect(!untouchedController.linkSheetPresented)
        #expect(untouchedDocument.text == "world\n")
        session.detach()
        untouchedSession.detach()
    }
}
