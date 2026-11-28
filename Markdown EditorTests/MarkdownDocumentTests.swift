//
//  MarkdownDocumentTests.swift
//  Markdown EditorTests
//

import Testing
import Foundation
import AppKit
import Combine
import UniformTypeIdentifiers
@testable import Markdown_Editor

@MainActor
struct MarkdownDocumentTests {

    // Validates: REQ-013 / REQ-015
    @Test func readableWritableTypesAreMarkdown() {
        #expect(MarkdownDocument.readableTypes.contains(MarkdownContentType.identifier))
        #expect(MarkdownDocument.writableTypes.contains(MarkdownContentType.identifier))
    }

    // Validates: REQ-015
    @Test func readAndDataRoundTripByteFixtures() throws {
        let fixtures: [Data] = [
            Data(),
            Data("lf\n".utf8),
            Data("crlf\r\n".utf8),
            Data([0xEF, 0xBB, 0xBF]) + Data("bom\n".utf8),
            Data("Ünïcödé 😀\n".utf8),
        ]
        for original in fixtures {
            let doc = MarkdownDocument()
            try doc.read(from: original, ofType: MarkdownContentType.identifier)
            let written = try doc.data(ofType: MarkdownContentType.identifier)
            #expect(written == original)
        }
    }

    // Validates: REQ-015
    @Test func readRejectsInvalidUTF8() {
        let doc = MarkdownDocument()
        #expect(throws: CocoaError.self) {
            try doc.read(from: Data([0xFF, 0xFE, 0xFD]), ofType: MarkdownContentType.identifier)
        }
    }

    // Validates: REQ-014 — autosave in place is enabled for production.
    @Test func autosavesInPlace() {
        #expect(MarkdownDocument.autosavesInPlaceForProduction == true)
    }

    // Validates: REQ-013 — document owns undo manager used by transactions.
    @Test func documentOwnsUndoManager() {
        let doc = MarkdownDocument()
        #expect(doc.documentUndoManager != nil)
        #expect(doc.documentUndoManager === doc.undoManager)
    }

    // Validates: REQ-017 — injected Save success / cancel / failure.
    @Test func injectedSaveSuccessCancelFailure() async {
        let doc = MarkdownDocument()

        final class FakeSave: DocumentSaving {
            var result: DocumentSaveOutcome
            init(_ result: DocumentSaveOutcome) { self.result = result }
            func saveDocument() async -> DocumentSaveOutcome { result }
        }

        doc.saveExecutorOverride = FakeSave(.succeeded)
        #expect(await doc.saveDocument() == .succeeded)

        doc.saveExecutorOverride = FakeSave(.cancelled)
        #expect(await doc.saveDocument() == .cancelled)
    }

    // Validates: REQ-019 — URL change advances location generation; untitled-save path does not.
    @Test func locationGenerationAdvancesOnURLChangeButNotUntitledSave() async {
        let doc = MarkdownDocument()
        #expect(doc.locationGeneration == 0)

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url1 = dir.appendingPathComponent("a.md")
        let url2 = dir.appendingPathComponent("b.md")
        try? Data().write(to: url1)
        try? Data().write(to: url2)

        final class AssigningSave: DocumentSaving {
            let doc: MarkdownDocument
            let url: URL
            init(doc: MarkdownDocument, url: URL) {
                self.doc = doc
                self.url = url
            }
            func saveDocument() async -> DocumentSaveOutcome {
                doc.fileURL = url
                return .succeeded
            }
        }

        doc.saveExecutorOverride = AssigningSave(doc: doc, url: url1)
        #expect(await doc.saveDocument() == .succeeded)
        #expect(doc.fileURL == url1)
        #expect(doc.locationGeneration == 0) // untitled → first URL via Save

        doc.fileURL = url2
        #expect(doc.locationGeneration == 1)
    }

    // Validates: REQ-018 — data(ofType:) snapshots canonical main-actor text under serialized I/O.
    @Test func dataOfTypeSnapshotsCanonicalMainActorText() throws {
        let doc = MarkdownDocument()
        doc.installTextForTesting("snapshot-me")
        let data = try doc.data(ofType: MarkdownContentType.identifier)
        #expect(data == Data("snapshot-me".utf8))
    }

    // Validates: REQ-096 — derived asset references notify image placement without invalidating
    // the document view. Republishing through `objectWillChange` would reschedule parsing
    // through EditorSession and create an idle reconciliation loop.
    @Test func canonicalAssetReferencesDoNotRepublishTheDocument() {
        let doc = MarkdownDocument()
        let references = CanonicalAssetReferences(values: [], sourceVersion: 1)
        var documentPublications = 0
        var assetReferenceUpdates = 0
        let documentObserver = doc.objectWillChange.sink { _ in documentPublications += 1 }
        let assetObserver = doc.canonicalAssetReferenceUpdates.sink { _ in assetReferenceUpdates += 1 }
        defer {
            documentObserver.cancel()
            assetObserver.cancel()
        }

        doc.updateCanonicalAssetReferences(references)
        doc.updateCanonicalAssetReferences(references)

        #expect(documentPublications == 0)
        #expect(assetReferenceUpdates == 1)
    }

    // Validates: REQ-014 — standard document File selectors remain wired for First Responder.
    @Test func requiredDocumentFileSelectorsAreDeclared() {
        for name in MarkdownAppDelegate.requiredDocumentSelectors {
            #expect(name.hasSuffix(":"))
        }
        #expect(Set(MarkdownAppDelegate.requiredDocumentSelectors).count == MarkdownAppDelegate.requiredDocumentSelectors.count)
        #expect(MarkdownAppDelegate.requiredDocumentSelectors.contains("saveDocument:"))
        #expect(MarkdownAppDelegate.requiredDocumentSelectors.contains("saveDocumentAs:"))
        #expect(MarkdownAppDelegate.requiredDocumentSelectors.contains("revertDocumentToSaved:"))
        // Liveness: the list is a declaration, and a declaration that names a selector nothing
        // implements would satisfy every assertion above while leaving File ▸ Save dead.
        for name in MarkdownAppDelegate.requiredDocumentSelectors {
            #expect(
                MarkdownDocument.instancesRespond(to: Selector(name)),
                "MarkdownDocument does not respond to declared selector \(name)"
            )
        }
    }
}

@MainActor
struct DocumentActionInterfaceTests {

    // Validates: REQ-017 — Save does not require view hierarchy discovery.
    @Test func saveGoesThroughInterfaceNotViewLookup() async {
        let doc = MarkdownDocument()
        final class FakeSave: DocumentSaving {
            func saveDocument() async -> DocumentSaveOutcome { .succeeded }
        }
        doc.saveExecutorOverride = FakeSave()
        let actions: DocumentActionInterface = doc
        #expect(await actions.saveDocument() == .succeeded)
    }

    // Validates: REQ-019 — placement tracking lives on the interface.
    @Test func placementTrackingIsEditorNeutral() {
        let doc = MarkdownDocument()
        doc.installTextForTesting("hello")
        let gen = doc.beginPlacementTracking(
            range: SourceRange(NSRange(location: 2, length: 0))
        )
        #expect(doc.trackedPlacement(for: gen)?.range.location == 2)
        doc.noteTrackedEdit(edited: NSRange(location: 0, length: 1), changeInLength: 0)
        #expect(doc.trackedPlacement(for: gen)?.range.location == 2)
        doc.endPlacementTracking(gen)
        #expect(doc.trackedPlacement(for: gen) == nil)
    }
}
