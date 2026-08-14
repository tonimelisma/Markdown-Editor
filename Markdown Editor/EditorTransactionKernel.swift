//
//  EditorTransactionKernel.swift
//  Markdown Editor
//

import Foundation

/// The closed set of production inputs that can affect an editor transaction.
///
/// Keeping the route vocabulary separate from the payload lets tests enumerate the complete
/// matrix without manufacturing AppKit objects. A new route must be assigned an owner here
/// before it can enter production.
nonisolated enum EditorInputRoute: String, CaseIterable, Sendable, Equatable {
    case sourceReplacement
    case wysiwygReplacement
    case markedText
    case semanticCommand
    case checkbox
    case imageReference
    case undoRedo
    case modeChange
    case reconciliation
}

nonisolated struct EditorReplacementInput: Sendable, Equatable {
    let mutation: SourceMutation
    let intentID: IntentID

    init(mutation: SourceMutation, intentID: IntentID = IntentID(rawValue: 0)) {
        self.mutation = mutation
        self.intentID = intentID
    }
}

nonisolated struct EditorSemanticInput: Sendable, Equatable {
    let request: EditorEditRequest
    let intentID: IntentID

    init(request: EditorEditRequest, intentID: IntentID = IntentID(rawValue: 0)) {
        self.request = request
        self.intentID = intentID
    }
}

nonisolated struct EditorMarkedTextInput: Sendable, Equatable {
    enum Phase: String, CaseIterable, Sendable, Equatable {
        case update
        case commit
        case cancel
    }

    let phase: Phase
    let request: EditorEditRequest?
    let intentID: IntentID

    init(
        phase: Phase,
        request: EditorEditRequest? = nil,
        intentID: IntentID = IntentID(rawValue: 0)
    ) {
        self.phase = phase
        self.request = request
        self.intentID = intentID
    }
}

nonisolated struct EditorHistoryInput: Sendable, Equatable {
    let patch: HistoryPatch
    let direction: HistoryDirection
    let intentID: IntentID

    init(
        patch: HistoryPatch,
        direction: HistoryDirection,
        intentID: IntentID = IntentID(rawValue: 0)
    ) {
        self.patch = patch
        self.direction = direction
        self.intentID = intentID
    }
}

nonisolated struct EditorModeInput: Sendable, Equatable {
    let mode: EditorMode
    let intentID: IntentID

    init(mode: EditorMode, intentID: IntentID = IntentID(rawValue: 0)) {
        self.mode = mode
        self.intentID = intentID
    }
}

nonisolated struct EditorReconciliationInput: Sendable, Equatable {
    let sourceRevision: SourceRevision
    let locationGeneration: UInt64
    let projectionID: PresentationSnapshot.ID
    let intentID: IntentID

    init(
        sourceRevision: SourceRevision,
        locationGeneration: UInt64,
        projectionID: PresentationSnapshot.ID,
        intentID: IntentID = IntentID(rawValue: 0)
    ) {
        self.sourceRevision = sourceRevision
        self.locationGeneration = locationGeneration
        self.projectionID = projectionID
        self.intentID = intentID
    }
}

/// Immutable state captured before reduction. It contains no live document, text view, clock,
/// diagnostic sink, or filesystem handle.
nonisolated struct EditorStateSnapshot: Sendable, Equatable {
    let source: SourceSnapshot
    let mode: EditorMode
    let origin: EditorUpdateOrigin
    let sourceSelection: SourceSelection
    let projectionSelection: ProjectionSelection?
    let presentation: PresentationSnapshot?
    let tree: MarkdownTree?
    let intentID: IntentID
    let nextPresentationID: PresentationSnapshot.ID

    init(
        source: SourceSnapshot,
        mode: EditorMode = .source,
        origin: EditorUpdateOrigin = .nativeUserInput,
        sourceSelection: SourceSelection = SourceSelection(utf16: NSRange(location: 0, length: 0)),
        projectionSelection: ProjectionSelection? = nil,
        presentation: PresentationSnapshot? = nil,
        tree: MarkdownTree? = nil,
        intentID: IntentID = IntentID(rawValue: 0),
        nextPresentationID: PresentationSnapshot.ID = PresentationSnapshot.ID(value: 0)
    ) {
        self.source = source
        self.mode = mode
        self.origin = origin
        self.sourceSelection = sourceSelection
        self.projectionSelection = projectionSelection
        self.presentation = presentation
        self.tree = tree
        self.intentID = intentID
        self.nextPresentationID = nextPresentationID
    }
}

