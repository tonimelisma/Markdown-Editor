//
//  SemanticEditEngine.swift
//  Markdown Editor
//

import Foundation

nonisolated enum SemanticCommand: Sendable, Equatable {
    case insertText(String)
    case deleteBackward
    case toggleBold
    case toggleItalic
    case toggleStrikethrough
    case toggleInlineCode
    case setParagraph
    case setHeading(level: Int)
    case toggleOrderedList
    case toggleUnorderedList
    case toggleTaskList
    case toggleBlockQuote
    case toggleCodeBlock
    case setLink(destination: String?)
    case toggleTask(nodeID: MarkdownNodeID)
    case replaceTableCell(nodeID: MarkdownNodeID, text: String)
    case insertImageMarkdown(String)
}

extension SemanticCommand {
    /// True for commands whose planner rewrites the caret's entire source line.
    ///
    /// // REQ-113/087; ARC-009: these may act only on a proven identity selection. Inline
    /// // commands wrap the selected span instead and are not restricted here.
    var reshapesWholeLine: Bool {
        switch self {
        case .setParagraph, .setHeading, .toggleOrderedList, .toggleUnorderedList,
             .toggleTaskList, .toggleBlockQuote, .toggleCodeBlock:
            return true
        case .toggleBold, .toggleItalic, .toggleStrikethrough, .toggleInlineCode, .setLink,
             .insertText, .deleteBackward, .toggleTask, .replaceTableCell, .insertImageMarkdown:
            return false
        }
    }
}

nonisolated enum SemanticEditRefusal: Error, Sendable, Equatable {
    case staleVersion
    case ambiguousSelection
    case unsupportedCommand
    case mappingFailure
    case invalidRange
}

nonisolated enum SemanticEditResult: Sendable, Equatable {
    /// Complete content-validated mutation ready for `commitSourceMutation`.
    case mutation(SourceMutation)
    case refused(SemanticEditRefusal)
}

