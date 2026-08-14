//
//  EditorTransactionKernelTests.swift
//  Markdown EditorTests
//

import AppKit
import Foundation
import Testing
@testable import Markdown_Editor

@MainActor
struct EditorTransactionKernelTests {
    // Verifies: COR-70 acceptedEditAdvancesSourcePresentationSelectionAndUndoOnce.
    @Test func acceptedEditAdvancesSourcePresentationSelectionAndUndoOnce() {
        let document = MarkdownDocument()
        document.installTextForTesting("hello\n")
        let trace = InMemoryEditorTrace()
        document.trace = trace
        let session = EditorSession(performanceSamplerCoordinator: DiagnosticRunCoordinator())
        session.attach(document: document)
        let tree = MarkdownParser.parse(document.text, sourceVersion: document.sourceVersion).get()!
        let model = MarkdownProjectionModel.build(
            tree: tree,
            index: MarkdownSourceIndex(source: document.text, sourceVersion: document.sourceVersion)
        )
        session.installProjectionForTesting(model, tree: tree)

        let initialRevision = document.sourceVersion
        let initialPresentationID = session.presentation?.id
        let beforeCommitCount = trace.events.filter {
            if case .mutationCommitted = $0 { return true }
            return false
        }.count
        let outcome = session.perform(
            .insertText("X"),
            selection: .projection(
                ProjectionSelection(
                    utf16: NSRange(location: 0, length: 0),
                    revision: session.presentation!.projectionRevision
                )
            ),
            expectedSourceRevision: SourceRevision(value: initialRevision)
        )

        guard case .accepted(let edit) = outcome else {
            Issue.record("accepted transaction refused: \(outcome)")
            return
        }
        #expect(edit.intent != nil)
        #expect(document.text == "Xhello\n")
        #expect(document.sourceVersion == initialRevision + 1)
        #expect(session.presentation?.id != initialPresentationID)
        #expect(session.presentation?.sourceRevision.value == document.sourceVersion)
        #expect(session.sourceModeState.selection == edit.sourceSelectionAfter)
        #expect(session.wysiwygModeState.selection == edit.projectionSelectionAfter)
        #expect(trace.events.filter {
            if case .mutationCommitted = $0 { return true }
            return false
        }.count - beforeCommitCount == 1)
        #expect(document.documentUndoManager?.canUndo == true)

        document.documentUndoManager?.undo()
        #expect(document.text == "hello\n")
        #expect(document.sourceVersion == initialRevision + 2)
    }

    // Verifies: COR-70 refusedEditMutatesNothing.
    @Test func refusedEditMutatesNothing() {
        let document = MarkdownDocument()
        document.installTextForTesting("abc")
        let state = EditorStateSnapshot(
            source: document.sourceSnapshot(),
            sourceSelection: SourceSelection(utf16: NSRange(location: 1, length: 0))
        )
        let mutation = SourceMutation(
            expectedRevision: document.sourceVersion + 1,
            range: NSRange(location: 1, length: 0),
            expectedText: "",
            replacement: "X",
            selectionBefore: state.sourceSelection,
            selectionAfter: SourceSelection(utf16: NSRange(location: 2, length: 0)),
            actionName: "Typing",
            grouping: .typing
        )
        let input = EditorInput.sourceReplacement(EditorReplacementInput(mutation: mutation))
        let before = state
        let result = EditorTransactionKernel.reduce(input, state: state)
        #expect(result == .refused(.staleVersion))
        #expect(state == before)
        #expect(document.text == "abc")
        #expect(document.sourceVersion == 0)
        #expect(document.documentUndoManager?.canUndo == false)
    }

    // Verifies: COR-70 kernelRejectsMismatchedPlansAndSelectionIdentities.
    @Test func kernelRejectsMismatchedPlansAndSelectionIdentities() {
        let document = MarkdownDocument()
        document.installTextForTesting("abc")
        let selection = SourceSelection(utf16: NSRange(location: 0, length: 0))
        let state = EditorStateSnapshot(
            source: document.sourceSnapshot(),
            sourceSelection: selection
        )
        let request = EditorEditRequest(
            command: .insertText("X"),
            selection: .source(selection),
            expectedSourceRevision: SourceRevision(value: state.source.sourceVersion),
            grouping: .typing
        )
        let mismatchedMutation = SourceMutation(
            expectedRevision: state.source.sourceVersion,
            range: NSRange(location: 0, length: 1),
            expectedText: "not-abc",
            replacement: "X",
            selectionBefore: selection,
            selectionAfter: SourceSelection(utf16: NSRange(location: 1, length: 0)),
            actionName: "Typing",
            grouping: .typing
        )
        let mismatchedPlan = EditorEditOutcome.accepted(
            AcceptedEdit(
                sourceMutation: mismatchedMutation,
                presentationTransition: nil,
                sourceSelectionAfter: mismatchedMutation.selectionAfter,
                projectionSelectionAfter: nil,
                intent: nil
            )
        )
        let plannedResult = EditorTransactionKernel.reduce(
            .semanticCommand(EditorSemanticInput(request: request, plannedOutcome: mismatchedPlan)),
            state: state
        )
        #expect(plannedResult == .refused(.contentMismatch))
        #expect(document.text == "abc")
        #expect(document.sourceVersion == 0)
        #expect(document.documentUndoManager?.canUndo == false)

        let staleSelectionMutation = SourceMutation(
            expectedRevision: state.source.sourceVersion,
            range: NSRange(location: 0, length: 0),
            expectedText: "",
            replacement: "X",
            selectionBefore: SourceSelection(utf16: NSRange(location: 1, length: 0)),
            selectionAfter: SourceSelection(utf16: NSRange(location: 2, length: 0)),
            actionName: "Typing",
            grouping: .typing
        )
        let identityResult = EditorTransactionKernel.reduce(
            .sourceReplacement(
                EditorReplacementInput(
                    mutation: staleSelectionMutation,
                    selectionIdentity: .source(staleSelectionMutation.selectionBefore)
                )
            ),
            state: state
        )
        #expect(identityResult == .refused(.ambiguousSelection))
        #expect(document.text == "abc")
        #expect(document.sourceVersion == 0)
    }

    // Verifies: COR-70 reconciliationRejectsUnexpectedCurrentPresentationIdentity.
    @Test func reconciliationRejectsUnexpectedCurrentPresentationIdentity() {
        let source = SourceSnapshot(text: "abc", sourceVersion: 3, locationGeneration: 7, fileURL: nil)
        let state = EditorStateSnapshot(source: source)
        let result = EditorTransactionKernel.reduce(
            .reconciliation(
                EditorReconciliationInput(
                    sourceRevision: SourceRevision(value: 3),
                    locationGeneration: 7,
                    projectionID: PresentationSnapshot.ID(value: 11),
                    expectedProjectionID: PresentationSnapshot.ID(value: 10)
                )
            ),
            state: state
        )
        #expect(result == .refused(.staleVersion))
    }

    // Verifies: COR-70 realSourceAdapterRouteUsesKernelCommitExactlyOnce.
    @Test func realSourceAdapterRouteUsesKernelCommitExactlyOnce() {
        let document = MarkdownDocument()
        document.installTextForTesting("abc")
        let trace = InMemoryEditorTrace()
        document.trace = trace
        let session = EditorSession()
        session.attach(document: document)
        let coordinator = SourceEditor.Coordinator(
            document: document,
            placementController: ImagePlacementController(),
            session: session
        )
        let mutation = SourceMutation(
            expectedRevision: document.sourceVersion,
            range: NSRange(location: 0, length: 1),
            expectedText: "a",
            replacement: "A",
            selectionBefore: SourceSelection(utf16: NSRange(location: 0, length: 1)),
            selectionAfter: SourceSelection(utf16: NSRange(location: 1, length: 0)),
            actionName: "Typing",
            grouping: .typing
        )
        let before = trace.events.filter {
            if case .mutationCommitted = $0 { return true }
            return false
        }.count
        let result = coordinator.commitNativeMutation(mutation)
        guard case .committed = result else {
            Issue.record("real source route refused: \(result)")
            return
        }
        #expect(document.text == "Abc")
        #expect(document.sourceVersion == 1)
        #expect(trace.events.filter {
            if case .mutationCommitted = $0 { return true }
            return false
        }.count - before == 1)
        #expect(document.documentUndoManager?.canUndo == true)
    }

    // Verifies: COR-70 everyInputRouteUsesEditorTransactionKernel.
    @Test(arguments: EditorInputRoute.allCases)
    func everyInputRouteUsesEditorTransactionKernel(_ route: EditorInputRoute) throws {
        let document = MarkdownDocument()
        document.installTextForTesting("a")
        let source = document.sourceSnapshot()
        let selection = SourceSelection(utf16: NSRange(location: 0, length: 0))
        let mutation = SourceMutation(
            expectedRevision: source.sourceVersion,
            range: NSRange(location: 0, length: 0),
            expectedText: "",
            replacement: "x",
            selectionBefore: selection,
            selectionAfter: SourceSelection(utf16: NSRange(location: 1, length: 0)),
            actionName: "Test",
            grouping: .discrete
        )
        let request = EditorEditRequest(
            command: .insertText("x"),
            selection: .source(selection),
            expectedSourceRevision: SourceRevision(value: source.sourceVersion),
            grouping: .discrete
        )
        let plannedOutcome = EditorEditOutcome.accepted(
            AcceptedEdit(
                sourceMutation: mutation,
                presentationTransition: nil,
                sourceSelectionAfter: mutation.selectionAfter,
                projectionSelectionAfter: nil,
                intent: nil
            )
        )
        let input: EditorInput
        switch route {
        case .sourceReplacement:
            input = .sourceReplacement(EditorReplacementInput(mutation: mutation))
        case .wysiwygReplacement:
            input = .wysiwygReplacement(EditorSemanticInput(request: request, plannedOutcome: plannedOutcome))
        case .markedText:
            input = .markedText(EditorMarkedTextInput(
                phase: .update,
                sourceRevision: SourceRevision(value: source.sourceVersion)
            ))
        case .semanticCommand:
            input = .semanticCommand(EditorSemanticInput(request: request, plannedOutcome: plannedOutcome))
        case .checkbox:
            input = .checkbox(EditorSemanticInput(request: request, plannedOutcome: plannedOutcome))
        case .imageReference:
            input = .imageReference(EditorReplacementInput(mutation: mutation))
        case .undoRedo:
            input = .undoRedo(
                EditorHistoryInput(
                    patch: HistoryPatch(
                        range: NSRange(location: 0, length: 1),
                        before: "",
                        after: "a",
                        selectionBefore: selection,
                        selectionAfter: SourceSelection(utf16: NSRange(location: 1, length: 0)),
                        actionName: "Undo"
                    ),
                    direction: .undo
                )
            )
        case .modeChange:
            input = .modeChange(EditorModeInput(mode: .wysiwyg))
        case .reconciliation:
            input = .reconciliation(
                EditorReconciliationInput(
                    sourceRevision: SourceRevision(value: source.sourceVersion),
                    locationGeneration: source.locationGeneration,
                    projectionID: PresentationSnapshot.ID(value: 1)
                )
            )
        }
        let state = EditorStateSnapshot(source: source, sourceSelection: selection)
        let result = EditorTransactionKernel.reduce(input, state: state)
        switch result {
        case .accepted(let transaction):
            #expect(transaction.route == route)
        case .refused(let refusal):
            #expect(EditorRefusal.allCases.contains(refusal))
            Issue.record("closed input route \(route) unexpectedly refused: \(refusal)")
        }

        let productionFiles = try productionSourceFiles()
        let kernelSource = try String(
            contentsOf: productionFiles.first { $0.lastPathComponent == "EditorTransactionKernel.swift" }!,
            encoding: .utf8
        )
        #expect(!kernelSource.contains("EditorSemanticWorker"))
        #expect(!kernelSource.contains("DispatchTime"))
        #expect(!kernelSource.contains("UndoManager"))
        let nonKernel = try productionFiles
            .filter {
                ![
                    "EditorTransactionKernel.swift",
                    "DocumentActionInterface.swift",
                    "MarkdownDocument.swift"
                ].contains($0.lastPathComponent)
            }
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")
        #expect(!nonKernel.contains("commitSourceMutation("))

        let sourceEditor = try String(contentsOf: productionFiles.first { $0.lastPathComponent == "SourceEditor.swift" }!, encoding: .utf8)
        let wysiwygEditor = try String(contentsOf: productionFiles.first { $0.lastPathComponent == "WYSIWYGEditor.swift" }!, encoding: .utf8)
        let imagePlacement = try String(contentsOf: productionFiles.first { $0.lastPathComponent == "ImagePlacementController.swift" }!, encoding: .utf8)
        #expect(!sourceEditor.contains("SemanticEditEngine.plan("))
        #expect(!wysiwygEditor.contains("SemanticEditEngine.plan("))
        #expect(!imagePlacement.contains("SemanticEditEngine.plan("))
        #expect(sourceEditor.contains("EditorInput.sourceReplacement"))
        #expect(wysiwygEditor.contains("inputRoute: .wysiwygReplacement"))
        #expect(wysiwygEditor.contains("inputRoute: .markedText"))
        #expect(wysiwygEditor.contains("inputRoute: .checkbox"))
        #expect(wysiwygEditor.contains("EditorInput.markedText"))
        #expect(imagePlacement.contains("EditorInput.imageReference"))
        #expect(!sourceEditor.contains("closeTypingUndoGroup"))
        #expect(!wysiwygEditor.contains("beginUndoGrouping"))
        #expect(!wysiwygEditor.contains("closeTypingUndoGroup"))
    }
}
