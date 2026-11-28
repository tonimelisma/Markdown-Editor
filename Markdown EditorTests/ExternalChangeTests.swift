//
//  ExternalChangeTests.swift
//  Markdown EditorTests
//

import AppKit
import Foundation
import Testing
@testable import Markdown_Editor

/// What happens when the file changes underneath an open document.
///
/// // Validates: REQ-145, REQ-146, REQ-147, REQ-148, REQ-149; ARC-027.
///
/// vision.md ranks *trustworthy files* first, and before COR-87 no requirement covered this at all:
/// `MarkdownDocument` overrode thirteen `NSDocument` members and none of them was a file-presenter
/// callback. The behaviour was whatever AppKit inherited, and nobody had observed it.
///
/// These drive `applyExternalChange` directly rather than through `NSFileCoordinator`, and that
/// is deliberate. `MarkdownDocument.autosavesInPlace` is `false` under XCTest — a documented
/// choice, because AppKit autosave races Swift 6 isolation in the test host — and the file
/// presenter machinery depends on it. A test that wrote through a coordinator would therefore be
/// observing a configuration that never ships, and would pass whatever the production behaviour
/// was. The presenter overrides are one line each for the same reason: the behaviour lives where
/// it can be proved.
@MainActor
struct ExternalChangeTests {

    private func documentOnDisk(_ text: String) throws -> (MarkdownDocument, URL, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("doc.md")
        try Data(text.utf8).write(to: url)
        let document = MarkdownDocument()
        try document.read(from: url, ofType: MarkdownContentType.identifier)
        document.fileURL = url
        document.fileType = MarkdownContentType.identifier
        return (document, url, dir)
    }

    // MARK: - The closed matrix

