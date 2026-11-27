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

        let sourceVersionBeforeSave = document.sourceVersion
        let locationGenerationBeforeSave = document.locationGeneration
        let canUndoBeforeSave = document.undoManager?.canUndo == true
        document.saveExecutorOverride = SaveOutcome(.failed)
        let outcome = await document.saveDocument()

        #expect(outcome == .failed)
        #expect(document.text == "before!")
        #expect(document.fileURL == nil)
        #expect(document.sourceVersion == sourceVersionBeforeSave)
        #expect(document.locationGeneration == locationGenerationBeforeSave)
        #expect(document.undoManager?.canUndo == canUndoBeforeSave)

        document.saveExecutorOverride = SaveOutcome(.cancelled)
        let cancelled = await document.saveDocument()

        #expect(cancelled == .cancelled)
        #expect(document.text == "before!")
        #expect(document.sourceVersion == sourceVersionBeforeSave)
        #expect(document.locationGeneration == locationGenerationBeforeSave)
        #expect(document.undoManager?.canUndo == canUndoBeforeSave)
    }

    // Verifies: REQ-005 — a canonical edit hands off to NSDocument's autosave contract and
    // completes without a custom timer or shadow persistence service.
    @Test func autosaveHandoffCompletesAfterCanonicalEdit() async throws {
        let document = MarkdownDocument()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cor74-autosave-" + UUID().uuidString + ".md")
        var autosavedURLToRemove: URL?
        defer {
            if let autosavedURLToRemove {
                try? FileManager.default.removeItem(at: autosavedURLToRemove)
            }
            try? FileManager.default.removeItem(at: url)
        }
        try Data("before".utf8).write(to: url)
        document.fileURL = url
        document.installTextForTesting("before")
        let snapshot = document.sourceSnapshot()
        let mutation = try #require(SourceMutation.exact(
            snapshot: snapshot,
            range: NSRange(location: 6, length: 0),
            replacement: "!",
            selectionBefore: SourceSelection(utf16: NSRange(location: 6, length: 0)),
            actionName: "Autosave edit",
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
        guard case .committed = commit else {
            Issue.record("canonical autosave edit was refused")
            return
        }

        #expect(document.hasUnautosavedChanges == true)
        let error = await withCheckedContinuation { continuation in
            document.autosave(withImplicitCancellability: true) { error in
                continuation.resume(returning: error)
            }
        }

        #expect(error == nil)
        #expect(document.hasUnautosavedChanges == false)
        let autosavedURL = document.autosavedContentsFileURL
        #expect(autosavedURL != nil)
        if let autosavedURL {
            autosavedURLToRemove = autosavedURL
            #expect(String(data: try Data(contentsOf: autosavedURL), encoding: .utf8) == "before!")
        }
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
            .appendingPathComponent("cor74-revert-" + UUID().uuidString + ".md")
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
    // Verifies: REQ-014 — an untitled duplicate resolves its `assets/` images beside the
    // document it was copied from. The copy has no file of its own, so every image in it showed
    // as missing (tour 45979207044, File › Duplicate).
    @Test func aDuplicateResolvesImagesBesideItsOriginal() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("original.md")
        try Data("![a](assets/a.png)\n".utf8).write(to: url)
        let original: MarkdownDocument = try await withCheckedThrowingContinuation { continuation in
            NSDocumentController.shared.openDocument(withContentsOf: url, display: false) { document, _, error in
                if let document = document as? MarkdownDocument {
                    continuation.resume(returning: document)
                } else {
                    continuation.resume(throwing: error ?? CocoaError(.fileReadUnknown))
                }
            }
        }
        defer { original.close() }
        let copy = try #require(try original.duplicate() as? MarkdownDocument)
        defer { copy.close() }
        #expect(copy.fileURL == nil, "the duplicate is untitled")
        #expect(copy.text == original.text)
        #expect(
            copy.imageBaseURL?.standardizedFileURL == url.standardizedFileURL,
            "the duplicate resolves images against \(String(describing: copy.imageBaseURL))"
        )
    }

    // Verifies: REQ-014 — where relative images resolve: a past version beside the document it
    // is a version of, though its own file is in the version store (the Versions browser showed
    // its images as missing, tour 45980851977); a file beside itself; an untitled duplicate
    // beside its original until it is saved.
    @Test func imagesResolveBesideTheDocumentAVersionBelongsTo() {
        let browsed = URL(fileURLWithPath: "/Notes/notes.md")
        let store = URL(fileURLWithPath: "/.DocumentRevisions-V100/PerUID/501/1/com.apple.documentVersions/A.md")
        let original = URL(fileURLWithPath: "/Notes/original.md")
        #expect(MarkdownDocument.imageBase(versionOf: browsed, fileURL: store, duplicateOrigin: nil) == browsed)
        #expect(MarkdownDocument.imageBase(versionOf: nil, fileURL: browsed, duplicateOrigin: nil) == browsed)
        #expect(MarkdownDocument.imageBase(versionOf: nil, fileURL: nil, duplicateOrigin: original) == original)
        // A duplicate saved somewhere of its own resolves there.
        #expect(MarkdownDocument.imageBase(versionOf: nil, fileURL: browsed, duplicateOrigin: original) == browsed)
    }

    @Test func newRouteCreatesEmptyDocument() throws {
        let controller = MarkdownDocumentController()
        let document = try #require(controller.openUntitledDocumentAndDisplay(false) as? MarkdownDocument)
        defer { document.close() }

        #expect(document.text.isEmpty)
        #expect(document.fileURL == nil)
        #expect(controller.documents.contains { $0 === document })
    }

    // Verifies: REQ-021 — the standard NSDocumentController route records a recently opened
    // document, and File › Open Recent lists what it records.
    @Test func recentsUseTheStandardDocumentControllerRoute() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cor74-recent-" + UUID().uuidString + ".md")
        try Data().write(to: url)
        let defaults = UserDefaults.standard
        let previousRecentLimit = defaults.object(forKey: "NSRecentDocumentsLimit")
        defaults.set(10, forKey: "NSRecentDocumentsLimit")
        let controller = NSDocumentController.shared
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
        // AppKit documents recentDocumentURLs as the URLs currently represented by Open Recent;
        // use that public menu contract rather than depending on private dynamic submenu items.
        #expect(controller.recentDocumentURLs.contains { $0.path == canonicalPath })
        // Open Recent lists the controller's record, updated as each document is noted: the
        // shared controller is the app's, which refreshes the list in noteNewRecentDocumentURL.
        #expect(controller is MarkdownDocumentController, "the shared controller is \(type(of: controller))")
        #expect(RecentDocuments.shared.urls.contains { $0.path == canonicalPath })
    }

    // Verifies: REQ-013/015/019 — the lifecycle boundary is one NSDocument owner with serialized
    // framework I/O and one URL/location-generation route, not an app shadow subsystem.
    @Test func lifecycleOwnerHasNoDuplicateDocumentSubsystem() throws {
        // Uniqueness and absence only. The five `override func` presence assertions this test
        // used to carry are covered behaviourally elsewhere — `documentControllerOpenAndSaveRoundTrip`
        // and `readRejectsInvalidUTF8` call those overrides, and
        // `requiredDocumentFileSelectorsAreDeclared` proves the document responds to the File
        // selectors. Asserting their spelling here proved nothing and reddened on reformatting.
        let allProduction = try productionSourceText()
        // The detector proves itself: an empty or unreadable corpus would make every count below
        // trivially zero and every `== 1` assertion fail loudly rather than silently pass — but a
        // regex that stopped matching would not, so anchor on something certainly present.
        #expect(allProduction.contains("final class MarkdownDocument"), "production source unreadable")
        #expect(allProduction.components(separatedBy: "@Published private(set) var text").count - 1 == 1)
        #expect(allProduction.components(separatedBy: "@Published private(set) var sourceVersion").count - 1 == 1)
        #expect(allProduction.components(separatedBy: "@Published private(set) var locationGeneration").count - 1 == 1)
        // Scoped to the document, not to all production: `DocumentActionInterface` declares the
        // protocol requirement and `MarkdownDocument` implements it, so the whole-production count
        // is legitimately two. The claim is that there is one *implementation*.
        let documentSource = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Markdown Editor/MarkdownDocument.swift"),
            encoding: .utf8
        )
        #expect(documentSource.components(separatedBy: "var documentUndoManager").count - 1 == 1)
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
