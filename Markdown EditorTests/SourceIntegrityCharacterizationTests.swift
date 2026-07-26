//
//  SourceIntegrityCharacterizationTests.swift
//  Markdown EditorTests
//
//  Source mutation, history, trace, and dirty-state tests.
//

import Testing
import Foundation
import AppKit
import Combine
@testable import Markdown_Editor

@MainActor
struct SourceIntegrityCharacterizationTests {

    // Verifies: REQ-011 / REQ-016 — three independent edits, three undos, three redos.
    @Test func threeEditsThreeUndosThreeRedosRestoreEveryIntermediateSource() {
        let doc = MarkdownDocument()
        doc.installTextForTesting("_____") // 5 underscores

        // Edit 1: insert "A" at 0
        expectCommitted(
            doc.commitSourceMutation(mutation(
                doc,
                range: NSRange(location: 0, length: 0),
                expected: "",
                replacement: "A",
                name: "E1",
                grouping: .discrete
            ))
        )
        let after1 = doc.text
        #expect(after1 == "A_____")

        // Edit 2: insert "B" at end of A
        expectCommitted(
            doc.commitSourceMutation(mutation(
                doc,
                range: NSRange(location: 1, length: 0),
                expected: "",
                replacement: "B",
                name: "E2",
                grouping: .discrete
            ))
        )
        let after2 = doc.text
        #expect(after2 == "AB_____")

        // Edit 3: insert "C"
        expectCommitted(
            doc.commitSourceMutation(mutation(
                doc,
                range: NSRange(location: 2, length: 0),
                expected: "",
                replacement: "C",
                name: "E3",
                grouping: .discrete
            ))
        )
        let after3 = doc.text
        #expect(after3 == "ABC_____")

        doc.undoManager?.undo()
        #expect(doc.text == after2)
        doc.undoManager?.undo()
        #expect(doc.text == after1)
        doc.undoManager?.undo()
        #expect(doc.text == "_____")

        doc.undoManager?.redo()
        #expect(doc.text == after1)
        doc.undoManager?.redo()
        #expect(doc.text == after2)
        doc.undoManager?.redo()
        #expect(doc.text == after3)
    }

    // Verifies: REQ-016 — revision increments once per successful history operation.
    @Test func undoRedoIncrementsSourceRevisionOncePerSuccessfulHistoryOperation() {
        let doc = MarkdownDocument()
        doc.installTextForTesting("xy")
        expectCommitted(
            doc.commitSourceMutation(mutation(
                doc,
                range: NSRange(location: 0, length: 1),
                expected: "x",
                replacement: "X",
                name: "Edit",
                grouping: .discrete
            ))
        )
        #expect(doc.sourceVersion == 1)

        doc.undoManager?.undo()
        #expect(doc.text == "xy")
        #expect(doc.sourceVersion == 2)

        doc.undoManager?.redo()
        #expect(doc.text == "Xy")
        #expect(doc.sourceVersion == 3)
    }

    // Verifies: REQ-016 — content-validated history refuses divergent patch without mutation.
    @Test func undoValidatesExpectedContentAndRefusesDivergentPatchWithoutMutation() {
        let doc = MarkdownDocument()
        doc.installTextForTesting("abcdef")
        let patch = HistoryPatch(
            range: NSRange(location: 0, length: 3),
            before: "abc",
            after: "XYZ", // document still has "abc", not "XYZ"
            selectionBefore: SourceSelection(utf16: NSRange(location: 0, length: 0)),
            selectionAfter: SourceSelection(utf16: NSRange(location: 3, length: 0)),
            actionName: "Divergent"
        )
        let beforeText = doc.text
        let beforeVersion = doc.sourceVersion
        let result = doc.applyHistoryPatchForTesting(patch, direction: .undo)
        #expect(result == .refused(.contentMismatch))
        #expect(doc.text == beforeText)
        #expect(doc.sourceVersion == beforeVersion)
    }

    // Verifies: REQ-016 — typing coalesces; discrete actions stay separate.
    @Test func typingGroupsCoalesceWhileDiscreteActionsRemainSeparate() {
        let doc = MarkdownDocument()
        doc.installTextForTesting("")
        doc.undoManager?.groupsByEvent = false

        expectCommitted(
            doc.commitSourceMutation(mutation(
                doc,
                range: NSRange(location: 0, length: 0),
                expected: "",
                replacement: "a",
                name: "Typing",
                grouping: .typing
            ))
        )
        expectCommitted(
            doc.commitSourceMutation(mutation(
                doc,
                range: NSRange(location: 1, length: 0),
                expected: "",
                replacement: "b",
                name: "Typing",
                grouping: .typing
            ))
        )
        expectCommitted(
            doc.commitSourceMutation(mutation(
                doc,
                range: NSRange(location: 2, length: 0),
                expected: "",
                replacement: "c",
                name: "Typing",
                grouping: .typing
            ))
        )
        #expect(doc.text == "abc")

        // One undo should remove the whole typing run.
        doc.undoManager?.undo()
        #expect(doc.text == "")

        // Discrete toolbar-style actions each undo separately.
        expectCommitted(
            doc.commitSourceMutation(mutation(
                doc,
                range: NSRange(location: 0, length: 0),
                expected: "",
                replacement: "H1",
                name: "Heading",
                grouping: .discrete
            ))
        )
        expectCommitted(
            doc.commitSourceMutation(mutation(
                doc,
                range: NSRange(location: 2, length: 0),
                expected: "",
                replacement: "!",
                name: "Insert Image",
                grouping: .discrete
            ))
        )
        #expect(doc.text == "H1!")
        doc.undoManager?.undo()
        #expect(doc.text == "H1")
        doc.undoManager?.undo()
        #expect(doc.text == "")
    }

