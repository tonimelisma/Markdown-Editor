//
//  LocalTransitionDomain.swift
//  Markdown Editor
//

import Foundation

/// Closed classification for the synchronous WYSIWYG input boundary.
///
/// // REQ-090/091/092; ARC-005/008/009: ordinary native input either uses the exact local
/// /// identity/atomic route or refuses before the document owner is reached. Adding a new
/// /// projection atom requires a corresponding matrix case here and in LocalTransitionTests.
nonisolated enum LocalTransitionClass: String, CaseIterable, Sendable {
    case identityText
    case atomicText
    case syntheticInsertion
    case tableCell
    case taskMarker
    case uneditable
    case mixed
    case crossCell
    case ambiguous
}

nonisolated enum LocalTransitionDomain {
    /// Maps every classifier outcome into the closed class set. Associated identity is retained
    /// by the classifier and re-derived by the existing semantic planner; this enum owns only
    /// the route decision, never a second coordinate representation.
    static func classify(_ selection: ProjectionSelectionClass) -> LocalTransitionClass {
        switch selection {
        case .identityText: return .identityText
        case .atomicText: return .atomicText
        case .syntheticInsertion: return .syntheticInsertion
        case .tableCell: return .tableCell
        case .taskMarker: return .taskMarker
        case .uneditable: return .uneditable
        case .mixed: return .mixed
        case .crossCell: return .crossCell
        case .ambiguous: return .ambiguous
        }
    }

    /// Plans only the classes proven by Stage 0 to be identity/atomic local transitions. The
    /// existing semantic planner is pure here: it performs source-range and literal-encoding
    /// work but does not enter the parser worker. Any transition that asks for an authoritative
    /// source result is refused by this callback route rather than silently doing whole-document
    /// work on the main actor.
    static func plan(
        _ request: EditorEditRequest,
        snapshot: SourceSnapshot,
        presentation: PresentationSnapshot,
        tree: MarkdownTree?,
        nextSnapshotID: PresentationSnapshot.ID,
        intent: IntentContext? = nil
    ) -> EditorEditOutcome {
        let isTypingCommand: Bool
        switch request.command {
        case .insertText, .deleteBackward:
            isTypingCommand = true
        default:
            isTypingCommand = false
        }
        guard isTypingCommand,
              case .projection(let projectionSelection) = request.selection else {
            return .refused(.unsupportedCommand)
        }
        let classification = ProjectionSelectionClassifier.classify(
            selection: projectionSelection.range.utf16,
            affinity: projectionSelection.affinity,
            snapshot: presentation
        )
        switch classify(classification) {
        case .identityText, .atomicText:
            let planned = SemanticEditEngine.plan(
                request,
                snapshot: snapshot,
                presentation: presentation,
                tree: tree,
                nextSnapshotID: nextSnapshotID,
                intent: intent
            )
            guard case .accepted(let edit) = planned,
                  let transition = edit.presentationTransition,
                  transition.sourceAfter == nil else {
                return .refused(.unprovable)
            }
            return .accepted(edit)
        case .syntheticInsertion:
            return .refused(.unprovable)
        case .tableCell, .taskMarker, .uneditable:
            return .refused(.unsupportedCommand)
        case .mixed, .crossCell, .ambiguous:
            return .refused(.ambiguousSelection)
        }
    }
}
