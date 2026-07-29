//
//  MarkdownDocumentTests.swift
//  Markdown EditorTests
//

import Testing
import Foundation
import AppKit
import UniformTypeIdentifiers
@testable import Markdown_Editor

@MainActor
struct MarkdownDocumentTests {

    // Verifies: REQ-013 / REQ-015
    @Test func readableWritableTypesAreMarkdown() {
        #expect(MarkdownDocument.readableTypes.contains(MarkdownContentType.identifier))
        #expect(MarkdownDocument.writableTypes.contains(MarkdownContentType.identifier))
    }

    // Verifies: REQ-015
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

    // Verifies: REQ-015
    @Test func readRejectsInvalidUTF8() {
        let doc = MarkdownDocument()
        #expect(throws: CocoaError.self) {
            try doc.read(from: Data([0xFF, 0xFE, 0xFD]), ofType: MarkdownContentType.identifier)
        }
    }

    // Verifies: REQ-014 — autosave in place is enabled for production.
    @Test func autosavesInPlace() {
        #expect(MarkdownDocument.autosavesInPlaceForProduction == true)
    }

    // Verifies: REQ-013 — document owns undo manager used by transactions.
    @Test func documentOwnsUndoManager() {
        let doc = MarkdownDocument()
        #expect(doc.documentUndoManager != nil)
        #expect(doc.documentUndoManager === doc.undoManager)
    }

    // Verifies: REQ-017 — injected Save success / cancel / failure.
    @Test func injectedSaveSuccessCancelFailure() async {
        let doc = MarkdownDocument()

        final class FakeSave: DocumentSaving {
            var result: Bool
            init(_ result: Bool) { self.result = result }
            func saveDocument() async -> Bool { result }
        }

        doc.saveExecutorOverride = FakeSave(true)
        #expect(await doc.saveDocument() == true)

        doc.saveExecutorOverride = FakeSave(false)
        #expect(await doc.saveDocument() == false)
    }


    // Verifies: REQ-019 — URL change advances location generation; untitled-save path does not.
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
            func saveDocument() async -> Bool {
                doc.fileURL = url
                return true
            }
        }

        doc.saveExecutorOverride = AssigningSave(doc: doc, url: url1)
        #expect(await doc.saveDocument() == true)
        #expect(doc.fileURL == url1)
        #expect(doc.locationGeneration == 0) // untitled → first URL via Save

        doc.fileURL = url2
        #expect(doc.locationGeneration == 1)
    }

    // Verifies: REQ-018 — data(ofType:) snapshots canonical main-actor text under serialized I/O.
    @Test func dataOfTypeSnapshotsCanonicalMainActorText() throws {
        let doc = MarkdownDocument()
        doc.installTextForTesting("snapshot-me")
        let data = try doc.data(ofType: MarkdownContentType.identifier)
        #expect(data == Data("snapshot-me".utf8))
    }

    // Verifies: REQ-014 — standard document File selectors remain wired for First Responder.
    @Test func requiredDocumentFileSelectorsAreDeclared() {
        for name in MarkdownAppDelegate.requiredDocumentSelectors {
            #expect(name.hasSuffix(":"))
        }
        #expect(Set(MarkdownAppDelegate.requiredDocumentSelectors).count == MarkdownAppDelegate.requiredDocumentSelectors.count)
        #expect(MarkdownAppDelegate.requiredDocumentSelectors.contains("saveDocument:"))
        #expect(MarkdownAppDelegate.requiredDocumentSelectors.contains("saveDocumentAs:"))
        #expect(MarkdownAppDelegate.requiredDocumentSelectors.contains("revertDocumentToSaved:"))
    }
}

@MainActor
struct DocumentActionInterfaceTests {

    // Verifies: REQ-017 — Save does not require view hierarchy discovery.
    @Test func saveGoesThroughInterfaceNotViewLookup() async {
        let doc = MarkdownDocument()
        final class FakeSave: DocumentSaving {
            func saveDocument() async -> Bool { true }
        }
        doc.saveExecutorOverride = FakeSave()
        let actions: DocumentActionInterface = doc
        #expect(await actions.saveDocument() == true)
    }

    // Verifies: REQ-019 — placement tracking lives on the interface.
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