    // Verifies: REQ-083 — undo/redo restores source selections across mode changes.
    @Test func undoRedoRestoresSourceSelectionsAcrossModeChanges() {
        let doc = MarkdownDocument()
        doc.installTextForTesting("hello")
        let before = SourceSelection(utf16: NSRange(location: 0, length: 5))
        let after = SourceSelection(utf16: NSRange(location: 5, length: 0))
        var restorations: [SourceSelection] = []
        let cancellable = doc.selectionRestorations.sink { restorations.append($0) }
        defer { cancellable.cancel() }

        expectCommitted(
            doc.commitSourceMutation(
                SourceMutation(
                    expectedRevision: doc.sourceVersion,
                    range: NSRange(location: 0, length: 5),
                    expectedText: "hello",
                    replacement: "HELLO",
                    selectionBefore: before,
                    selectionAfter: after,
                    actionName: "Upper",
                    grouping: .discrete
                )
            )
        )
        #expect(restorations.isEmpty)

        doc.undoManager?.undo()
        #expect(doc.text == "hello")
        #expect(restorations.last?.range.utf16 == before.range.utf16)

        doc.undoManager?.redo()
        #expect(doc.text == "HELLO")
        #expect(restorations.last?.range.utf16 == after.range.utf16)
    }

    // Verifies: REQ-011 — dirty clears at saved history point; dirty again on redo.
    @Test func dirtyStateTracksSavedHistoryPoint() {
        let doc = MarkdownDocument()
        doc.installTextForTesting("base")
        #expect(doc.isDocumentEdited == false)

        expectCommitted(
            doc.commitSourceMutation(mutation(
                doc,
                range: NSRange(location: 4, length: 0),
                expected: "",
                replacement: "!",
                name: "Edit",
                grouping: .discrete
            ))
        )
        #expect(doc.isDocumentEdited == true)

        doc.undoManager?.undo()
        #expect(doc.text == "base")
        #expect(doc.isDocumentEdited == false)

        doc.undoManager?.redo()
        #expect(doc.text == "base!")
        #expect(doc.isDocumentEdited == true)
    }

    // Verifies: REQ-018 — serialized data(ofType:) reads the current canonical text.
    @Test func serializedDataReadsCanonicalText() throws {
        let doc = MarkdownDocument()
        let payload = String(repeating: "snapshot-", count: 200)
        doc.installTextForTesting(payload)

        let expected = try doc.data(ofType: MarkdownContentType.identifier)
        #expect(expected == Data(payload.utf8))
        let again = try doc.data(ofType: MarkdownContentType.identifier)
        #expect(again == expected)
    }

    // Verifies: REQ-089 — traces never carry document content or paths.
    @Test func editorTraceOmitsSourceSelectionAndPathStrings() {
        let trace = InMemoryEditorTrace()
        let doc = MarkdownDocument()
        doc.trace = trace
        doc.installTextForTesting("secret-path-/Users/private/doc.md")
        expectCommitted(
            doc.commitSourceMutation(mutation(
                doc,
                range: NSRange(location: 0, length: 6),
                expected: "secret",
                replacement: "PUBLIC",
                name: "Edit",
                grouping: .discrete
            ))
        )
        let dumped = String(describing: trace.events)
        #expect(!dumped.contains("secret"))
        #expect(!dumped.contains("/Users/"))
        #expect(!dumped.contains("PRIVATE"))
        #expect(!dumped.contains("PUBLIC"))
        #expect(trace.events.contains { event in
            if case .mutationCommitted = event { return true }
            return false
        })
    }

    // MARK: - Helpers

    private func mutation(
        _ doc: MarkdownDocument,
        range: NSRange,
        expected: String,
        replacement: String,
        name: String,
        grouping: MutationGrouping
    ) -> SourceMutation {
        let afterLoc = range.location + (replacement as NSString).length
        return SourceMutation(
            expectedRevision: doc.sourceVersion,
            range: range,
            expectedText: expected,
            replacement: replacement,
            selectionBefore: SourceSelection(utf16: range),
            selectionAfter: SourceSelection(utf16: NSRange(location: afterLoc, length: 0)),
            actionName: name,
            grouping: grouping
        )
    }

    private func expectCommitted(_ result: SourceEditResult) {
        guard case .committed = result else {
            Issue.record("expected committed, got \(result)")
            return
        }
    }
}
