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
    let selectionIdentity: EditorSelection?
    let intentID: IntentID

    init(
        mutation: SourceMutation,
        selectionIdentity: EditorSelection? = nil,
        intentID: IntentID = IntentID(rawValue: 0)
    ) {
        self.mutation = mutation
        self.selectionIdentity = selectionIdentity
        self.intentID = intentID
    }
}

nonisolated struct EditorSemanticInput: Sendable, Equatable {
    let request: EditorEditRequest
    let plannedOutcome: EditorEditOutcome?
    let intentID: IntentID

    init(
        request: EditorEditRequest,
        plannedOutcome: EditorEditOutcome? = nil,
        intentID: IntentID = IntentID(rawValue: 0)
    ) {
        self.request = request
        self.plannedOutcome = plannedOutcome
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
    let sourceRevision: SourceRevision?
    let projectionID: PresentationSnapshot.ID?
    let plannedOutcome: EditorEditOutcome?
    let intentID: IntentID

    init(
        phase: Phase,
        request: EditorEditRequest? = nil,
        sourceRevision: SourceRevision? = nil,
        projectionID: PresentationSnapshot.ID? = nil,
        plannedOutcome: EditorEditOutcome? = nil,
        intentID: IntentID = IntentID(rawValue: 0)
    ) {
        self.phase = phase
        self.request = request
        self.sourceRevision = sourceRevision
        self.projectionID = projectionID
        self.plannedOutcome = plannedOutcome
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
    let expectedProjectionID: PresentationSnapshot.ID?
    let intentID: IntentID

    init(
        sourceRevision: SourceRevision,
        locationGeneration: UInt64,
        projectionID: PresentationSnapshot.ID,
        expectedProjectionID: PresentationSnapshot.ID? = nil,
        intentID: IntentID = IntentID(rawValue: 0)
    ) {
        self.sourceRevision = sourceRevision
        self.locationGeneration = locationGeneration
        self.projectionID = projectionID
        self.expectedProjectionID = expectedProjectionID
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

    var intentID: IntentID {
        switch self {
        case .sourceReplacement(let value), .imageReference(let value): return value.intentID
        case .wysiwygReplacement(let value), .semanticCommand(let value), .checkbox(let value):
            return value.intentID
        case .markedText(let value): return value.intentID
        case .undoRedo(let value): return value.intentID
        case .modeChange(let value): return value.intentID
        case .reconciliation(let value): return value.intentID
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
    let request: EditorEditRequest?
    let checkboxNodeID: MarkdownNodeID?
    let effect: EditorTransactionEffect

    init(
        route: EditorInputRoute,
        intentID: IntentID,
        request: EditorEditRequest? = nil,
        checkboxNodeID: MarkdownNodeID? = nil,
        effect: EditorTransactionEffect
    ) {
        self.route = route
        self.intentID = intentID
        self.request = request
        self.checkboxNodeID = checkboxNodeID
        self.effect = effect
    }
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
        case .contentMismatch:
            return .contentMismatch
        case .ambiguousSelection, .mixedDomain, .crossCell, .unprovable,
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

/// Caller-owned proof that a route performed one reduction before handing its result to the
/// document owner. The kernel remains free of diagnostics, clocks, and mutable document state.
nonisolated struct EditorTransactionReductionAudit: Sendable, Equatable {
    private(set) var count = 0

    mutating func recordReduction() {
        count &+= 1
    }
}

/// Main-actor application result returned by a document/session owner after reduction.
nonisolated enum EditorTransactionCommitResult: Sendable, Equatable {
    case committed(AcceptedEditorTransaction)
    case refused(EditorRefusal)
}

/// Pure input-to-transaction reducer. AppKit, mutable documents, diagnostics, I/O, and clocks
/// are deliberately absent from this type.
nonisolated enum EditorTransactionKernel {
    /// Revalidates a reduced transaction at the mutable owner boundary. Reduction validates the
    /// caller's immutable snapshot; this second validation prevents a forged or stale accepted
    /// value from becoming a document mutation merely because its source snapshot still matches.
    static func validateAcceptedTransaction(
        _ transaction: AcceptedEditorTransaction,
        state: EditorStateSnapshot
    ) -> EditorRefusal? {
        guard transaction.intentID == state.intentID else { return .invalidIdentity }
        switch (transaction.route, transaction.effect) {
        case (.sourceReplacement, .edit(let edit)), (.imageReference, .edit(let edit)):
            return validateSourceEdit(edit, state: state, requiresSourceSelection: true)
        case (.wysiwygReplacement, .edit(let edit)),
             (.semanticCommand, .edit(let edit)),
             (.markedText, .edit(let edit)):
            guard let request = transaction.request,
                  requestSelectionMatchesOwner(request.selection, state: state) else {
                return .invalidIdentity
            }
            return validateAcceptedEdit(edit, request: request, state: state)
        case (.checkbox, .edit(let edit)):
            guard let request = transaction.request,
                  requestSelectionMatchesOwner(request.selection, state: state),
                  let nodeID = transaction.checkboxNodeID,
                  case .toggleTask = request.command else {
                return .invalidIdentity
            }
            if let refusal = validateAcceptedEdit(edit, request: request, state: state) {
                return refusal
            }
            return validateCheckboxEdit(edit, nodeID: nodeID, state: state)
        case (.markedText, .markedText(let phase)):
            guard state.origin == .composition || state.origin == .nativeUserInput else {
                return .invalidIdentity
            }
            switch phase {
            case .update, .commit, .cancel:
                return nil
            }
        case (.undoRedo, .history(let input)):
            guard input.patch.matchesCurrentContent(in: state.source.text),
                  input.patch.range.location >= 0,
                  input.patch.range.length >= 0,
                  NSMaxRange(input.patch.range) <= (state.source.text as NSString).length else {
                return .contentMismatch
            }
            return nil
        case (.modeChange, .modeChange(let mode)):
            guard mode == .source || mode == .wysiwyg else { return .invalidIdentity }
            return nil
        case (.reconciliation, .reconciliation(let input)):
            guard input.sourceRevision.value == state.source.sourceVersion,
                  input.locationGeneration == state.source.locationGeneration,
                  input.expectedProjectionID == nil || input.expectedProjectionID == state.presentation?.id else {
                return .staleVersion
            }
            return nil
        default:
            return .invalidIdentity
        }
    }

    private static func validateSourceEdit(
        _ edit: AcceptedEdit,
        state: EditorStateSnapshot,
        requiresSourceSelection: Bool
    ) -> EditorRefusal? {
        let mutation = edit.sourceMutation
        let source = state.source.text as NSString
        guard mutation.expectedRevision == state.source.sourceVersion else { return .staleVersion }
        guard mutation.range.location >= 0,
              mutation.range.length >= 0,
              NSMaxRange(mutation.range) <= source.length else { return .invalidRange }
        guard source.substring(with: mutation.range) == mutation.expectedText else { return .contentMismatch }
        guard mutation.selectionAfter == edit.sourceSelectionAfter else { return .invalidIdentity }
        let nextLength = source.length - mutation.range.length + (mutation.replacement as NSString).length
        guard mutation.selectionAfter.range.utf16.location >= 0,
              mutation.selectionAfter.range.utf16.length >= 0,
              NSMaxRange(mutation.selectionAfter.range.utf16) <= nextLength else { return .invalidIdentity }

        if requiresSourceSelection || state.projectionSelection == nil {
            guard mutation.selectionBefore == state.sourceSelection,
                  edit.presentationTransition == nil,
                  edit.projectionSelectionAfter == nil else {
                return .invalidIdentity
            }
            return nil
        }

        guard let presentation = state.presentation,
              let currentSelection = state.projectionSelection,
              currentSelection.range.revision.snapshotID == presentation.id,
              mutation.selectionBefore.affinity == currentSelection.affinity else {
            return .invalidIdentity
        }

        guard let transition = edit.presentationTransition else {
            return .invalidIdentity
        }
        guard transition.fromSnapshotID == presentation.id,
              transition.nextSnapshot.id == state.nextPresentationID,
              transition.nextSnapshot.sourceRevision.value == state.source.sourceVersion &+ 1,
              transition.nextSnapshot.locationGeneration == state.source.locationGeneration,
              transition.nextSnapshot.sourceUTF16Count == nextLength,
              transition.nextSnapshot.isOracleValid,
              let projectionSelectionAfter = edit.projectionSelectionAfter,
              projectionSelectionAfter == transition.selectionAfter,
              projectionSelectionAfter.range.revision.snapshotID == transition.nextSnapshot.id,
              transition.selectionAfter.range.revision.snapshotID == transition.nextSnapshot.id else {
            return .invalidIdentity
        }
        let rendered = presentation.renderedString as NSString
        guard transition.projectionReplacementRange.location >= 0,
              transition.projectionReplacementRange.length >= 0,
              NSMaxRange(transition.projectionReplacementRange) <= rendered.length,
              NSMaxRange(projectionSelectionAfter.range.utf16)
                <= (transition.nextSnapshot.renderedString as NSString).length else {
            return .invalidRange
        }

        // A literal replacement uses the selected projection range directly. Structural
        // commands intentionally replace a larger semantic block, so their source mutation can
        // include delimiters outside the selection. In both cases the live snapshot identity
        // and affinity are bound above; exact coordinate mapping is required whenever the
        // transition claims to replace exactly what the caller selected, while a structural
        // transition must at least cover that selection (including a caret at either boundary).
        if transition.projectionReplacementRange == currentSelection.range.utf16 {
            guard case .exact(let sourceRange) = presentation.coordinateMap.sourceRange(
                forProjection: currentSelection.range.utf16,
                affinity: currentSelection.affinity
            ), sourceRange == mutation.range else {
                return .invalidIdentity
            }
        } else {
            let selected = currentSelection.range.utf16
            let replacement = transition.projectionReplacementRange
            let selectedStart = selected.location
            let selectedEnd = NSMaxRange(selected)
            let replacementStart = replacement.location
            let replacementEnd = NSMaxRange(replacement)
            guard selectedStart >= replacementStart,
                  selectedEnd <= replacementEnd
                    || (selected.length == 0
                        && (selectedStart == replacementStart || selectedStart == replacementEnd)) else {
                return .invalidIdentity
            }
        }

        let projected = rendered.replacingCharacters(
            in: transition.projectionReplacementRange,
            with: transition.projectionReplacement
        )
        guard projected == transition.nextSnapshot.renderedString else { return .invalidIdentity }
        return nil
    }

    private static func validateCheckboxEdit(
        _ edit: AcceptedEdit,
        nodeID: MarkdownNodeID,
        state: EditorStateSnapshot
    ) -> EditorRefusal? {
        guard let presentation = state.presentation,
              let selection = state.projectionSelection,
              selection.range.revision.snapshotID == presentation.id,
              selection.range.utf16.length == 1,
              let attachment = presentation.attachments.first(where: {
                  $0.utf16Location == selection.range.utf16.location
              }), attachment.nodeID == nodeID,
              case .task(let checked, _) = attachment.kind,
              let itemSource = attachment.sourceUTF16Range,
              let markerRange = StructuralSourceSpans.taskMarkerRange(
                  itemSource: itemSource,
                  source: state.source.text,
                  currentlyChecked: checked
              ) else {
            return .invalidIdentity
        }
        let mutation = edit.sourceMutation
        guard mutation.range == markerRange,
              mutation.expectedText == (state.source.text as NSString).substring(with: markerRange),
              mutation.replacement == (checked ? "[ ]" : "[x]") else {
            return .invalidIdentity
        }
        guard let transition = edit.presentationTransition,
              let nextAttachment = transition.nextSnapshot.attachments.first(where: {
                  $0.nodeID == nodeID
              }),
              nextAttachment.sourceUTF16Range == itemSource,
              case .task(let nextChecked, _) = nextAttachment.kind,
              nextChecked != checked else {
            return .invalidIdentity
        }
        return nil
    }

    static func reduce(
        _ input: EditorInput,
        state: EditorStateSnapshot
    ) -> EditorTransactionReduction {
        var audit = EditorTransactionReductionAudit()
        return reduce(input, state: state, audit: &audit)
    }

    static func reduce(
        _ input: EditorInput,
        state: EditorStateSnapshot,
        audit: inout EditorTransactionReductionAudit
    ) -> EditorTransactionReduction {
        audit.recordReduction()
        return reduceCore(input, state: state)
    }

    private static func reduceCore(
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
            guard value.sourceRevision == nil
                || value.sourceRevision == SourceRevision(value: state.source.sourceVersion) else {
                return .refused(.staleVersion)
            }
            guard value.projectionID == nil || value.projectionID == state.presentation?.id else {
                return .refused(.stalePresentation)
            }
            if value.phase == .commit {
                guard let request = value.request else { return .refused(.invalidIdentity) }
                return reduceSemantic(
                    EditorSemanticInput(
                        request: request,
                        plannedOutcome: value.plannedOutcome,
                        intentID: value.intentID
                    ),
                    input: .markedText(value),
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
                  value.locationGeneration == state.source.locationGeneration,
                  value.expectedProjectionID == nil || value.expectedProjectionID == state.presentation?.id else {
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
        if let selectionIdentity = value.selectionIdentity {
            guard selectionIdentity.matches(state) else { return .refused(.ambiguousSelection) }
            if route != .imageReference,
               case .projection(let projectionSelection) = selectionIdentity {
                guard mutation.selectionBefore.affinity == projectionSelection.affinity else {
                    return .refused(.ambiguousSelection)
                }
            }
        } else if route != .imageReference {
            guard mutation.selectionBefore == state.sourceSelection else {
                return .refused(.ambiguousSelection)
            }
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
        let nextSourceLength = source.length - mutation.range.length
            + (mutation.replacement as NSString).length
        guard mutation.selectionAfter.range.utf16.location >= 0,
              mutation.selectionAfter.range.utf16.length >= 0,
              NSMaxRange(mutation.selectionAfter.range.utf16) <= nextSourceLength else {
            return .refused(.invalidIdentity)
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
        guard value.request.expectedSourceRevision.value == state.source.sourceVersion else {
            return .refused(.staleVersion)
        }
        guard requestSelectionMatchesOwner(value.request.selection, state: state) else {
            return .refused(.ambiguousSelection)
        }
        let outcome = value.plannedOutcome
        guard let outcome else { return .refused(.unavailable) }
        switch outcome {
        case .accepted(let edit):
            guard let refusal = validateAcceptedEdit(edit, request: value.request, state: state) else {
            return .accepted(
            AcceptedEditorTransaction(
                route: input.route,
                intentID: value.intentID,
                request: value.request,
                checkboxNodeID: {
                    guard input.route == .checkbox,
                          case .toggleTask(let nodeID) = value.request.command else { return nil }
                    return nodeID
                }(),
                effect: .edit(edit)
            )
        )
            }
            return .refused(refusal)
        case .refused(let refusal):
            return .refused(EditorRefusal(refusal))
        }
    }

    private static func requestSelectionMatchesOwner(
        _ selection: EditorSelection,
        state: EditorStateSnapshot
    ) -> Bool {
        switch selection {
        case .source(let value):
            return value == state.sourceSelection
        case .projection(let value):
            return value == state.projectionSelection
        }
    }

    /// Validate the immutable result produced before reduction. The kernel cannot re-run the
    /// semantic planner (that would reintroduce worker/clock work), but it can and must reject a
    /// result whose content, identity, revision, selection, or presentation transition does not
    /// correspond to the request and captured owner state.
    private static func validateAcceptedEdit(
        _ edit: AcceptedEdit,
        request: EditorEditRequest,
        state: EditorStateSnapshot
    ) -> EditorRefusal? {
        let mutation = edit.sourceMutation
        guard mutation.expectedRevision == state.source.sourceVersion else {
            return .staleVersion
        }
        guard mutation.grouping == request.grouping else {
            return .invalidIdentity
        }
        let source = state.source.text as NSString
        guard mutation.range.location >= 0,
              mutation.range.length >= 0,
              NSMaxRange(mutation.range) <= source.length else {
            return .invalidRange
        }
        guard source.substring(with: mutation.range) == mutation.expectedText else {
            return .contentMismatch
        }
        guard mutation.selectionAfter == edit.sourceSelectionAfter else {
            return .invalidIdentity
        }
        let nextSourceLength = source.length - mutation.range.length
            + (mutation.replacement as NSString).length
        guard mutation.selectionAfter.range.utf16.location >= 0,
              mutation.selectionAfter.range.utf16.length >= 0,
              NSMaxRange(mutation.selectionAfter.range.utf16) <= nextSourceLength else {
            return .invalidIdentity
        }

        switch request.selection {
        case .source(let selection):
            guard mutation.selectionBefore == selection,
                  edit.presentationTransition == nil,
                  edit.projectionSelectionAfter == nil else {
                return .invalidIdentity
            }
            switch request.command {
            case .insertText(let text):
                guard mutation.replacement == text else { return .contentMismatch }
            case .deleteBackward:
                guard mutation.replacement.isEmpty else { return .contentMismatch }
            default:
                break
            }
        case .projection(let selection):
            guard let presentation = state.presentation,
                  presentation.sourceRevision.value == state.source.sourceVersion,
                  presentation.locationGeneration == state.source.locationGeneration,
                  presentation.id == selection.range.revision.snapshotID,
                  mutation.selectionBefore.affinity == selection.affinity,
                  let transition = edit.presentationTransition else {
                return .stalePresentation
            }
            guard transition.fromSnapshotID == presentation.id,
                  transition.nextSnapshot.id == state.nextPresentationID,
                  transition.nextSnapshot.sourceRevision.value == state.source.sourceVersion &+ 1,
                  transition.nextSnapshot.locationGeneration == state.source.locationGeneration,
                  transition.nextSnapshot.sourceUTF16Count == nextSourceLength,
                  transition.nextSnapshot.isOracleValid,
                  let projectionSelectionAfter = edit.projectionSelectionAfter,
                  projectionSelectionAfter == transition.selectionAfter,
                  projectionSelectionAfter.range.revision.snapshotID == transition.nextSnapshot.id,
                  transition.selectionAfter.range.revision.snapshotID == transition.nextSnapshot.id else {
                return .invalidIdentity
            }
            let rendered = presentation.renderedString as NSString
            guard transition.projectionReplacementRange.location >= 0,
                  transition.projectionReplacementRange.length >= 0,
                  NSMaxRange(transition.projectionReplacementRange) <= rendered.length,
                  projectionSelectionAfter.range.utf16.location >= 0,
                  projectionSelectionAfter.range.utf16.length >= 0,
                  NSMaxRange(projectionSelectionAfter.range.utf16)
                    <= (transition.nextSnapshot.renderedString as NSString).length else {
                return .invalidRange
            }

            // COR-71 architecture boundary: a local identity transition carries its atom/range
            // preservation proof from the planner. Reconstructing the complete rendered string
            // here would turn the native callback back into a whole-document scan. The common
            // source, revision, identity, and selection checks above remain mandatory; the local
            // proof only replaces the redundant rendered-string equality checks below.
            if transition.proof == .localIdentity {
                let selected = selection.range.utf16
                let replacement = transition.projectionReplacementRange
                let selectedWithinReplacement: Bool
                if selected.length == 0 {
                    selectedWithinReplacement = selected.location >= replacement.location
                        && selected.location <= NSMaxRange(replacement)
                } else {
                    selectedWithinReplacement = selected.location >= replacement.location
                        && NSMaxRange(selected) <= NSMaxRange(replacement)
                }
                guard selectedWithinReplacement else { return .invalidIdentity }
                switch request.command {
                case .insertText(let text):
                    guard transition.projectionReplacement == text else { return .contentMismatch }
                case .deleteBackward:
                    guard transition.projectionReplacement.isEmpty else { return .contentMismatch }
                default:
                    return .invalidIdentity
                }
                return nil
            }

            let projected = rendered.replacingCharacters(
                in: transition.projectionReplacementRange,
                with: transition.projectionReplacement
            )
            guard projected == transition.nextSnapshot.renderedString else {
                return .invalidIdentity
            }
            switch request.command {
            case .insertText(let text):
                if transition.projectionReplacementRange == selection.range.utf16 {
                    guard case .exact(let sourceRange) = presentation.coordinateMap.sourceRange(
                        forProjection: selection.range.utf16,
                        affinity: selection.affinity
                    ), mutation.range == sourceRange else {
                        return .ambiguousSelection
                    }
                }
                let expected = (presentation.renderedString as NSString).replacingCharacters(
                    in: selection.range.utf16,
                    with: text
                )
                if transition.projectionReplacementRange == selection.range.utf16 {
                    guard transition.projectionReplacement == text else { return .contentMismatch }
                } else {
                    guard transition.nextSnapshot.renderedString == expected else { return .contentMismatch }
                }
            case .deleteBackward:
                if transition.projectionReplacementRange == selection.range.utf16 {
                    guard case .exact(let sourceRange) = presentation.coordinateMap.sourceRange(
                        forProjection: selection.range.utf16,
                        affinity: selection.affinity
                    ), mutation.range == sourceRange else {
                        return .ambiguousSelection
                    }
                }
                var deletionRange = selection.range.utf16
                if deletionRange.length == 0 {
                    guard deletionRange.location > 0 else { return .invalidRange }
                    deletionRange = rendered.rangeOfComposedCharacterSequence(
                        at: deletionRange.location - 1
                    )
                }
                let expected = (presentation.renderedString as NSString).replacingCharacters(
                    in: deletionRange,
                    with: ""
                )
                if transition.projectionReplacementRange == selection.range.utf16 {
                    guard transition.projectionReplacement.isEmpty else { return .contentMismatch }
                } else {
            guard transition.nextSnapshot.renderedString == expected else { return .contentMismatch }
                }
            default:
                break
            }

            let requiresAuthoritativeSourceResult: Bool
            switch request.command {
            case .insertText, .deleteBackward:
                // These commands may use a proven identity splice.  When their planner needs a
                // structural rebuild it still supplies sourceAfter below.
                requiresAuthoritativeSourceResult = false
            default:
                // Every formatting, block, task, table, and image command changes semantic
                // structure.  Its owner-boundary proof must therefore bind the source result to
                // the next presentation snapshot; a nil optional is not an accepted shortcut.
                requiresAuthoritativeSourceResult = true
            }
            guard !requiresAuthoritativeSourceResult || transition.sourceAfter != nil else {
                return .invalidIdentity
            }
            if let sourceAfter = transition.sourceAfter {
                let expectedSourceAfter = (state.source.text as NSString).replacingCharacters(
                    in: mutation.range,
                    with: mutation.replacement
                )
                guard sourceAfter == expectedSourceAfter,
                      let rebuilt = AuthoritativePresentationBuilder.build(
                          source: sourceAfter,
                          sourceRevision: transition.nextSnapshot.sourceRevision.value,
                          snapshotID: transition.nextSnapshot.id,
                          locationGeneration: transition.nextSnapshot.locationGeneration,
                          intent: edit.intent
                      ), rebuilt == transition.nextSnapshot else {
                    return .invalidIdentity
                }
            }
        }
        return nil
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

private extension EditorSelection {
    func matches(_ state: EditorStateSnapshot) -> Bool {
        switch self {
        case .source(let selection):
            return selection == state.sourceSelection
        case .projection(let selection):
            return selection == state.projectionSelection
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