nonisolated enum EditorInput: Sendable, Equatable {
    case sourceReplacement(EditorReplacementInput)
    case wysiwygReplacement(EditorSemanticInput)
    case markedText(EditorMarkedTextInput)
    case semanticCommand(EditorSemanticInput)
    case checkbox(EditorSemanticInput)
    case imageReference(EditorReplacementInput)
    case undoRedo(EditorHistoryInput)
    case modeChange(EditorModeInput)
    case reconciliation(EditorReconciliationInput)

    var route: EditorInputRoute {
        switch self {
        case .sourceReplacement: return .sourceReplacement
        case .wysiwygReplacement: return .wysiwygReplacement
        case .markedText: return .markedText
        case .semanticCommand: return .semanticCommand
        case .checkbox: return .checkbox
        case .imageReference: return .imageReference
        case .undoRedo: return .undoRedo
        case .modeChange: return .modeChange
        case .reconciliation: return .reconciliation
        }
    }
}

nonisolated enum EditorTransactionEffect: Sendable, Equatable {
    case edit(AcceptedEdit)
    case markedText(EditorMarkedTextInput.Phase)
    case modeChange(EditorMode)
    case history(EditorHistoryInput)
    case reconciliation(EditorReconciliationInput)
}

/// A pure reduction result. The transaction is a description; it does not mutate anything.
nonisolated struct AcceptedEditorTransaction: Sendable, Equatable {
    let route: EditorInputRoute
    let intentID: IntentID
    let effect: EditorTransactionEffect
}

nonisolated enum EditorRefusal: Error, Sendable, Equatable, CaseIterable {
    case unavailable
    case staleVersion
    case stalePresentation
    case ambiguousSelection
    case unsupportedCommand
    case mappingFailure
    case invalidRange
    case mixedDomain
    case crossCell
    case unprovable
    case contentMismatch
    case invalidIdentity

    var asEditRefusal: EditRefusal {
        switch self {
        case .unavailable: return .unavailable
        case .staleVersion: return .staleVersion
        case .stalePresentation: return .stalePresentation
        case .ambiguousSelection: return .ambiguousSelection
        case .unsupportedCommand: return .unsupportedCommand
        case .mappingFailure: return .mappingFailure
        case .invalidRange: return .invalidRange
        case .mixedDomain: return .mixedDomain
        case .crossCell: return .crossCell
        case .unprovable: return .unprovable
        case .contentMismatch, .invalidIdentity: return .ambiguousSelection
        }
    }

    var asSourceRefusal: SourceEditRefusal {
        switch self {
        case .staleVersion: return .staleVersion
        case .invalidRange: return .invalidRange
        case .contentMismatch, .ambiguousSelection, .mixedDomain, .crossCell, .unprovable,
             .stalePresentation, .unsupportedCommand, .mappingFailure, .unavailable,
             .invalidIdentity:
            return .conflict
        }
    }
}

nonisolated enum EditorTransactionReduction: Sendable, Equatable {
    case accepted(AcceptedEditorTransaction)
    case refused(EditorRefusal)
}

/// Main-actor application result returned by a document/session owner after reduction.
nonisolated enum EditorTransactionCommitResult: Sendable, Equatable {
    case committed(AcceptedEditorTransaction)
    case refused(EditorRefusal)
}

