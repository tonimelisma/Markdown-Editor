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

    // Verifies: REQ-005/017 — a real canonical edit marks the document dirty, while
    // operation-scoped Save reports a failure without discovering ownership through a view.
    @Test func editIsDirtyAndSaveFailureIsScopedToTheDocument() async throws {
        let document = MarkdownDocument()
        document.installTextForTesting("before")
        #expect(document.isDocumentEdited == false)

        let snapshot = document.sourceSnapshot()
        let mutation = try #require(SourceMutation.exact(
            snapshot: snapshot,
            range: NSRange(location: 6, length: 0),
            replacement: "!",
            selectionBefore: SourceSelection(utf16: NSRange(location: 6, length: 0)),
            actionName: "Lifecycle edit",
            grouping: .discrete
        ))
        let commit = document.commitEditorInput(
            .sourceReplacement(EditorReplacementInput(
                mutation: mutation,
                selectionIdentity: .source(mutation.selectionBefore)
            )),
            state: EditorStateSnapshot(
                source: snapshot,
                sourceSelection: mutation.selectionBefore
            )
        )
        if case .committed = commit {
            // Expected liveness path.
        } else {
            Issue.record("canonical lifecycle edit was refused")
        }
        #expect(document.text == "before!")
        #expect(document.isDocumentEdited == true)

        document.saveExecutorOverride = SaveOutcome(.failed)
        let outcome = await document.saveDocument()

        #expect(outcome == .failed)
        #expect(document.text == "before!")
        #expect(document.fileURL == nil)
    }

    // Verifies: REQ-006/014/020 — Versions/revert and tabs stay AppKit-owned. The app configures
    // only the standard NSDocument window metadata and document-controller route.
    @Test func standardDocumentLifecycleUsesAppKitOwners() throws {
        let document = MarkdownDocument()
        document.makeWindowControllers()
        defer { document.close() }

        let window = try #require(document.windowControllers.first?.window)
        #expect(window.tabbingIdentifier == "MarkdownDocument")
        #expect(window.tabbingMode == .preferred)
        #expect(window.windowController?.document === document)
        #expect(document.isInViewingMode == false)

        let savedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cor74-revert-\\(UUID().uuidString).md")
        defer { try? FileManager.default.removeItem(at: savedURL) }
        try Data("saved\n".utf8).write(to: savedURL)
        document.installTextForTesting("edited\n")
        try document.revert(toContentsOf: savedURL, ofType: MarkdownContentType.identifier)
        #expect(document.text == "saved\n")

        let second = MarkdownDocument()
        second.makeWindowControllers()
        defer { second.close() }
        let secondWindow = try #require(second.windowControllers.first?.window)
        window.addTabbedWindow(secondWindow, ordered: .above)
        #expect(window.tabbedWindows?.contains(secondWindow) == true)

        let controller = MarkdownDocumentController()
        #expect(controller.documentClass(forType: MarkdownContentType.identifier) == MarkdownDocument.self)
        #expect(controller.documentClass(forType: "Markdown Document") == MarkdownDocument.self)
        #expect(NSDocumentController.instancesRespond(to: #selector(NSDocumentController.clearRecentDocuments(_:))))
    }

    // Verifies: REQ-002/014 — the standard New route creates and registers an empty Markdown
    // document without a custom document factory or view-owned source.
    @Test func newRouteCreatesEmptyDocument() throws {
        let controller = MarkdownDocumentController()
        let document = try #require(controller.openUntitledDocumentAndDisplay(false) as? MarkdownDocument)
        defer { document.close() }

        #expect(document.text.isEmpty)
        #expect(document.fileURL == nil)
        #expect(controller.documents.contains { $0 === document })
    }

    // Verifies: REQ-021 — the standard NSDocumentController route records a recently opened
    // document, while the app only supplies the required Clear Menu item.
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

        let originalMenu = NSApp.mainMenu
        defer { NSApp.mainMenu = originalMenu }
        let menu = NSMenu(title: "Main")
        let fileMenu = NSMenu(title: "File")
        menu.addItem(withTitle: "File", action: nil, keyEquivalent: "").submenu = fileMenu
        NSApp.mainMenu = menu
        let appDelegate = MarkdownAppDelegate()
        appDelegate.ensureOpenRecentMenuItem()
        let openRecent = fileMenu.item(withTitle: "Open Recent")
        #expect(openRecent?.submenu?.item(withTitle: "Clear Menu") != nil)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cor74-recent-(UUID().uuidString).md")
        try Data().write(to: url)
        let defaults = UserDefaults.standard
        let previousRecentLimit = defaults.object(forKey: "NSRecentDocumentsLimit")
        defaults.set(10, forKey: "NSRecentDocumentsLimit")
        let controller = MarkdownDocumentController()
        controller.noteNewRecentDocumentURL(url)
        defer {
            controller.clearRecentDocuments(nil)
            if let previousRecentLimit {
                defaults.set(previousRecentLimit, forKey: "NSRecentDocumentsLimit")
            } else {
                defaults.removeObject(forKey: "NSRecentDocumentsLimit")
            }
            try? FileManager.default.removeItem(at: url)
        }
        let canonicalPath = url.path.hasPrefix("/private/") ? url.path : "/private\(url.path)"
        #expect(controller.maximumRecentDocumentCount > 0)
        #expect(controller.recentDocumentURLs.contains { $0.path == canonicalPath })
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

        let allProduction = try productionSourceText()
        #expect(source.contains("override func save("))
        #expect(source.contains("override func revert(toContentsOf"))
        #expect(source.contains("override func read(from data:"))
        #expect(source.contains("override func data(ofType"))
        #expect(source.contains("override var fileURL"))
        #expect(allProduction.components(separatedBy: "@Published private(set) var text").count - 1 == 1)
        #expect(allProduction.components(separatedBy: "@Published private(set) var sourceVersion").count - 1 == 1)
        #expect(allProduction.components(separatedBy: "@Published private(set) var locationGeneration").count - 1 == 1)
        #expect(source.components(separatedBy: "var documentUndoManager").count - 1 == 1)
        #expect(allProduction.components(separatedBy: "final class MarkdownDocument: NSDocument").count - 1 == 1)
        #expect(allProduction.range(of: #"\b(?:class|struct|actor|enum)\s+\w*(?:DocumentStore|DocumentManager|SourceStore|RevisionStore|UndoStore|TabManager|VersionStore|AutosaveStore)\b"#, options: .regularExpression) == nil)
    }

    private final class SaveOutcome: DocumentSaving {
        let outcome: DocumentSaveOutcome

        init(_ outcome: DocumentSaveOutcome) {
            self.outcome = outcome
        }

        func saveDocument() async -> DocumentSaveOutcome { outcome }
    }
}
