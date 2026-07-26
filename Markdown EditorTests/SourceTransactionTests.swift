//
//  SourceTransactionTests.swift
//  Markdown EditorTests
//

import Testing
import Foundation
import AppKit
@testable import Markdown_Editor

@MainActor
struct SourceTransactionTests {

    private func mutate(
        _ doc: MarkdownDocument,
        range: NSRange,
        replacement: String,
        expectedRevision: UInt64,
        action: String
    ) -> SourceEditResult {
        let snap = doc.sourceSnapshot()
        guard let mutation = SourceMutation.exact(
            snapshot: SourceSnapshot(
                text: snap.text,
                sourceVersion: expectedRevision,
                locationGeneration: snap.locationGeneration,
                fileURL: snap.fileURL
            ),
            range: range,
            replacement: replacement,
            selectionBefore: SourceSelection(utf16: range),
            actionName: action,
            grouping: .discrete
        ) else {
            return .refused(.invalidRange)
        }
        // Force expected revision for stale tests.
        let forced = SourceMutation(
            expectedRevision: expectedRevision,
            range: mutation.range,
            expectedText: mutation.expectedText,
            replacement: mutation.replacement,
            selectionBefore: mutation.selectionBefore,
            selectionAfter: mutation.selectionAfter,
            actionName: mutation.actionName,
            grouping: mutation.grouping
        )
        return doc.commitSourceMutation(forced)
    }

    // Verifies: REQ-016
    @Test func exactUTF16ReplaceAdvancesVersion() {
        let doc = MarkdownDocument()
        doc.installTextForTesting("Hello World")
        let result = mutate(
            doc,
            range: NSRange(location: 6, length: 5),
            replacement: "there",
            expectedRevision: 0,
            action: "Replace"
        )
        guard case .committed(let selection) = result else {
            Issue.record("expected commit")
            return
        }
        #expect(doc.text == "Hello there")
        #expect(doc.sourceVersion == 1)
        #expect(selection.range.utf16 == NSRange(location: 11, length: 0))
    }

    // Verifies: REQ-016 — Unicode scalar boundaries (emoji is 2 UTF-16 units).
    @Test func unicodeScalarBoundaryReplace() {
        let doc = MarkdownDocument()
        doc.installTextForTesting("a😀b")
        let result = mutate(
            doc,
            range: NSRange(location: 1, length: 2),
            replacement: "X",
            expectedRevision: 0,
            action: "Replace emoji"
        )
        guard case .committed = result else {
            Issue.record("expected commit")
            return
        }
        #expect(doc.text == "aXb")
        #expect(doc.sourceVersion == 1)
    }

    // Verifies: REQ-016
    @Test func staleVersionRefusesWithoutMutation() {
        let doc = MarkdownDocument()
        doc.installTextForTesting("abc")
        _ = mutate(doc, range: NSRange(location: 0, length: 1), replacement: "A", expectedRevision: 0, action: "1")
        let before = doc.text
        let version = doc.sourceVersion
        let result = mutate(
            doc,
            range: NSRange(location: 1, length: 1),
            replacement: "Z",
            expectedRevision: 0,
            action: "stale"
        )
        #expect(result == .refused(.staleVersion))
        #expect(doc.text == before)
        #expect(doc.sourceVersion == version)
    }

    // Verifies: REQ-016
    @Test func invalidRangeRefusesWithoutMutation() {
        let doc = MarkdownDocument()
        doc.installTextForTesting("hi")
        let result = mutate(
            doc,
            range: NSRange(location: 0, length: 99),
            replacement: "x",
            expectedRevision: 0,
            action: "bad"
        )
        #expect(result == .refused(.invalidRange))
        #expect(doc.text == "hi")
        #expect(doc.sourceVersion == 0)
    }

    // Verifies: REQ-016 / REQ-013 — one undo group, redo restores.
    @Test func undoRedoRestoresTextAndAdvancesVersion() {
        let doc = MarkdownDocument()
        doc.installTextForTesting("abc")
        _ = mutate(doc, range: NSRange(location: 1, length: 1), replacement: "X", expectedRevision: 0, action: "Edit")
        #expect(doc.text == "aXc")
        #expect(doc.sourceVersion == 1)

        doc.undoManager?.undo()
        #expect(doc.text == "abc")
        #expect(doc.sourceVersion == 2)

        doc.undoManager?.redo()
        #expect(doc.text == "aXc")
        #expect(doc.sourceVersion == 3)
    }

    // Verifies: REQ-018 — snapshots are Sendable values, not live references.
    @Test func snapshotIsImmutableCopy() {
        let doc = MarkdownDocument()
        doc.installTextForTesting("one")
        let snap = doc.sourceSnapshot()
        _ = mutate(doc, range: NSRange(location: 0, length: 3), replacement: "two", expectedRevision: 0, action: "Edit")
        #expect(snap.text == "one")
        #expect(snap.sourceVersion == 0)
        #expect(doc.sourceSnapshot().text == "two")
        #expect(doc.sourceSnapshot().sourceVersion == 1)
    }
}
