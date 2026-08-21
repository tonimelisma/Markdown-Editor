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

nonisolated enum LocalTransitionRoute: Sendable, Equatable {
    case local
    case bounded
    case refusal
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

    /// The route decision is explicit for every associated classifier outcome. Synthetic
    /// insertion at source boundaries is the list-marker case selected by Stage 0; paragraph,
    /// soft/hard-break, image, and other source-location synthetic units remain refusal cases.
    static func route(for selection: ProjectionSelectionClass) -> LocalTransitionRoute {
        switch selection {
        case .identityText, .atomicText:
            return .local
        case .syntheticInsertion(let policy):
            if case .atSourceBoundaries = policy { return .local }
            return .refusal
        case .tableCell:
            return .bounded
        case .taskMarker, .uneditable, .mixed, .crossCell, .ambiguous:
            return .refusal
        }
    }

    /// Plans only the classes proven by Stage 0 to be identity/atomic local transitions. This
    /// route deliberately calls the WYSIWYG source mapper and literal encoder directly: the
    /// candidate-proof helper is authoritative reconciliation work and is not allowed to hide a
    /// whole-document parser behind an ordinary native callback.
    static func plan(
        _ request: EditorEditRequest,
        snapshot: SourceSnapshot,
        presentation: PresentationSnapshot,
        tree: MarkdownTree?,
        nextSnapshotID: PresentationSnapshot.ID,
        intent: IntentContext? = nil,
        classification: ProjectionSelectionClass? = nil
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
        let classification = classification ?? ProjectionSelectionClassifier.classify(
            selection: projectionSelection.range.utf16,
            affinity: projectionSelection.affinity,
            snapshot: presentation
        )
        let transitionRange: NSRange
        let planningClassification: ProjectionSelectionClass
        if case .deleteBackward = request.command, projectionSelection.range.utf16.length == 0 {
            guard projectionSelection.range.utf16.location > 0 else {
                return .refused(.unsupportedCommand)
            }
            transitionRange = (presentation.renderedString as NSString).rangeOfComposedCharacterSequence(
                at: projectionSelection.range.utf16.location - 1
            )
            planningClassification = ProjectionSelectionClassifier.classify(
                selection: transitionRange,
                affinity: projectionSelection.affinity,
                snapshot: presentation
            )
        } else {
            transitionRange = projectionSelection.range.utf16
            planningClassification = classification
        }
        switch route(for: planningClassification) {
        case .local:
            guard case .mutation(let mutation) = WYSIWYGPlanningDomain.applyWYSIWYG(
                command: request.command,
                selection: projectionSelection,
                snapshot: snapshot,
                presentation: presentation,
                tree: tree,
                grouping: request.grouping,
                intent: intent,
                classification: planningClassification
            ) else {
                return .refused(.unprovable)
            }
            let encodedMutation: SourceMutation
            switch request.command {
            case .insertText(let text) where !text.isEmpty:
                let context = LiteralEncodeContext(
                    intendedVisibleText: text,
                    precedingSourceCharacter: SemanticEditEngine.precedingCharacter(
                        snapshot: snapshot,
                        range: mutation.range
                    ),
                    followingSourceCharacter: SemanticEditEngine.followingCharacter(
                        snapshot: snapshot,
                        range: mutation.range
                    ),
                    atLineStart: SemanticEditEngine.isAtLineStart(
                        snapshot: snapshot,
                        location: mutation.range.location
                    ),
                    container: SemanticEditEngine.container(for: planningClassification),
                    dialect: .formalGFM
                )
                guard case .encoded(let sourceSpelling) = MarkdownLiteralEncoder.encode(context),
                      localLiteralIsSafe(
                          visible: text,
                          encoded: sourceSpelling,
                          context: context,
                          snapshot: snapshot,
                          range: mutation.range,
                          classification: planningClassification
                      ),
                      let remade = SourceMutation.exact(
                          snapshot: snapshot,
                          range: mutation.range,
                          replacement: sourceSpelling,
                          selectionBefore: mutation.selectionBefore,
                          actionName: mutation.actionName,
                          grouping: mutation.grouping
                      ) else {
                    return .refused(.unprovable)
                }
                encodedMutation = remade
            default:
                encodedMutation = mutation
            }
            let planned = SemanticEditEngine.finishIdentityTransition(
                mutation: encodedMutation,
                presentation: presentation,
                projectionRange: transitionRange,
                visibleReplacement: {
                    if case .insertText(let text) = request.command { return text }
                    return ""
                }(),
                nextSnapshotID: nextSnapshotID,
                affinity: projectionSelection.affinity,
                proof: .locallyProven,
                intent: intent
            )
            guard case .accepted(let edit) = planned,
                  let transition = edit.presentationTransition,
                  transition.sourceAfter == nil else {
                return .refused(.unprovable)
            }
            return .accepted(edit)
        case .bounded:
            guard case .tableCell(_, let cellSource, let body) = planningClassification else {
                return .refused(.unprovable)
            }
            return planBoundedTableCell(
                request,
                selection: projectionSelection,
                cellSource: cellSource,
                body: body,
                snapshot: snapshot,
                presentation: presentation,
                nextSnapshotID: nextSnapshotID,
                intent: intent
            )
        case .refusal:
            return .refused(.unsupportedCommand)
        }
    }

    private static func localLiteralIsSafe(
        visible: String,
        encoded: String,
        context: LiteralEncodeContext,
        snapshot: SourceSnapshot,
        range: NSRange,
        classification: ProjectionSelectionClass
    ) -> Bool {
        // Existing atomic spans already carry a concrete inverse. The local identity route has
        // no parser oracle, so refuse a candidate whose neighboring source punctuation could join
        // the new characters into a different entity or delimiter construct.
        if case .atomicText = classification { return true }
        if context.precedingSourceCharacter == "&" || context.followingSourceCharacter == ";" {
            return false
        }
        let ns = snapshot.text as NSString
        let neighboring = [
            context.precedingSourceCharacter,
            context.followingSourceCharacter
        ].compactMap { $0 }
        if neighboring.contains(where: { "\\[]`*_~!<>|".contains($0) }) && encoded == visible {
            return false
        }
        guard range.location >= 0, NSMaxRange(range) <= ns.length else { return false }
        return !visible.contains(where: { $0 == "\n" || $0 == "\r" })
    }

    /// Table cells are a bounded structural domain: the cell's raw source is the only source
    /// region allowed to change, and the oracle checks the cell grammar without reparsing the
    /// document. The authoritative parser still reconciles the resulting source asynchronously.
    private static func planBoundedTableCell(
        _ request: EditorEditRequest,
        selection: ProjectionSelection,
        cellSource: NSRange,
        body: NSRange,
        snapshot: SourceSnapshot,
        presentation: PresentationSnapshot,
        nextSnapshotID: PresentationSnapshot.ID,
        intent: IntentContext?
    ) -> EditorEditOutcome {
        let commandText: String
        let deleting: Bool
        switch request.command {
        case .insertText(let text):
            commandText = text
            deleting = false
        case .deleteBackward:
            commandText = ""
            deleting = true
        default:
            return .refused(.unsupportedCommand)
        }

        var editedProjection = selection.range.utf16
        let rendered = presentation.renderedString as NSString
        if deleting, editedProjection.length == 0 {
            guard editedProjection.location > body.location else {
                return .refused(.unsupportedCommand)
            }
            editedProjection = rendered.rangeOfComposedCharacterSequence(at: editedProjection.location - 1)
        }
        guard editedProjection.location >= body.location,
              NSMaxRange(editedProjection) <= NSMaxRange(body) else {
            return .refused(.mappingFailure)
        }

        guard let sourceRange = sourceRange(
            for: editedProjection,
            selection: selection,
            body: body,
            snapshot: snapshot,
            presentation: presentation
        ) else {
            return .refused(.mappingFailure)
        }

        let sourceReplacement: String
        if commandText.isEmpty {
            sourceReplacement = ""
        } else {
            let context = LiteralEncodeContext(
                intendedVisibleText: commandText,
                precedingSourceCharacter: SemanticEditEngine.precedingCharacter(snapshot: snapshot, range: sourceRange),
                followingSourceCharacter: SemanticEditEngine.followingCharacter(snapshot: snapshot, range: sourceRange),
                atLineStart: false,
                container: .tableCell,
                dialect: .formalGFM
            )
            guard case .encoded(let encoded) = MarkdownLiteralEncoder.encode(context) else {
                return .refused(.unprovable)
            }
            sourceReplacement = encoded
        }
        guard let mutation = SourceMutation.exact(
            snapshot: snapshot,
            range: sourceRange,
            replacement: sourceReplacement,
            selectionBefore: SourceSelection(utf16: sourceRange, affinity: selection.affinity),
            actionName: "Typing",
            grouping: request.grouping
        ), boundedCellOracle(
            mutation: mutation,
            cellSource: cellSource,
            snapshot: snapshot
        ) else {
            return .refused(.unprovable)
        }

        let planned = SemanticEditEngine.finishIdentityTransition(
            mutation: mutation,
            presentation: presentation,
            projectionRange: editedProjection,
            visibleReplacement: commandText,
            nextSnapshotID: nextSnapshotID,
            affinity: selection.affinity,
            proof: .boundedLocallyProven,
            intent: intent
        )
        guard case .accepted(let edit) = planned,
              let transition = edit.presentationTransition,
              transition.sourceAfter == nil else {
            return .refused(.unprovable)
        }
        return .accepted(edit)
    }

    private static func sourceRange(
        for editedProjection: NSRange,
        selection: ProjectionSelection,
        body: NSRange,
        snapshot: SourceSnapshot,
        presentation: PresentationSnapshot
    ) -> NSRange? {
        switch presentation.coordinateMap.sourceRange(
            forProjection: editedProjection,
            affinity: selection.affinity
        ) {
        case .exact(let range):
            return range
        case .refused:
            let cellText = presentation.renderedString as NSString
            guard body.location >= 0, NSMaxRange(body) <= cellText.length else { return nil }
            let local = NSRange(
                location: editedProjection.location - body.location,
                length: editedProjection.length
            )
            guard let cell = presentation.tables.flatMap(\.cells).first(where: {
                $0.utf16Range == NSRange(location: body.location, length: body.length)
            }), let cellSource = cell.sourceUTF16Range else { return nil }
            let ns = snapshot.text as NSString
            guard NSMaxRange(cellSource) <= ns.length else { return nil }
            return WYSIWYGPlanningDomain.mapProjectedCellRangeToSource(
                projected: local,
                sourceCell: ns.substring(with: cellSource)
            ).map { NSRange(location: cellSource.location + $0.location, length: $0.length) }
        }
    }

    private static func boundedCellOracle(
        mutation: SourceMutation,
        cellSource: NSRange,
        snapshot: SourceSnapshot,
    ) -> Bool {
        let source = snapshot.text as NSString
        guard cellSource.location >= 0,
              cellSource.length >= 0,
              NSMaxRange(cellSource) <= source.length,
              mutation.range.location >= cellSource.location,
              NSMaxRange(mutation.range) <= NSMaxRange(cellSource) else { return false }
        let local = NSRange(
            location: mutation.range.location - cellSource.location,
            length: mutation.range.length
        )
        let cellText = (source.substring(with: cellSource) as NSString)
            .replacingCharacters(in: local, with: mutation.replacement)
        guard !cellText.contains("\n"), !cellText.contains("\r") else { return false }
        var escaped = false
        for character in cellText {
            if character == "\\" {
                escaped.toggle()
            } else {
                if character == "|" && !escaped { return false }
                escaped = false
            }
        }
        return true
    }
}