/// Pure input-to-transaction reducer. AppKit, mutable documents, diagnostics, I/O, and clocks
/// are deliberately absent from this type.
nonisolated enum EditorTransactionKernel {
    static func reduce(
        _ input: EditorInput,
        state: EditorStateSnapshot
    ) -> EditorTransactionReduction {
        switch input {
        case .sourceReplacement(let value):
            return reduceSourceMutation(value, route: .sourceReplacement, state: state)
        case .imageReference(let value):
            return reduceSourceMutation(value, route: .imageReference, state: state)
        case .wysiwygReplacement(let value), .semanticCommand(let value), .checkbox(let value):
            return reduceSemantic(value, input: input, state: state)
        case .markedText(let value):
            guard state.origin == .composition || state.origin == .nativeUserInput else {
                return .refused(.invalidIdentity)
            }
            if value.phase == .commit {
                guard let request = value.request else { return .refused(.invalidIdentity) }
                return reduceSemantic(
                    EditorSemanticInput(request: request, intentID: value.intentID),
                    input: .semanticCommand(EditorSemanticInput(request: request, intentID: value.intentID)),
                    state: state
                )
            }
            return .accepted(
                AcceptedEditorTransaction(
                    route: .markedText,
                    intentID: value.intentID,
                    effect: .markedText(value.phase)
                )
            )
        case .undoRedo(let value):
            guard value.patch.matchesCurrentContent(in: state.source.text) else {
                return .refused(.contentMismatch)
            }
            guard value.patch.range.location >= 0,
                  value.patch.range.length >= 0 else {
                return .refused(.invalidRange)
            }
            return .accepted(
                AcceptedEditorTransaction(
                    route: .undoRedo,
                    intentID: value.intentID,
                    effect: .history(value)
                )
            )
        case .modeChange(let value):
            guard value.mode != state.mode else {
                return .accepted(
                    AcceptedEditorTransaction(
                        route: .modeChange,
                        intentID: value.intentID,
                        effect: .modeChange(value.mode)
                    )
                )
            }
            return .accepted(
                AcceptedEditorTransaction(
                    route: .modeChange,
                    intentID: value.intentID,
                    effect: .modeChange(value.mode)
                )
            )
        case .reconciliation(let value):
            guard value.sourceRevision.value == state.source.sourceVersion,
                  value.locationGeneration == state.source.locationGeneration else {
                return .refused(.staleVersion)
            }
            return .accepted(
                AcceptedEditorTransaction(
                    route: .reconciliation,
                    intentID: value.intentID,
                    effect: .reconciliation(value)
                )
            )
        }
    }

    private static func reduceSourceMutation(
        _ value: EditorReplacementInput,
        route: EditorInputRoute,
        state: EditorStateSnapshot
    ) -> EditorTransactionReduction {
        let mutation = value.mutation
        guard mutation.expectedRevision == state.source.sourceVersion else {
            return .refused(.staleVersion)
        }
        let source = state.source.text as NSString
        guard mutation.range.location >= 0,
              mutation.range.length >= 0,
              NSMaxRange(mutation.range) <= source.length else {
            return .refused(.invalidRange)
        }
        guard source.substring(with: mutation.range) == mutation.expectedText else {
            return .refused(.contentMismatch)
        }
        let edit = AcceptedEdit(
            sourceMutation: mutation,
            presentationTransition: nil,
            sourceSelectionAfter: mutation.selectionAfter,
            projectionSelectionAfter: nil,
            intent: nil
        )
        return .accepted(
            AcceptedEditorTransaction(
                route: route,
                intentID: value.intentID,
                effect: .edit(edit)
            )
        )
    }

    private static func reduceSemantic(
        _ value: EditorSemanticInput,
        input: EditorInput,
        state: EditorStateSnapshot
    ) -> EditorTransactionReduction {
        let request: EditorEditRequest
        switch input {
        case .checkbox:
            request = value.request
        default:
            request = value.request
        }
        let outcome = SemanticEditEngine.plan(
            request,
            snapshot: state.source,
            presentation: state.presentation,
            tree: state.tree,
            nextSnapshotID: state.nextPresentationID,
            intent: nil
        )
        switch outcome {
        case .accepted(let edit):
            return .accepted(
                AcceptedEditorTransaction(
                    route: input.route,
                    intentID: value.intentID,
                    effect: .edit(edit)
                )
            )
        case .refused(let refusal):
            return .refused(EditorRefusal(refusal))
        }
    }

}

private extension EditorRefusal {
    init(_ refusal: EditRefusal) {
        switch refusal {
        case .unavailable: self = .unavailable
        case .staleVersion: self = .staleVersion
        case .stalePresentation: self = .stalePresentation
        case .ambiguousSelection: self = .ambiguousSelection
        case .unsupportedCommand: self = .unsupportedCommand
        case .mappingFailure: self = .mappingFailure
        case .invalidRange: self = .invalidRange
        case .mixedDomain: self = .mixedDomain
        case .crossCell: self = .crossCell
        case .unprovable: self = .unprovable
        }
    }
}

extension AcceptedEdit {
    func withIntent(_ intent: IntentContext) -> AcceptedEdit {
        AcceptedEdit(
            sourceMutation: sourceMutation,
            presentationTransition: presentationTransition,
            sourceSelectionAfter: sourceSelectionAfter,
            projectionSelectionAfter: projectionSelectionAfter,
            intent: intent
        )
    }
}

extension EditorTransactionReduction {
    var acceptedTransaction: AcceptedEditorTransaction? {
        guard case .accepted(let transaction) = self else { return nil }
        return transaction
    }
}