/// Pure semantic → source translation. Never mutates document state.
///
/// // REQ-057/058/078–080/083/087: preserve spelling when safe; smallest unit rewrite; typed refusal.
nonisolated enum SemanticEditEngine {
    /// Plan an accepted edit including a provisional presentation transition when required.
    ///
    /// // REQ-091; ARC-005: WYSIWYG acceptance carries source mutation + presentation together.
    static func plan(
        _ request: EditorEditRequest,
        snapshot: SourceSnapshot,
        presentation: PresentationSnapshot?,
        tree: MarkdownTree?,
        nextSnapshotID: PresentationSnapshot.ID
    ) -> EditorEditOutcome {
        guard request.expectedSourceRevision.value == snapshot.sourceVersion else {
            return .refused(.staleVersion)
        }

        let plannedMutation = apply(
            request,
            snapshot: snapshot,
            presentation: presentation,
            tree: tree
        )
        switch plannedMutation {
        case .refused(let refusal):
            return .refused(mapRefusal(refusal))
        case .mutation(let mutation):
            switch request.selection {
            case .source:
                return .accepted(
                    AcceptedEdit(
                        sourceMutation: mutation,
                        presentationTransition: nil,
                        sourceSelectionAfter: mutation.selectionAfter,
                        projectionSelectionAfter: nil
                    )
                )
            case .projection(let projSel):
                guard let presentation else { return .refused(.unavailable) }
                guard presentation.id == projSel.range.revision.snapshotID else {
                    return .refused(.stalePresentation)
                }
                guard presentation.sourceRevision.value == snapshot.sourceVersion else {
                    return .refused(.stalePresentation)
                }

                let classification = ProjectionSelectionClassifier.classify(
                    selection: projSel.range.utf16,
                    affinity: projSel.affinity,
                    snapshot: presentation
                )
                let transitionRange = projSel.range.utf16
                let replacement: String
                switch request.command {
                case .insertText(let text):
                    replacement = text
                case .deleteBackward:
                    replacement = ""
                case .replaceTableCell(_, let text):
                    // Table cell planner replaces whole cell source; use projected body rewrite.
                    replacement = text
                default:
                    // For semantic formatting, build next snapshot from the post-mutation source
                    // synchronously when the tree/source metadata already supports it.
                    return planAuthoritativeTransition(
                        mutation: mutation,
                        snapshot: snapshot,
                        presentation: presentation,
                        nextSnapshotID: nextSnapshotID,
                        affinity: projSel.affinity,
                        taskNodeID: {
                            if case .toggleTask(let nodeID) = request.command { return nodeID }
                            return nil
                        }()
                    )
                }

                let visibleReplacement = replacement
                if case .tableCell(_, _, let projectionBody) = classification {
                    guard let tableEdit = WYSIWYGPlanningDomain.tablePresentationEdit(
                        command: request.command,
                        selection: projSel.range.utf16,
                        body: projectionBody,
                        rendered: presentation.renderedString
                    ) else {
                        return .refused(.unprovable)
                    }
                    return planAuthoritativeTransition(
                        mutation: mutation,
                        snapshot: snapshot,
                        presentation: presentation,
                        nextSnapshotID: nextSnapshotID,
                        affinity: projSel.affinity,
                        projectionSelectionLocation: tableEdit.selectionLocation
                    )
                }

                if case .insertText(let text) = request.command, !text.isEmpty {
                    switch classification {
                    case .identityText, .atomicText, .syntheticInsertion:
                        let encodeCtx = LiteralEncodeContext(
                            intendedVisibleText: text,
                            precedingSourceCharacter: precedingCharacter(snapshot: snapshot, range: mutation.range),
                            followingSourceCharacter: followingCharacter(snapshot: snapshot, range: mutation.range),
                            atLineStart: isAtLineStart(snapshot: snapshot, location: mutation.range.location),
                            container: container(for: classification),
                            dialect: .formalGFM
                        )
                        switch MarkdownLiteralEncoder.encode(encodeCtx) {
                        case .encoded(let sourceSpelling):
                            guard let remade = SourceMutation.exact(
                                snapshot: snapshot,
                                range: mutation.range,
                                replacement: sourceSpelling,
                                selectionBefore: mutation.selectionBefore,
                                actionName: mutation.actionName,
                                grouping: mutation.grouping
                            ) else {
                                return .refused(.invalidRange)
                            }
                            switch WYSIWYGPlanningDomain.literalCandidateProof(
                                mutation: remade,
                                snapshot: snapshot,
                                presentation: presentation,
                                projectionRange: projSel.range.utf16,
                                visibleReplacement: text,
                                nextSnapshotID: nextSnapshotID
                            ) {
                            case .preservesPresentation:
                                return finishIdentityTransition(
                                    mutation: remade,
                                    presentation: presentation,
                                    projectionRange: transitionRange,
                                    visibleReplacement: text,
                                    nextSnapshotID: nextSnapshotID,
                                    affinity: projSel.affinity
                                )
                            case .changesPresentation:
                                break
                            case .unbuildable:
                                return .refused(.unprovable)
                            }
                            guard let contextual = WYSIWYGPlanningDomain.contextualLiteralMutation(
                                original: mutation,
                                encodedInsertion: sourceSpelling,
                                snapshot: snapshot,
                                presentation: presentation,
                                projectionRange: projSel.range.utf16,
                                visibleReplacement: text,
                                nextSnapshotID: nextSnapshotID
                            ) else {
                                return .refused(.unprovable)
                            }
                            return planAuthoritativeTransition(
                                mutation: contextual.mutation,
                                snapshot: snapshot,
                                presentation: presentation,
                                nextSnapshotID: nextSnapshotID,
                                affinity: projSel.affinity,
                                prebuilt: contextual.built
                            )
                        case .refused:
                            return .refused(.unprovable)
                        }
                    case .tableCell:
                        // Cell-local planning already encoded the inserted fragment before
                        // rebuilding the complete source cell.
                        break
                    case .taskMarker:
                        return .refused(.unsupportedCommand)
                    case .uneditable:
                        return .refused(.unprovable)
                    case .mixed:
                        return .refused(.mixedDomain)
                    case .crossCell:
                        return .refused(.crossCell)
                    case .ambiguous:
                        return .refused(.ambiguousSelection)
                    }
                }

                return finishIdentityTransition(
                    mutation: mutation,
                    presentation: presentation,
                    projectionRange: transitionRange,
                    visibleReplacement: visibleReplacement,
                    nextSnapshotID: nextSnapshotID,
                    affinity: projSel.affinity
                )
            }
        }
    }

    static func finishIdentityTransition(
        mutation: SourceMutation,
        presentation: PresentationSnapshot,
        projectionRange: NSRange,
        visibleReplacement: String,
        nextSnapshotID: PresentationSnapshot.ID,
        affinity: SelectionAffinity
    ) -> EditorEditOutcome {
        let nextSourceCount = presentation.sourceUTF16Count
            - mutation.range.length
            + (mutation.replacement as NSString).length
        guard let transition = PresentationTransitionPlanner.identityReplacement(
            snapshot: presentation,
            projectionRange: projectionRange,
            visibleReplacement: visibleReplacement,
            sourceRange: mutation.range,
            sourceReplacement: mutation.replacement,
            nextSourceRevision: SourceRevision(value: mutation.expectedRevision &+ 1),
            nextSourceUTF16Count: nextSourceCount,
            nextSnapshotID: nextSnapshotID,
            affinity: affinity
        ) else {
            return .refused(.unprovable)
        }
        if !transition.nextSnapshot.isOracleValid {
            return .refused(.unprovable)
        }
        return .accepted(
            AcceptedEdit(
                sourceMutation: mutation,
                presentationTransition: transition,
                sourceSelectionAfter: mutation.selectionAfter,
                projectionSelectionAfter: transition.selectionAfter
            )
        )
    }

    static func planAuthoritativeTransition(
        mutation: SourceMutation,
        snapshot: SourceSnapshot,
        presentation: PresentationSnapshot,
        nextSnapshotID: PresentationSnapshot.ID,
        affinity: SelectionAffinity,
        taskNodeID: MarkdownNodeID? = nil,
        projectionSelectionLocation: Int? = nil,
        prebuilt: PresentationSnapshot? = nil
    ) -> EditorEditOutcome {
        let activeMutation = mutation
        // Apply the candidate to immutable source, then build one exact authoritative result.
        let ns = snapshot.text as NSString
        let usableSource: String
        guard activeMutation.range.location >= 0,
              NSMaxRange(activeMutation.range) <= ns.length else {
            return .refused(.invalidRange)
        }
        usableSource = ns.replacingCharacters(in: activeMutation.range, with: activeMutation.replacement)
        let nextRevision = activeMutation.expectedRevision &+ 1
        let nextFixed: PresentationSnapshot
        if let prebuilt,
           prebuilt.id == nextSnapshotID,
           prebuilt.sourceRevision.value == nextRevision,
           prebuilt.locationGeneration == presentation.locationGeneration,
           prebuilt.sourceUTF16Count == (usableSource as NSString).length {
            nextFixed = prebuilt
        } else {
            guard let built = AuthoritativePresentationBuilder.build(
                source: usableSource,
                sourceRevision: nextRevision,
                snapshotID: nextSnapshotID,
                locationGeneration: presentation.locationGeneration
            ) else { return .refused(.unprovable) }
            nextFixed = built
        }
        if !nextFixed.isOracleValid {
            return .refused(.unprovable)
        }
        let sourceAfter = activeMutation.selectionAfter.range.utf16
        let projSel: ProjectionSelection
        if let projectionSelectionLocation,
           projectionSelectionLocation >= 0,
           projectionSelectionLocation <= (nextFixed.renderedString as NSString).length {
            projSel = ProjectionSelection(
                utf16: NSRange(location: projectionSelectionLocation, length: 0),
                revision: nextFixed.projectionRevision,
                affinity: affinity
            )
        } else {
            switch nextFixed.coordinateMap.projectionRange(forSource: sourceAfter, affinity: affinity) {
        case .exact(let range):
            projSel = ProjectionSelection(utf16: range, revision: nextFixed.projectionRevision, affinity: affinity)
        case .refused:
            if let taskNodeID,
               let task = nextFixed.attachments.first(where: { attachment in
                   attachment.nodeID == taskNodeID && {
                       if case .task = attachment.kind { return true }
                       return false
                   }()
               }) {
                projSel = ProjectionSelection(
                    utf16: NSRange(location: task.utf16Location, length: 1),
                    revision: nextFixed.projectionRevision,
                    affinity: affinity
                )
            } else {
                return .refused(.mappingFailure)
            }
        }
        }
        let transition = PresentationTransition(
            fromSnapshotID: presentation.id,
            nextSnapshot: nextFixed,
            projectionReplacementRange: NSRange(location: 0, length: (presentation.renderedString as NSString).length),
            projectionReplacement: nextFixed.renderedString,
            selectionAfter: projSel
        )
        return .accepted(
            AcceptedEdit(
                sourceMutation: activeMutation,
                presentationTransition: transition,
                sourceSelectionAfter: activeMutation.selectionAfter,
                projectionSelectionAfter: projSel
            )
        )
    }

    static func mapRefusal(_ refusal: SemanticEditRefusal) -> EditRefusal {
        switch refusal {
        case .staleVersion: return .staleVersion
        case .ambiguousSelection: return .ambiguousSelection
        case .unsupportedCommand: return .unsupportedCommand
        case .mappingFailure: return .mappingFailure
        case .invalidRange: return .invalidRange
        }
    }

    static func precedingCharacter(snapshot: SourceSnapshot, range: NSRange) -> Character? {
        guard range.location > 0 else { return nil }
        let ns = snapshot.text as NSString
        let composed = ns.rangeOfComposedCharacterSequence(at: range.location - 1)
        return ns.substring(with: composed).first
    }

    static func followingCharacter(snapshot: SourceSnapshot, range: NSRange) -> Character? {
        let ns = snapshot.text as NSString
        let idx = NSMaxRange(range)
        guard idx < ns.length else { return nil }
        let composed = ns.rangeOfComposedCharacterSequence(at: idx)
        return ns.substring(with: composed).first
    }

    static func isAtLineStart(snapshot: SourceSnapshot, location: Int) -> Bool {
        if location == 0 { return true }
        let ns = snapshot.text as NSString
        return ns.character(at: location - 1) == 0x0A
    }

    static func container(for classif: ProjectionSelectionClass) -> LiteralEncodeContext.LiteralContainer {
        switch classif {
        case .tableCell: return .tableCell
        default: return .paragraph
        }
    }

    /// Typed source-mutation planning. This function never mutates document or presentation state.
    static func apply(
        _ request: EditorEditRequest,
        snapshot: SourceSnapshot,
        presentation: PresentationSnapshot?,
        tree: MarkdownTree?
    ) -> SemanticEditResult {
        guard request.expectedSourceRevision.value == snapshot.sourceVersion else {
            return .refused(.staleVersion)
        }

        switch request.selection {
        case .source(let sourceSel):
            return SourcePlanningDomain.applySource(
                command: request.command,
                selection: sourceSel,
                snapshot: snapshot,
                grouping: request.grouping
            )
        case .projection(let projSel):
            guard let presentation,
                  presentation.sourceRevision.value == snapshot.sourceVersion,
                  projSel.range.revision.snapshotID == presentation.id else {
                return .refused(.staleVersion)
            }
            return WYSIWYGPlanningDomain.applyWYSIWYG(
                command: request.command,
                selection: projSel,
                snapshot: snapshot,
                presentation: presentation,
                tree: tree,
                grouping: request.grouping
            )
        }
    }

    static func defaultGrouping(for command: SemanticCommand) -> MutationGrouping {
        switch command {
        case .insertText, .deleteBackward:
            return .typing
        case .toggleBold, .toggleItalic, .toggleStrikethrough, .toggleInlineCode,
             .setParagraph, .setHeading, .toggleOrderedList, .toggleUnorderedList,
             .toggleTaskList, .toggleBlockQuote, .toggleCodeBlock, .setLink,
             .toggleTask, .replaceTableCell, .insertImageMarkdown:
            return .discrete
        }
    }

    // MARK: - Source mode



    static func sourceRange(
        for classification: ProjectionSelectionClass,
        affinity: SelectionAffinity
    ) -> NSRange? {
        switch classification {
        case .identityText(let sourceRange), .atomicText(_, let sourceRange, _):
            return sourceRange
        case .syntheticInsertion(let policy):
            switch policy {
            case .atSourceLocation(let location):
                return NSRange(location: location, length: 0)
            case .atSourceBoundaries(let before, let after):
                return NSRange(
                    location: affinity == .upstream ? before : after,
                    length: 0
                )
            case .refuse:
                return nil
            }
        case .tableCell(_, let sourceRange, _):
            return sourceRange
        case .taskMarker, .uneditable, .mixed, .crossCell, .ambiguous:
            return nil
        }
    }

    static func refusal(for classification: ProjectionSelectionClass) -> SemanticEditResult {
        switch classification {
        case .mixed, .crossCell, .ambiguous:
            return .refused(.ambiguousSelection)
        case .uneditable, .taskMarker:
            return .refused(.unsupportedCommand)
        case .identityText, .atomicText, .syntheticInsertion, .tableCell:
            return .refused(.mappingFailure)
        }
    }

    static func commit(
        _ snapshot: SourceSnapshot,
        range: NSRange,
        replacement: String,
        action: String,
        grouping: MutationGrouping,
        selectionBefore: SourceSelection
    ) -> SemanticEditResult {
        guard let mutation = SourceMutation.exact(
            snapshot: snapshot,
            range: range,
            replacement: replacement,
            selectionBefore: selectionBefore,
            actionName: action,
            grouping: grouping
        ) else {
            return .refused(.invalidRange)
        }
        return .mutation(mutation)
    }

    static func mapProjectionSelectionToSource(
        _ range: NSRange,
        affinity: SelectionAffinity,
        projection: MarkdownProjectionModel
    ) -> NSRange? {
        switch projection.coordinateMap.sourceRange(forProjection: range, affinity: affinity) {
        case .exact(let mapped):
            return mapped
        case .refused:
            return nil
        }
    }

    static func toggleTaskMarker(
        snapshot: SourceSnapshot,
        tree: MarkdownTree?,
        nodeID: MarkdownNodeID,
        selectionBefore: SourceSelection
    ) -> SemanticEditResult {
        guard let tree, let node = findNode(id: nodeID, in: tree.root) else {
            return .refused(.mappingFailure)
        }
        guard case .item(let checked) = node.kind, let checked else {
            return .refused(.unsupportedCommand)
        }
        let itemRange: NSRange? = EditorSemanticWorker.sync {
            let index = MarkdownSourceIndex(
                source: snapshot.text,
                sourceVersion: snapshot.sourceVersion
            )
            guard case .success(let range) = index.utf16Range(for: node.position) else {
                return nil
            }
            return range
        }
        guard let itemRange else {
            return .refused(.mappingFailure)
        }
        guard let markerRange = StructuralSourceSpans.taskMarkerRange(
            itemSource: itemRange,
            source: snapshot.text,
            currentlyChecked: checked
        ) else {
            return .refused(.ambiguousSelection)
        }
        let replacement = checked ? "[ ]" : "[x]"
        let ns = snapshot.text as NSString
        let outsideBefore = ns.substring(with: NSRange(location: 0, length: markerRange.location))
        let outsideAfter = ns.substring(
            with: NSRange(location: NSMaxRange(markerRange), length: ns.length - NSMaxRange(markerRange))
        )
        // History selection is the exact marker span in source — never a projection offset.
        let sourceSelectionBefore = SourceSelection(
            utf16: markerRange,
            affinity: selectionBefore.affinity
        )
        return SemanticPlannerGate.commitIfValid(
            snapshot: snapshot,
            range: markerRange,
            replacement: replacement,
            action: "Toggle Task",
            grouping: .discrete,
            selectionBefore: sourceSelectionBefore
        ) { _, newText in
            let newNS = newText as NSString
            guard NSMaxRange(markerRange) <= newNS.length else { return false }
            guard newNS.substring(with: markerRange) == replacement else { return false }
            let newBefore = newNS.substring(with: NSRange(location: 0, length: markerRange.location))
            let newAfter = newNS.substring(
                with: NSRange(location: markerRange.location + 3, length: newNS.length - markerRange.location - 3)
            )
            return newBefore == outsideBefore && newAfter == outsideAfter
        }
    }

    static func findNode(id: MarkdownNodeID, in node: MarkdownNode) -> MarkdownNode? {
        if node.id == id { return node }
        for child in node.children {
            if let found = findNode(id: id, in: child) { return found }
        }
        return nil
    }
}
