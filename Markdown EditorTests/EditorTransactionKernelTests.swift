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
    // Verifies: REQ-052/083/084/086/087/093/094 — every native callback route has one owner,
    // an explicit accepted origin set, and one allowed state transition.
    @Test func nativeCallbackContractIsClosed() {
        let expected: [EditorInputRoute: EditorInputContract] = [
            .sourceReplacement: EditorInputContract(
                owner: .sourceEditor,
                acceptedOrigins: [.nativeUserInput],
                transition: .sourceMutation
            ),
            .wysiwygReplacement: EditorInputContract(
                owner: .wysiwygEditor,
                acceptedOrigins: [.nativeUserInput],
                transition: .sourceAndPresentationMutation
            ),
            .markedText: EditorInputContract(
                owner: .compositionCoordinator,
                acceptedOrigins: [.nativeUserInput, .composition],
                transition: .compositionLifecycle
            ),
            .semanticCommand: EditorInputContract(
                owner: .commandController,
                acceptedOrigins: [.nativeUserInput],
                transition: .sourceAndPresentationMutation
            ),
            .checkbox: EditorInputContract(
                owner: .wysiwygEditor,
                acceptedOrigins: [.nativeUserInput],
                transition: .sourceAndPresentationMutation
            ),
            .imageReference: EditorInputContract(
                owner: .imagePlacement,
                acceptedOrigins: [.nativeUserInput],
                transition: .sourceMutation
            ),
            .undoRedo: EditorInputContract(
                owner: .documentUndoManager,
                acceptedOrigins: [.history],
                transition: .historyAndSelection
            ),
            .modeChange: EditorInputContract(
                owner: .editorSession,
                acceptedOrigins: [.nativeUserInput],
                transition: .modeState
            ),
            .reconciliation: EditorInputContract(
                owner: .editorHost,
                acceptedOrigins: [.nativeUserInput, .programmaticPresentation],
                transition: .reconciliation
            )
        ]

        #expect(Set(EditorInputRoute.allCases) == Set(expected.keys))
        for route in EditorInputRoute.allCases {
            #expect(route.contract == expected[route])
            #expect(!route.contract.acceptedOrigins.isEmpty)
        }
    }

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

    // Verifies: COR-70 — the main-actor owner revalidates an accepted transaction rather than
    // trusting a caller that forges a different mutation after kernel reduction.
    @Test func ownerRejectsForgedAcceptedTransactionBeforeMutation() {
        let document = MarkdownDocument()
        document.installTextForTesting("abc")
        let trace = InMemoryEditorTrace()
        document.trace = trace
        let state = EditorStateSnapshot(
            source: document.sourceSnapshot(),
            sourceSelection: SourceSelection(utf16: NSRange(location: 0, length: 0))
        )
        let mutation = SourceMutation(
            expectedRevision: state.source.sourceVersion,
            range: NSRange(location: 0, length: 0),
            expectedText: "",
            replacement: "X",
            selectionBefore: state.sourceSelection,
            selectionAfter: SourceSelection(utf16: NSRange(location: 1, length: 0)),
            actionName: "Typing",
            grouping: .typing
        )
        let forged = SourceMutation(
            expectedRevision: mutation.expectedRevision,
            range: mutation.range,
            expectedText: "not-current",
            replacement: mutation.replacement,
            selectionBefore: mutation.selectionBefore,
            selectionAfter: mutation.selectionAfter,
            actionName: mutation.actionName,
            grouping: mutation.grouping
        )
        let transaction = AcceptedEditorTransaction(
            route: .sourceReplacement,
            intentID: IntentID(rawValue: 0),
            effect: .edit(
                AcceptedEdit(
                    sourceMutation: forged,
                    presentationTransition: nil,
                    sourceSelectionAfter: forged.selectionAfter,
                    projectionSelectionAfter: nil,
                    intent: nil
                )
            )
        )
        #expect(document.commitEditorTransaction(transaction, state: state) == .refused(.contentMismatch))
        #expect(document.text == "abc")
        #expect(document.sourceVersion == state.source.sourceVersion)
        #expect(document.documentUndoManager?.canUndo == false)
        #expect(trace.events.contains {
            if case .mutationRefused = $0 { return true }
            return false
        })

        let markedState = EditorStateSnapshot(
            source: document.sourceSnapshot(),
            origin: .programmaticPresentation
        )
        let markedTransaction = AcceptedEditorTransaction(
            route: .markedText,
            intentID: markedState.intentID,
            effect: .markedText(.update)
        )
        #expect(document.commitEditorTransaction(markedTransaction, state: markedState) == .refused(.invalidIdentity))

        let modeState = EditorStateSnapshot(source: document.sourceSnapshot())
        let forgedMode = AcceptedEditorTransaction(
            route: .modeChange,
            intentID: IntentID(rawValue: 1),
            effect: .modeChange(.wysiwyg)
        )
        #expect(document.commitEditorTransaction(forgedMode, state: modeState) == .refused(.invalidIdentity))

        var repeatedAudit = EditorTransactionReductionAudit()
        repeatedAudit.recordReduction()
        repeatedAudit.recordReduction()
        let validTransaction = AcceptedEditorTransaction(
            route: .sourceReplacement,
            intentID: state.intentID,
            effect: .edit(
                AcceptedEdit(
                    sourceMutation: mutation,
                    presentationTransition: nil,
                    sourceSelectionAfter: mutation.selectionAfter,
                    projectionSelectionAfter: nil,
                    intent: nil
                )
            )
        )
        #expect(document.commitEditorTransaction(validTransaction, state: state, audit: repeatedAudit) == .refused(.invalidIdentity))
    }

    // Verifies: COR-70 — a forged structural transition cannot pair one source result with a
    // different authoritative projection, and a checkbox transaction remains bound to its node.
    @Test(.serialized) func ownerRejectsForgedStructuralAndCheckboxTransactions() throws {
        let document = MarkdownDocument()
        document.installTextForTesting("hello\n")
        let session = EditorSession()
        session.attach(document: document)
        session.setMode(.wysiwyg)
        let tree = try #require(MarkdownParser.parse(document.text, sourceVersion: document.sourceVersion).get())
        session.installProjectionForTesting(
            MarkdownProjectionModel.build(
                tree: tree,
                index: MarkdownSourceIndex(source: document.text, sourceVersion: document.sourceVersion)
            ),
            tree: tree
        )
        let presentation = try #require(session.presentation)
        let selection = ProjectionSelection(
            utf16: NSRange(location: 0, length: 5),
            revision: presentation.projectionRevision
        )
        session.captureSelection(.projection(selection))
        let state = session.editorStateSnapshot()
        let request = EditorEditRequest(
            command: .setHeading(level: 2),
            selection: .projection(selection),
            expectedSourceRevision: SourceRevision(value: document.sourceVersion),
            grouping: .discrete
        )
        let planned = SemanticEditEngine.plan(
            request,
            snapshot: state.source,
            presentation: state.presentation,
            tree: state.tree,
            nextSnapshotID: state.nextPresentationID
        )
        guard case .accepted(let acceptedEdit) = planned else {
            Issue.record("heading fixture did not produce an accepted transition: \(planned)")
            return
        }
        let input = EditorInput.semanticCommand(
            EditorSemanticInput(request: request, plannedOutcome: planned)
        )
        var audit = EditorTransactionReductionAudit()
        guard case .accepted(let transaction) = EditorTransactionKernel.reduce(
            input,
            state: state,
            audit: &audit
        ) else {
            Issue.record("heading fixture was refused by the kernel")
            return
        }
        let forgedMutation = SourceMutation(
            expectedRevision: acceptedEdit.sourceMutation.expectedRevision,
            range: acceptedEdit.sourceMutation.range,
            expectedText: acceptedEdit.sourceMutation.expectedText,
            replacement: "forged",
            selectionBefore: acceptedEdit.sourceMutation.selectionBefore,
            selectionAfter: acceptedEdit.sourceMutation.selectionAfter,
            actionName: acceptedEdit.sourceMutation.actionName,
            grouping: acceptedEdit.sourceMutation.grouping
        )
        let forgedStructural = AcceptedEditorTransaction(
            route: transaction.route,
            intentID: transaction.intentID,
            request: transaction.request,
            effect: .edit(
                AcceptedEdit(
                    sourceMutation: forgedMutation,
                    presentationTransition: acceptedEdit.presentationTransition,
                    sourceSelectionAfter: acceptedEdit.sourceSelectionAfter,
                    projectionSelectionAfter: acceptedEdit.projectionSelectionAfter,
                    intent: acceptedEdit.intent
                )
            )
        )
        #expect(document.commitEditorTransaction(forgedStructural, state: state, audit: audit) == .refused(.invalidIdentity))
        #expect(document.text == "hello\n")

        let missingSourceResultTransition = PresentationTransition(
            fromSnapshotID: acceptedEdit.presentationTransition!.fromSnapshotID,
            nextSnapshot: acceptedEdit.presentationTransition!.nextSnapshot,
            projectionReplacementRange: acceptedEdit.presentationTransition!.projectionReplacementRange,
            projectionReplacement: acceptedEdit.presentationTransition!.projectionReplacement,
            selectionAfter: acceptedEdit.presentationTransition!.selectionAfter
        )
        let missingSourceResult = AcceptedEditorTransaction(
            route: transaction.route,
            intentID: transaction.intentID,
            request: transaction.request,
            effect: .edit(
                AcceptedEdit(
                    sourceMutation: acceptedEdit.sourceMutation,
                    presentationTransition: missingSourceResultTransition,
                    sourceSelectionAfter: acceptedEdit.sourceSelectionAfter,
                    projectionSelectionAfter: acceptedEdit.projectionSelectionAfter,
                    intent: acceptedEdit.intent
                )
            )
        )
        #expect(document.commitEditorTransaction(missingSourceResult, state: state, audit: audit) == .refused(.invalidIdentity))
        #expect(document.text == "hello\n")
        session.detach()

        let taskDocument = MarkdownDocument()
        taskDocument.installTextForTesting("- [ ] task\n")
        let taskSession = EditorSession()
        taskSession.attach(document: taskDocument)
        taskSession.setMode(.wysiwyg)
        let taskTree = try #require(MarkdownParser.parse(taskDocument.text, sourceVersion: taskDocument.sourceVersion).get())
        taskSession.installProjectionForTesting(
            MarkdownProjectionModel.build(
                tree: taskTree,
                index: MarkdownSourceIndex(source: taskDocument.text, sourceVersion: taskDocument.sourceVersion)
            ),
            tree: taskTree
        )
        let taskPresentation = try #require(taskSession.presentation)
        let taskAttachment = try #require(taskPresentation.attachments.first)
        let taskSelection = ProjectionSelection(
            utf16: NSRange(location: taskAttachment.utf16Location, length: 1),
            revision: taskPresentation.projectionRevision
        )
        taskSession.captureSelection(.projection(taskSelection))
        let taskState = taskSession.editorStateSnapshot()
        let taskRequest = EditorEditRequest(
            command: .toggleTask(nodeID: taskAttachment.nodeID),
            selection: .projection(taskSelection),
            expectedSourceRevision: SourceRevision(value: taskDocument.sourceVersion),
            grouping: .discrete
        )
        let taskPlanned = SemanticEditEngine.plan(
            taskRequest,
            snapshot: taskState.source,
            presentation: taskState.presentation,
            tree: taskState.tree,
            nextSnapshotID: taskState.nextPresentationID
        )
        let taskInput = EditorInput.checkbox(
            EditorSemanticInput(request: taskRequest, plannedOutcome: taskPlanned)
        )
        var taskAudit = EditorTransactionReductionAudit()
        guard case .accepted(let taskTransaction) = EditorTransactionKernel.reduce(
            taskInput,
            state: taskState,
            audit: &taskAudit
        ) else {
            Issue.record("checkbox fixture was refused by the kernel")
            return
        }
        let forgedCheckbox = AcceptedEditorTransaction(
            route: taskTransaction.route,
            intentID: taskTransaction.intentID,
            request: taskTransaction.request,
            checkboxNodeID: MarkdownNodeID(rawValue: taskAttachment.nodeID.rawValue &+ 1),
            effect: taskTransaction.effect
        )
        #expect(taskDocument.commitEditorTransaction(forgedCheckbox, state: taskState, audit: taskAudit) == .refused(.invalidIdentity))
        #expect(taskDocument.text == "- [ ] task\n")
        taskSession.detach()
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

    // Verifies: COR-70 — the real projection, marked-text, image, mode, reconciliation, and
    // history entry points all use the owner transaction seam; the adapter never applies a
    // second source mutation of its own.
    @Test(.serialized) func realAdapterRoutesUseTheKernelOwnerSeam() throws {
        let document = MarkdownDocument()
        document.installTextForTesting("hi\n")
        let trace = InMemoryEditorTrace()
        document.trace = trace
        let session = EditorSession()
        session.attach(document: document)
        let tree = try #require(MarkdownParser.parse(document.text, sourceVersion: document.sourceVersion).get())
        session.installProjectionForTesting(
            MarkdownProjectionModel.build(
                tree: tree,
                index: MarkdownSourceIndex(source: document.text, sourceVersion: document.sourceVersion)
            ),
            tree: tree
        )
        let coordinator = WYSIWYGEditor.Coordinator(
            document: document,
            session: session,
            placementController: ImagePlacementController()
        )
        let textView = MarkdownWYSIWYGTextView(usingTextLayoutManager: false)
        textView.delegate = coordinator
        textView.session = session
        textView.documentActions = document
        textView.inputCoordinator = coordinator.input
        textView.adapterCoordinator = coordinator
        coordinator.textView = textView
        coordinator.applyProjectionIfNeeded(reason: .reapplyIfDrift)
        let firstPresentation = try #require(session.presentation)
        let firstSelection = ProjectionSelection(
            utf16: NSRange(location: 0, length: 0),
            revision: firstPresentation.projectionRevision
        )
        textView.setSelectedRange(firstSelection.range.utf16)
        session.captureSelection(.projection(firstSelection))
        let beforeProjection = trace.events.filter {
            if case .mutationCommitted = $0 { return true }
            return false
        }.count
        #expect(coordinator.textView(textView, shouldChangeTextIn: firstSelection.range.utf16, replacementString: "X") == false)
        #expect(document.text == "Xhi\n")
        #expect(trace.events.filter {
            if case .mutationCommitted = $0 { return true }
            return false
        }.count - beforeProjection == 1)

        // The native marked-text callback enters the transient route before it can commit.
        textView.setSelectedRange(NSRange(location: 1, length: 0))
        textView.setMarkedText(
            "日",
            selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: 1, length: 0)
        )
        #expect(trace.events.contains {
            if case .compositionBegan = $0 { return true }
            return false
        })
        textView.unmarkText()
        textView.unmarkText()
        #expect(trace.events.contains {
            if case .compositionCancelled = $0 { return true }
            return false
        })

        // The source image adapter is a production entry point, not a test-only document helper.
        let imageDocument = MarkdownDocument()
        imageDocument.installTextForTesting("x")
        let imageTrace = InMemoryEditorTrace()
        imageDocument.trace = imageTrace
        let imageSession = EditorSession()
        imageSession.attach(document: imageDocument)
        imageSession.captureSelection(.source(SourceSelection(utf16: NSRange(location: 1, length: 0))))
        let imagePlacement = ImagePlacementController()
        imagePlacement.attach(actions: imageDocument)
        let imageCoordinator = SourceEditor.Coordinator(
            document: imageDocument,
            placementController: imagePlacement,
            session: imageSession
        )
        let imageView = MarkdownSourceTextView(usingTextLayoutManager: false)
        imageView.documentActions = imageDocument
        imageView.sourceCoordinator = imageCoordinator
        imageCoordinator.textView = imageView
        imageView.string = imageDocument.text
        imageView.setSelectedRange(NSRange(location: 1, length: 0))
        imageSession.captureSelection(.source(
            SourceSelection(
                utf16: imageView.selectedRange(),
                affinity: imageView.selectionAffinity == .upstream ? .upstream : .downstream
            )
        ))
        imageView.insertImageMarkdown("![](a.png)", at: NSRange(location: 1, length: 0), selectEmptyDescription: false)
        #expect(imageDocument.text == "x![](a.png)", "wired image route events: \(imageTrace.events)")
        #expect(imageTrace.events.contains {
            if case .mutationCommitted = $0 { return true }
            return false
        })
        imageSession.detach()

        // Mode and reconciliation are also owner-approved transactions, not direct state writes.
        session.setMode(.source)
        session.setMode(.wysiwyg)
        if let presentation = session.presentation {
            session.installPresentation(
                presentation,
                tree: session.authoritativeTree,
                provisional: false
            )
        }
        #expect(trace.events.contains {
            if case .modeToggle = $0 { return true }
            return false
        })

        imageDocument.undoManager?.undo()
        #expect(imageDocument.text == "x")
        #expect(imageTrace.events.contains {
            if case .historyApplied = $0 { return true }
            return false
        }, "wired image undo events: \(imageTrace.events)")
        session.detach()
    }

    // Verifies: COR-70 — the WYSIWYG checkbox callback performs one owner transaction on its
    // own fixture, without composition or projection edits sharing AppKit transient state.
    @Test(.serialized) func realCheckboxAdapterRouteUsesKernelOwnerSeam() throws {
        let taskDocument = MarkdownDocument()
        taskDocument.installTextForTesting("- [ ] task\n")
        let taskTrace = InMemoryEditorTrace()
        taskDocument.trace = taskTrace
        let taskSession = EditorSession()
        taskSession.attach(document: taskDocument)
        taskSession.setMode(.wysiwyg)
        let taskTree = try #require(MarkdownParser.parse(taskDocument.text, sourceVersion: taskDocument.sourceVersion).get())
        taskSession.installProjectionForTesting(
            MarkdownProjectionModel.build(
                tree: taskTree,
                index: MarkdownSourceIndex(source: taskDocument.text, sourceVersion: taskDocument.sourceVersion)
            ),
            tree: taskTree
        )
        let taskView = MarkdownWYSIWYGTextView(usingTextLayoutManager: false)
        taskView.session = taskSession
        taskView.documentActions = taskDocument
        let taskAttachment = try #require(taskSession.presentation?.attachments.first {
            if case .task = $0.kind { return true }
            return false
        })
        let taskSelection = ProjectionSelection(
            utf16: NSRange(location: taskAttachment.utf16Location, length: 1),
            revision: try #require(taskSession.presentation).projectionRevision
        )
        taskView.setSelectedRange(taskSelection.range.utf16)
        taskSession.captureSelection(.projection(taskSelection))
        #expect(taskSession.wysiwygModeState.selection == taskSelection)
        let toggled = taskView.toggleTask(atUTF16: taskAttachment.utf16Location)
        #expect(toggled, "task route refused; text=\(taskDocument.text), events=\(taskTrace.events)")
        #expect(taskDocument.text == "- [x] task\n")
        taskSession.detach()
    }

    // Verifies: COR-70 — the closed input matrix is executed through the document owner, not
    // merely searched for in production source text.
    @Test func everyInputRouteUsesEditorTransactionKernel() {
        for route in EditorInputRoute.allCases {
            if route == .checkbox {
                let taskDocument = MarkdownDocument()
                taskDocument.installTextForTesting("- [ ] task\n")
                let taskSession = EditorSession()
                taskSession.attach(document: taskDocument)
                taskSession.setMode(.wysiwyg)
                let taskTree = MarkdownParser.parse(
                    taskDocument.text,
                    sourceVersion: taskDocument.sourceVersion
                ).get()!
                taskSession.installProjectionForTesting(
                    MarkdownProjectionModel.build(
                        tree: taskTree,
                        index: MarkdownSourceIndex(
                            source: taskDocument.text,
                            sourceVersion: taskDocument.sourceVersion
                        )
                    ),
                    tree: taskTree
                )
                let taskPresentation = taskSession.presentation!
                let taskAttachment = taskPresentation.attachments.first {
                    if case .task = $0.kind { return true }
                    return false
                }!
                let taskSelection = ProjectionSelection(
                    utf16: NSRange(location: taskAttachment.utf16Location, length: 1),
                    revision: taskPresentation.projectionRevision
                )
                taskSession.captureSelection(.projection(taskSelection))
                let taskState = taskSession.editorStateSnapshot()
                let taskRequest = EditorEditRequest(
                    command: .toggleTask(nodeID: taskAttachment.nodeID),
                    selection: .projection(taskSelection),
                    expectedSourceRevision: SourceRevision(value: taskDocument.sourceVersion),
                    grouping: .discrete
                )
                let taskInput = EditorInput.checkbox(
                    EditorSemanticInput(
                        request: taskRequest,
                        plannedOutcome: SemanticEditEngine.plan(
                            taskRequest,
                            snapshot: taskDocument.sourceSnapshot(),
                            presentation: taskPresentation,
                            tree: taskTree,
                            nextSnapshotID: taskState.nextPresentationID
                        )
                    )
                )
                switch taskDocument.commitEditorInput(taskInput, state: taskState) {
                case .committed(let transaction):
                    #expect(transaction.route == route)
                case .refused(let refusal):
                    Issue.record("closed input route \(route) unexpectedly refused: \(refusal)")
                }
                #expect(taskDocument.text == "- [x] task\n")
                taskSession.detach()
                taskDocument.close()
                continue
            }
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
                for phase in EditorMarkedTextInput.Phase.allCases {
                    let phaseDocument = MarkdownDocument()
                    phaseDocument.installTextForTesting("a")
                    defer { phaseDocument.close() }
                    let phaseSource = phaseDocument.sourceSnapshot()
                    let markedInput = EditorInput.markedText(EditorMarkedTextInput(
                        phase: phase,
                        request: phase == .commit ? request : nil,
                        sourceRevision: SourceRevision(value: phaseSource.sourceVersion),
                        plannedOutcome: phase == .commit ? plannedOutcome : nil
                    ))
                    let markedResult = phaseDocument.commitEditorInput(
                        markedInput,
                        state: EditorStateSnapshot(
                            source: phaseSource,
                            sourceSelection: selection
                        )
                    )
                    switch phase {
                    case .update, .cancel, .commit:
                        switch markedResult {
                        case .committed:
                            break
                        case .refused(let refusal):
                            Issue.record("marked-text phase \(phase) unexpectedly refused: \(refusal)")
                        }
                    }
                }
                continue
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
            let trace = InMemoryEditorTrace()
            document.trace = trace
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
            #expect(trace.events.contains {
                if case .editRefused = $0 { return true }
                if case .mutationRefused = $0 { return true }
                if case .historyRefused = $0 { return true }
                return false
            })
        }
    }

    // Verifies: COR-70 — refusal leaves the owning session's presentation, selections, intent
    // route, and diagnostic refusal observable unchanged together with canonical source.
    @Test func sessionRefusalLeavesAllOwnerStateUnchanged() {
        let document = MarkdownDocument()
        document.installTextForTesting("abc")
        let trace = InMemoryEditorTrace()
        document.trace = trace
        let session = EditorSession()
        session.attach(document: document)
        let sourceSelection = SourceSelection(utf16: NSRange(location: 1, length: 0))
        session.captureSelection(.source(sourceSelection))
        let sourceBefore = document.sourceSnapshot()
        let sourceStateBefore = session.sourceModeState
        let wysiwygStateBefore = session.wysiwygModeState
        let result = session.perform(
            .insertText("x"),
            selection: .source(sourceSelection),
            expectedSourceRevision: SourceRevision(value: sourceBefore.sourceVersion &+ 1)
        )
        #expect(result == .refused(.staleVersion))
        #expect(document.sourceSnapshot() == sourceBefore)
        #expect(session.sourceModeState == sourceStateBefore)
        #expect(session.wysiwygModeState == wysiwygStateBefore)
        #expect(trace.events.contains {
            if case .editRefused = $0 { return true }
            return false
        })
        session.detach()
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
