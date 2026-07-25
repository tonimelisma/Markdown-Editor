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

    // Verifies: REQ-016
    @Test func exactUTF16ReplaceAdvancesVersion() {
        let doc = MarkdownDocument()
        doc.installTextForTesting("Hello World")
        let result = doc.commitSourceEdit(
            SourceEdit(
                expectedVersion: 0,
                range: NSRange(location: 6, length: 5),
                replacement: "there",
                actionName: "Replace"
            )
        )
        guard case .committed(let selection) = result else {
            Issue.record("expected commit")
            return
        }
        #expect(doc.text == "Hello there")
        #expect(doc.sourceVersion == 1)
        #expect(selection.range == NSRange(location: 11, length: 0))
    }

    // Verifies: REQ-016 — Unicode scalar boundaries (emoji is 2 UTF-16 units).
    @Test func unicodeScalarBoundaryReplace() {
        let doc = MarkdownDocument()
        doc.installTextForTesting("a😀b")
        // 😀 is U+1F600 → surrogate pair at UTF-16 indices 1..<3
        let result = doc.commitSourceEdit(
            SourceEdit(
                expectedVersion: 0,
                range: NSRange(location: 1, length: 2),
                replacement: "X",
                actionName: "Replace emoji"
            )
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
        _ = doc.commitSourceEdit(
            SourceEdit(expectedVersion: 0, range: NSRange(location: 0, length: 1), replacement: "A", actionName: "1")
        )
        let before = doc.text
        let version = doc.sourceVersion
        let result = doc.commitSourceEdit(
            SourceEdit(expectedVersion: 0, range: NSRange(location: 1, length: 1), replacement: "Z", actionName: "stale")
        )
        #expect(result == .refused(.staleVersion))
        #expect(doc.text == before)
        #expect(doc.sourceVersion == version)
    }

    // Verifies: REQ-016
    @Test func invalidRangeRefusesWithoutMutation() {
        let doc = MarkdownDocument()
        doc.installTextForTesting("hi")
        let result = doc.commitSourceEdit(
            SourceEdit(expectedVersion: 0, range: NSRange(location: 0, length: 99), replacement: "x", actionName: "bad")
        )
        #expect(result == .refused(.invalidRange))
        #expect(doc.text == "hi")
        #expect(doc.sourceVersion == 0)
    }

    // Verifies: REQ-016 / REQ-013 — one undo group, redo restores.
    @Test func undoRedoRestoresTextAndAdvancesVersion() {
        let doc = MarkdownDocument()
        doc.installTextForTesting("abc")
        _ = doc.commitSourceEdit(
            SourceEdit(expectedVersion: 0, range: NSRange(location: 1, length: 1), replacement: "X", actionName: "Edit")
        )
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
        _ = doc.commitSourceEdit(
            SourceEdit(expectedVersion: 0, range: NSRange(location: 0, length: 3), replacement: "two", actionName: "Edit")
        )
        #expect(snap.text == "one")
        #expect(snap.sourceVersion == 0)
        #expect(doc.sourceSnapshot().text == "two")
        #expect(doc.sourceSnapshot().sourceVersion == 1)
    }
}
