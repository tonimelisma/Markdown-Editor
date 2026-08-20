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

        let commandMismatch = SourceMutation(
            expectedRevision: state.source.sourceVersion,
            range: NSRange(location: 0, length: 0),
            expectedText: "",
            replacement: "Y",
            selectionBefore: selection,
            selectionAfter: SourceSelection(utf16: NSRange(location: 1, length: 0)),
            actionName: "Typing",
            grouping: .typing
        )
        let commandMismatchResult = EditorTransactionKernel.reduce(
            .semanticCommand(
                EditorSemanticInput(
                    request: request,
                    plannedOutcome: .accepted(
                        AcceptedEdit(
                            sourceMutation: commandMismatch,
                            presentationTransition: nil,
                            sourceSelectionAfter: commandMismatch.selectionAfter,
                            projectionSelectionAfter: nil,
                            intent: nil
                        )
                    )
                )
            ),
            state: state
        )
        #expect(commandMismatchResult == .refused(.contentMismatch))

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
        let textView = MarkdownSourceTextView(usingTextLayoutManager: false)
        textView.documentActions = document
        coordinator.textView = textView
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
        // The native selection callback owns the pre-edit identity; the mutation cannot invent it.
        session.captureSelection(.source(mutation.selectionBefore))
        textView.setSelectedRange(mutation.selectionBefore.range.utf16)
        let accepted = coordinator.textView(
            textView,
            shouldChangeTextIn: mutation.range,
            replacementString: mutation.replacement
        )
        guard accepted else {
            Issue.record("real source delegate route refused the exact mutation")
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

    // Verifies: COR-70 — the window-scoped command route performs one kernel commit and does not
    // recapture its own request as owner selection.
    @Test func realCommandRouteUsesKernelCommitExactlyOnce() {
        let document = MarkdownDocument()
        document.installTextForTesting("hello\n")
        let trace = InMemoryEditorTrace()
        document.trace = trace
        let session = EditorSession()
        session.attach(document: document)
        session.setMode(.source)
        session.captureSelection(.source(
            SourceSelection(utf16: NSRange(location: 0, length: 5))
        ))
        let controller = EditorCommandController()
        controller.bind(
            document: document,
            session: session,
            actionRouter: EditorActionRouter(),
            window: nil
        )
        let before = trace.events.filter {
            if case .mutationCommitted = $0 { return true }
            return false
        }.count

        #expect(controller.perform(.bold) == .accepted)
        #expect(document.text == "**hello**\n")
        #expect(trace.events.filter {
            if case .mutationCommitted = $0 { return true }
            return false
        }.count - before == 1)
        session.detach()
    }

    // Verifies: COR-70 — the closed input matrix is executed through the document owner, not
    // merely searched for in production source text.
    @Test func everyInputRouteUsesEditorTransactionKernel() {
        for route in EditorInputRoute.allCases {
            let document = MarkdownDocument()
            defer { document.close() }
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
            if route == .undoRedo {
                let trace = InMemoryEditorTrace()
                document.trace = trace
                let setup = document.commitEditorInput(
                    .sourceReplacement(EditorReplacementInput(mutation: mutation)),
                    state: state
                )
                #expect({
                    if case .committed = setup { return true }
                    return false
                }())
                document.undoManager?.undo()
                #expect(document.text == "a")
                #expect(trace.events.contains {
                    if case .historyApplied = $0 { return true }
                    return false
                })
                continue
            }
            let result = document.commitEditorInput(input, state: state)
            switch result {
            case .committed(let transaction):
                #expect(transaction.route == route)
            case .refused(let refusal):
                Issue.record("closed input route \(route) unexpectedly refused: \(refusal)")
            }

            switch route {
            case .sourceReplacement, .wysiwygReplacement, .semanticCommand, .checkbox, .imageReference:
                #expect(document.text == "xa")
            case .undoRedo:
                #expect(document.text == "")
            case .markedText, .modeChange, .reconciliation:
                #expect(document.text == "a")
            }
        }
    }

    // Verifies: COR-70 — a stale immutable state cannot make a live document accept an old edit.
    @Test func staleStateRefusesBeforeApplyingTheMutation() {
        let document = MarkdownDocument()
        defer { document.close() }
        document.installTextForTesting("a")
        let stale = EditorStateSnapshot(
            source: document.sourceSnapshot(),
            sourceSelection: SourceSelection(utf16: NSRange(location: 0, length: 0))
        )
        document.installTextForTesting("new")
        let mutation = SourceMutation(
            expectedRevision: stale.source.sourceVersion,
            range: NSRange(location: 0, length: 1),
            expectedText: "a",
            replacement: "x",
            selectionBefore: stale.sourceSelection,
            selectionAfter: SourceSelection(utf16: NSRange(location: 1, length: 0)),
            actionName: "Stale",
            grouping: .discrete
        )
        let input = EditorInput.sourceReplacement(
            EditorReplacementInput(
                mutation: mutation,
                selectionIdentity: .source(stale.sourceSelection)
            )
        )

        let result = document.commitEditorInput(input, state: stale)

        #expect(result == .refused(.staleVersion))
        #expect(document.text == "new")
        #expect(document.sourceVersion == 0)
    }

    // Verifies: COR-70 — the refusal matrix is typed and leaves the canonical owner untouched.
    @Test func refusalMatrixLeavesOwnerUnchanged() {
        let selection = SourceSelection(utf16: NSRange(location: 0, length: 0))
        let source = SourceSnapshot(text: "abc", sourceVersion: 0, locationGeneration: 0, fileURL: nil)
        func makeMutation(
            expectedRevision: UInt64 = 0,
            range: NSRange = NSRange(location: 0, length: 0),
            expectedText: String = "",
            selectionBefore: SourceSelection = selection
        ) -> SourceMutation {
            SourceMutation(
                expectedRevision: expectedRevision,
                range: range,
                expectedText: expectedText,
                replacement: "x",
                selectionBefore: selectionBefore,
                selectionAfter: SourceSelection(utf16: NSRange(location: 1, length: 0)),
                actionName: "Refusal",
                grouping: .discrete
            )
        }
        let request = EditorEditRequest(
            command: .insertText("x"),
            selection: .source(selection),
            expectedSourceRevision: SourceRevision(value: 0),
            grouping: .discrete
        )
        let cases: [(EditorInput, EditorRefusal, EditorUpdateOrigin)] = [
            (
                .sourceReplacement(
                    EditorReplacementInput(
                        mutation: makeMutation(expectedRevision: 1)
                    )
                ),
                .staleVersion,
                .nativeUserInput
            ),
            (
                .sourceReplacement(
                    EditorReplacementInput(
                        mutation: makeMutation(expectedText: "z")
                    )
                ),
                .contentMismatch,
                .nativeUserInput
            ),
            (
                .sourceReplacement(
                    EditorReplacementInput(
                        mutation: makeMutation(range: NSRange(location: 99, length: 0))
                    )
                ),
                .invalidRange,
                .nativeUserInput
            ),
            (
                .sourceReplacement(
                    EditorReplacementInput(
                        mutation: makeMutation(
                            selectionBefore: SourceSelection(utf16: NSRange(location: 1, length: 0))
                        ),
                        selectionIdentity: .source(SourceSelection(utf16: NSRange(location: 1, length: 0)))
                    )
                ),
                .ambiguousSelection,
                .nativeUserInput
            ),
            (
                .markedText(EditorMarkedTextInput(phase: .update)),
                .invalidIdentity,
                .programmaticPresentation
            ),
            (
                .markedText(EditorMarkedTextInput(phase: .update, projectionID: PresentationSnapshot.ID(value: 1))),
                .stalePresentation,
                .nativeUserInput
            ),
            (
                .semanticCommand(EditorSemanticInput(request: request)),
                .unavailable,
                .nativeUserInput
            ),
            (
                .semanticCommand(
                    EditorSemanticInput(request: request, plannedOutcome: .refused(.mixedDomain))
                ),
                .mixedDomain,
                .nativeUserInput
            ),
        ]

        for (input, expected, origin) in cases {
            let document = MarkdownDocument()
            defer { document.close() }
            document.installTextForTesting(source.text)
            let result = document.commitEditorInput(
                input,
                state: EditorStateSnapshot(
                    source: source,
                    origin: origin,
                    sourceSelection: selection
                )
            )
            #expect(result == .refused(expected))
            #expect(document.text == source.text)
            #expect(document.sourceVersion == source.sourceVersion)
            #expect(document.documentUndoManager?.canUndo == false)
        }
    }

    // Verifies: COR-70 — native source/image replacements cannot install an out-of-bounds caret.
    @Test func replacementRejectsOutOfBoundsSelection() {
        for route in [EditorInputRoute.sourceReplacement, .imageReference] {
            let document = MarkdownDocument()
            defer { document.close() }
            document.installTextForTesting("a")
            let source = document.sourceSnapshot()
            let before = SourceSelection(utf16: NSRange(location: 0, length: 0))
            let mutation = SourceMutation(
                expectedRevision: source.sourceVersion,
                range: NSRange(location: 0, length: 0),
                expectedText: "",
                replacement: "x",
                selectionBefore: before,
                selectionAfter: SourceSelection(utf16: NSRange(location: 99, length: 0)),
                actionName: "Invalid selection",
                grouping: .discrete
            )
            let input = route == .sourceReplacement
                ? EditorInput.sourceReplacement(EditorReplacementInput(mutation: mutation))
                : EditorInput.imageReference(EditorReplacementInput(mutation: mutation))

            let result = document.commitEditorInput(
                input,
                state: EditorStateSnapshot(source: source, sourceSelection: before)
            )

            #expect(result == .refused(.invalidIdentity))
            #expect(document.text == "a")
        }
    }
}
