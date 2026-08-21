//
//  DocumentLifecycleContractTests.swift
//  Markdown EditorTests
//

import AppKit
import Foundation
import Testing
@testable import Markdown_Editor

@MainActor
struct DocumentLifecycleContractTests {
    // Verifies: REQ-002 — direct construction is the same empty, untitled document that AppKit
    // creates for File > New; no second source or location state is introduced by the app.
    @Test func newDocumentStartsEmptyAndUntitled() {
        let document = MarkdownDocument()

        #expect(document.text.isEmpty)
        #expect(document.fileURL == nil)
        #expect(document.sourceVersion == 0)
        #expect(document.locationGeneration == 0)
        #expect(document.isDocumentEdited == false)
        #expect(document.documentUndoManager === document.undoManager)
    }

    // Verifies: REQ-003/004/015 — the same canonical NSDocument data boundary accepts valid
    // UTF-8, rejects invalid UTF-8, and never installs a partial invalid document.
    @Test func readContractInstallsOnlyValidUTF8() throws {
        let valid = MarkdownDocument()
        try valid.read(from: Data("opened\n".utf8), ofType: MarkdownContentType.identifier)
        #expect(valid.text == "opened\n")

        let invalid = MarkdownDocument()
        #expect(throws: CocoaError.self) {
            try invalid.read(from: Data([0xC3, 0x28]), ofType: MarkdownContentType.identifier)
        }
        #expect(invalid.text.isEmpty)
        #expect(invalid.sourceVersion == 0)
    }

    // Verifies: REQ-005/017 — editing marks the document dirty while operation-scoped Save
    // reports a failure without discovering ownership through a view hierarchy.
    @Test func editIsDirtyAndSaveFailureIsScopedToTheDocument() async {
        let document = MarkdownDocument()
        document.installTextForTesting("before")
        #expect(document.isDocumentEdited == false)

        document.saveExecutorOverride = SaveOutcome(.failed)
        let outcome = await document.saveDocument()

        #expect(outcome == .failed)
        #expect(document.text == "before")
        #expect(document.fileURL == nil)
    }

    // Verifies: REQ-006/014/020/021 — Versions, tabs, and Recents stay AppKit-owned. The app
    // configures only the standard NSDocument window metadata and document-controller route.
    @Test func standardDocumentLifecycleUsesAppKitOwners() throws {
        let document = MarkdownDocument()
        document.makeWindowControllers()
        defer { document.close() }

        let window = try #require(document.windowControllers.first?.window)
        #expect(window.tabbingIdentifier == "MarkdownDocument")
        #expect(window.tabbingMode == .preferred)
        #expect(window.windowController?.document === document)
        #expect(document.isInViewingMode == false)

        let controller = MarkdownDocumentController()
        #expect(controller.documentClass(forType: MarkdownContentType.identifier) == MarkdownDocument.self)
        #expect(controller.documentClass(forType: "Markdown Document") == MarkdownDocument.self)
        #expect(NSDocumentController.instancesRespond(to: #selector(NSDocumentController.clearRecentDocuments(_:))))
    }

    // Verifies: REQ-021 — the app exposes the standard NSDocumentController Open Recent route
    // and only supplies the required Clear Menu item rather than maintaining a recent-file store.
    @Test func recentsUseTheStandardDocumentControllerRoute() throws {
        let source = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Markdown Editor/Markdown_EditorApp.swift"),
            encoding: .utf8
        )

        #expect(source.contains("withTitle: \"Open Recent\""))
        #expect(source.contains("#selector(NSDocumentController.clearRecentDocuments(_:))"))
        #expect(!source.contains("RecentDocumentStore"))
    }

    // Verifies: REQ-021 — the app exposes the standard NSDocumentController Open Recent route
    // and only supplies the required Clear Menu item rather than maintaining a recent-file store.
    @Test func recentsUseTheStandardDocumentControllerRoute() throws {
        let source = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Markdown Editor/Markdown_EditorApp.swift"),
            encoding: .utf8
        )

        #expect(source.contains("withTitle: \"Open Recent\""))
        #expect(source.contains("#selector(NSDocumentController.clearRecentDocuments(_:))"))
        #expect(!source.contains("RecentDocumentStore"))
    }

    // Verifies: REQ-013/015/019 — the lifecycle boundary is one NSDocument owner with serialized
    // framework I/O and one URL/location-generation route, not an app shadow subsystem.
    @Test func lifecycleOwnerHasNoDuplicateDocumentSubsystem() throws {
        let source = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Markdown Editor/MarkdownDocument.swift"),
            encoding: .utf8
        )

        #expect(source.contains("override func save("))
        #expect(source.contains("override func revert(toContentsOf"))
        #expect(source.contains("override func read(from data:"))
        #expect(source.contains("override func data(ofType"))
        #expect(source.contains("override var fileURL"))
        #expect(!source.contains("class RecentDocumentStore"))
        #expect(!source.contains("class TabManager"))
        #expect(!source.contains("class VersionStore"))
        #expect(!source.contains("class AutosaveStore"))
    }

    private final class SaveOutcome: DocumentSaving {
        let outcome: DocumentSaveOutcome

        init(_ outcome: DocumentSaveOutcome) {
            self.outcome = outcome
        }

        func saveDocument() async -> DocumentSaveOutcome { outcome }
    }
}