    /// // Validates: REQ-149 — every event × local-state cell has declared behaviour. A new
    /// `ExternalFileEvent` case fails the build in `ExternalChangeDomain.outcome`, and fails this
    /// table until someone states what it does.
    @Test func everyExternalChangeClassHasDeclaredBehavior() {
        let expected: [ExternalFileEvent: [LocalEditState: ExternalChangeOutcome]] = [
            .contentsChanged: [.clean: .reloadPreservingSelection,
                               .dirty: .retainLocalEditsAsConflicted],
            .deleted: [.clean: .retainContentAfterDeletion,
                       .dirty: .retainContentAfterDeletion],
            .moved: [.clean: .followMove,
                     .dirty: .followMove],
        ]
        for event in ExternalFileEvent.allCases {
            for local in LocalEditState.allCases {
                let declared = expected[event]?[local]
                #expect(declared != nil, "\(event) × \(local) has no declared outcome")
                #expect(
                    ExternalChangeDomain.outcome(for: event, local: local) == declared,
                    "\(event) × \(local) disagrees with the declared matrix"
                )
            }
        }
        // No cell may discard the buffer without the user asking: `reloadPreservingSelection` is
        // the only outcome that replaces content, and it is reachable only when nothing is unsaved.
        for local in LocalEditState.allCases where local == .dirty {
            for event in ExternalFileEvent.allCases {
                #expect(
                    ExternalChangeDomain.outcome(for: event, local: local) != .reloadPreservingSelection,
                    "\(event) discards unsaved work"
                )
            }
        }
    }

    // MARK: - Contents changed

    /// // Validates: REQ-145 — a clean document adopts the file and keeps the reader's place.
    @Test func externalWriteToCleanDocumentReloadsAndKeepsSelection() throws {
        let (document, url, dir) = try documentOnDisk("alpha\nbravo\ncharlie\n")
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(document.isDocumentEdited == false)

        document.lastKnownSourceSelection = NSRange(location: 8, length: 0)
        try Data("ALPHA\nBRAVO\nCHARLIE\n".utf8).write(to: url)

        #expect(document.applyExternalChange(.contentsChanged) == .reloadPreservingSelection)
        #expect(document.text == "ALPHA\nBRAVO\nCHARLIE\n")
        #expect(document.hasUnresolvedExternalChange == false)
        let hint = document.consumeExternalReloadSelectionHint()
        #expect(hint == NSRange(location: 8, length: 0), "the caret was not carried across the reload")
    }

    /// // Validates: REQ-146 — a dirty document keeps its edits and records the disagreement, and
    /// the file is not overwritten as a side effect of noticing.
    @Test func externalWriteToDirtyDocumentKeepsLocalEditsAndMarksConflict() throws {
        let (document, url, dir) = try documentOnDisk("original\n")
        defer { try? FileManager.default.removeItem(at: dir) }
        document.installTextForTesting("my unsaved work\n")
        document.updateChangeCount(.changeDone)
        #expect(document.isDocumentEdited)

        try Data("their work\n".utf8).write(to: url)
        #expect(document.applyExternalChange(.contentsChanged) == .retainLocalEditsAsConflicted)

        #expect(document.text == "my unsaved work\n", "unsaved work was discarded")
        #expect(document.hasUnresolvedExternalChange, "the conflict was not recorded")
        let onDisk = try String(contentsOf: url, encoding: .utf8)
        #expect(onDisk == "their work\n", "the external write was overwritten without being asked")
    }

    /// // Validates: REQ-146, REQ-149 — words typed since the last save are unsaved work, though their
    /// undo group is still open and AppKit has not counted a change. Tour 45968755636 typed a
    /// sentence, another app wrote the file, and the reload discarded the sentence.
    @Test func wordsTypedSinceTheLastSaveAreKeptWhenAnotherAppWrites() throws {
        let (document, url, dir) = try documentOnDisk("original\n")
        defer { try? FileManager.default.removeItem(at: dir) }
        let session = EditorSession()
        session.attach(document: document)
        defer { session.detach() }
        session.setMode(.source)
        for (offset, character) in "Mine.".enumerated() {
            let caret = SourceSelection(utf16: NSRange(location: 9 + offset, length: 0))
            session.captureSelection(.source(caret))
            let outcome = session.perform(
                .insertText(String(character)),
                selection: .source(caret),
                expectedSourceRevision: SourceRevision(value: document.sourceVersion)
            )
            let accepted: Bool
            if case .accepted = outcome { accepted = true } else { accepted = false }
            try #require(accepted, "typing was \(outcome)")
        }
        try #require(document.text == "original\nMine.")

        try Data("their work\n".utf8).write(to: url)
        #expect(document.applyExternalChange(.contentsChanged) == .retainLocalEditsAsConflicted)
        #expect(document.text == "original\nMine.", "the typed words were discarded: \(document.text.debugDescription)")
    }

    /// // Validates: REQ-146 — a save stopped for the conflict alert is the app asking, recorded as
    /// such: as an error, every run that saved through a conflict looked like a faulty one.
    @Test func aSaveStoppedForTheConflictAlertIsNotAnError() throws {
        let (document, url, dir) = try documentOnDisk("original\n")
        defer { try? FileManager.default.removeItem(at: dir) }
        let trace = InMemoryEditorTrace()
        document.trace = trace
        document.installTextForTesting("mine\n")
        document.updateChangeCount(.changeDone)
        try Data("theirs\n".utf8).write(to: url)
        try #require(document.applyExternalChange(.contentsChanged) == .retainLocalEditsAsConflicted)

        document.recordSaveOutcome(error: CocoaError(.fileWriteUnknown), utf16Count: 5, startUptimeNanos: 0)
        let reasons = trace.eventsMatching {
            if case .documentSaveFailed = $0 { return true }
            return false
        }
        let asked = reasons.contains {
            if case .documentSaveFailed(reason: .awaitingConflictDecision) = $0 { return true }
            return false
        }
        #expect(asked && reasons.count == 1, "recorded \(reasons)")
    }

    /// The conflict is a state, not a permanent mark: reverting resolves it.
    @Test func revertingResolvesTheConflict() throws {
        let (document, url, dir) = try documentOnDisk("original\n")
        defer { try? FileManager.default.removeItem(at: dir) }
        document.installTextForTesting("mine\n")
        document.updateChangeCount(.changeDone)
        try Data("theirs\n".utf8).write(to: url)
        _ = document.applyExternalChange(.contentsChanged)
        #expect(document.hasUnresolvedExternalChange)

        try document.revert(toContentsOf: url, ofType: MarkdownContentType.identifier)
        #expect(document.text == "theirs\n")
        #expect(document.hasUnresolvedExternalChange == false)
    }

    // MARK: - Deletion

    /// // Validates: REQ-147 — losing the buffer because another process unlinked the file is the
    /// worst outcome available, and is structurally impossible.
    @Test func externalDeleteRetainsContentAndCannotLoseTheBuffer() throws {
        let (document, url, dir) = try documentOnDisk("precious\n")
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.removeItem(at: url)

        #expect(document.applyExternalChange(.deleted) == .retainContentAfterDeletion)
        #expect(document.text == "precious\n", "the only remaining copy was discarded")
        // The buffer is now the only copy, so closing must not be silent.
        #expect(document.isDocumentEdited, "the sole remaining copy is not marked as unsaved work")
        #expect(document.hasUnresolvedExternalChange)
    }

    /// Deletion retains content whether or not the document was already edited.
    @Test func deletionRetainsContentFromEitherLocalState() throws {
        for edited in [false, true] {
            let (document, url, dir) = try documentOnDisk("content\n")
            defer { try? FileManager.default.removeItem(at: dir) }
            if edited {
                document.installTextForTesting("edited\n")
                document.updateChangeCount(.changeDone)
            }
            let before = document.text
            try FileManager.default.removeItem(at: url)
            #expect(document.applyExternalChange(.deleted) == .retainContentAfterDeletion)
            #expect(document.text == before)
        }
    }

    // MARK: - Movement

    /// // Validates: REQ-148 — a moved document resolves `assets/…` against its new parent.
    ///
    /// This is the case that is specific to this product: vision.md promises relative-path semantics
    /// survive a move, and specifies it for *in-app* moves only. Nothing had ever moved a document
    /// externally and re-resolved a live reference.
    @Test func externalMoveReResolvesRelativeAssetReferences() throws {
        let (document, url, dir) = try documentOnDisk("![](assets/x.png)\n")
        defer { try? FileManager.default.removeItem(at: dir) }

        let movedParent = dir.appendingPathComponent("moved", isDirectory: true)
        let movedAssets = movedParent.appendingPathComponent("assets", isDirectory: true)
        try FileManager.default.createDirectory(at: movedAssets, withIntermediateDirectories: true)
        let asset = movedAssets.appendingPathComponent("x.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: asset)

        let generationBefore = document.locationGeneration
        let destination = movedParent.appendingPathComponent("doc.md")
        try FileManager.default.moveItem(at: url, to: destination)
        document.fileURL = destination

        #expect(document.applyExternalChange(.moved) == .followMove)
        #expect(document.text == "![](assets/x.png)\n", "a move changed content")
        #expect(
            document.locationGeneration != generationBefore,
            "location generation did not advance, so cached asset resolutions are stale"
        )
        // The reference now resolves against the new parent — the property the generation exists
        // to guarantee.
        let resolved = document.fileURL?
            .deletingLastPathComponent()
            .appendingPathComponent("assets/x.png")
        #expect(resolved.map { FileManager.default.fileExists(atPath: $0.path) } == true)
    }

    // MARK: - Self-inflicted notifications

    /// // Validates: REQ-145 — the application does not treat its own writes as external changes.
    ///
    /// AppKit delivers `presentedItemDidChange()` for autosave, save, and open as well as for
    /// foreign writes. Before this check the smoke run caught the app reverting its own document
    /// moments after opening it: one spurious reload, nine host updates against a threshold of
    /// eight. A reload is not free even when the text matches — it discards the caret and the
    /// undo stack.
    @Test func aWriteMatchingTheBufferIsNotAnExternalChange() {
        #expect(ExternalChangeDomain.isForeignContentChange(onDisk: "same\n", buffer: "same\n") == false)
        #expect(ExternalChangeDomain.isForeignContentChange(onDisk: "theirs\n", buffer: "mine\n"))
        // An unreadable file is not a content change; deletion is a separate event with its own
        // cell, and guessing from a failed read would reload the buffer away on a transient error.
        #expect(ExternalChangeDomain.isForeignContentChange(onDisk: nil, buffer: "mine\n") == false)
    }

    // MARK: - Selection clamping

    /// A caret past the end of the new text lands at the end, not out of bounds.
    @Test func preservedSelectionIsClampedIntoTheNewText() {
        #expect(
            ExternalChangeDomain.preservedSelection(previous: NSRange(location: 900, length: 0), inNewLength: 10)
                == NSRange(location: 10, length: 0)
        )
        #expect(
            ExternalChangeDomain.preservedSelection(previous: NSRange(location: 4, length: 50), inNewLength: 10)
                == NSRange(location: 4, length: 6)
        )
        #expect(
            ExternalChangeDomain.preservedSelection(previous: NSRange(location: 5, length: 2), inNewLength: 0)
                == NSRange(location: 0, length: 0)
        )
        // The ordinary case is exact.
        #expect(
            ExternalChangeDomain.preservedSelection(previous: NSRange(location: 3, length: 2), inNewLength: 20)
                == NSRange(location: 3, length: 2)
        )
    }

    // MARK: - Privacy

    /// // Validates: REQ-031 — an external change is reported without naming the file.
    @Test func externalChangeDiagnosticsCarryNoPath() throws {
        let trace = InMemoryEditorTrace()
        let (document, url, dir) = try documentOnDisk("x\n")
        defer { try? FileManager.default.removeItem(at: dir) }
        document.trace = trace
        try Data("y\n".utf8).write(to: url)
        _ = document.applyExternalChange(.contentsChanged)

        let events = trace.eventsMatching {
            if case .externalFileChange = $0 { return true }
            return false
        }
        #expect(!events.isEmpty, "an external change was not recorded at all")
        // The payload type cannot represent a string at all (ARC-016), which is what makes this
        // structural rather than a promise; assert the event carries only its closed symbols.
        for event in events {
            guard case .externalFileChange(let kind, let local, let outcome, _) = event else { continue }
            #expect(ExternalFileEvent.allCases.contains(kind))
            #expect(LocalEditState.allCases.contains(local))
            #expect(ExternalChangeOutcome.allCases.contains(outcome))
        }
    }
}
