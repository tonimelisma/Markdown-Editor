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
                    guard let tableEdit = tablePresentationEdit(
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
                            if literalCandidatePreservesPresentation(
                                mutation: remade,
                                snapshot: snapshot,
                                presentation: presentation,
                                projectionRange: projSel.range.utf16,
                                visibleReplacement: text,
                                nextSnapshotID: nextSnapshotID
                            ) {
                                return finishIdentityTransition(
                                    mutation: remade,
                                    presentation: presentation,
                                    projectionRange: transitionRange,
                                    visibleReplacement: text,
                                    nextSnapshotID: nextSnapshotID,
                                    affinity: projSel.affinity
                                )
                            }
                            guard let contextual = contextualLiteralMutation(
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
                                mutation: contextual,
                                snapshot: snapshot,
                                presentation: presentation,
                                nextSnapshotID: nextSnapshotID,
                                affinity: projSel.affinity
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

    private static func finishIdentityTransition(
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
        if case .failure = ProjectionOracle.validate(snapshot: transition.nextSnapshot) {
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

    private static func planAuthoritativeTransition(
        mutation: SourceMutation,
        snapshot: SourceSnapshot,
        presentation: PresentationSnapshot,
        nextSnapshotID: PresentationSnapshot.ID,
        affinity: SelectionAffinity,
        taskNodeID: MarkdownNodeID? = nil,
        projectionSelectionLocation: Int? = nil
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
        guard let nextFixed = AuthoritativePresentationBuilder.build(
            source: usableSource,
            sourceRevision: nextRevision,
            snapshotID: nextSnapshotID,
            locationGeneration: presentation.locationGeneration
        ) else { return .refused(.unprovable) }
        if case .failure = ProjectionOracle.validate(snapshot: nextFixed) {
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

    private static func mapRefusal(_ refusal: SemanticEditRefusal) -> EditRefusal {
        switch refusal {
        case .staleVersion: return .staleVersion
        case .ambiguousSelection: return .ambiguousSelection
        case .unsupportedCommand: return .unsupportedCommand
        case .mappingFailure: return .mappingFailure
        case .invalidRange: return .invalidRange
        }
    }

    private static func precedingCharacter(snapshot: SourceSnapshot, range: NSRange) -> Character? {
        guard range.location > 0 else { return nil }
        let ns = snapshot.text as NSString
        let composed = ns.rangeOfComposedCharacterSequence(at: range.location - 1)
        return ns.substring(with: composed).first
    }

    private static func followingCharacter(snapshot: SourceSnapshot, range: NSRange) -> Character? {
        let ns = snapshot.text as NSString
        let idx = NSMaxRange(range)
        guard idx < ns.length else { return nil }
        let composed = ns.rangeOfComposedCharacterSequence(at: idx)
        return ns.substring(with: composed).first
    }

    private static func isAtLineStart(snapshot: SourceSnapshot, location: Int) -> Bool {
        if location == 0 { return true }
        let ns = snapshot.text as NSString
        return ns.character(at: location - 1) == 0x0A
    }

    private static func container(for classif: ProjectionSelectionClass) -> LiteralEncodeContext.LiteralContainer {
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
            return applySource(
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
            return applyWYSIWYG(
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

    private static func applySource(
        command: SemanticCommand,
        selection: SourceSelection,
        snapshot: SourceSnapshot,
        grouping: MutationGrouping
    ) -> SemanticEditResult {
        let ns = snapshot.text as NSString
        let range = selection.range.utf16
        guard range.location >= 0, NSMaxRange(range) <= ns.length else {
            return .refused(.invalidRange)
        }
        let selectionBefore = selection

        switch command {
        case .insertText(let text):
            return commit(
                snapshot,
                range: range,
                replacement: text,
                action: "Typing",
                grouping: grouping,
                selectionBefore: selectionBefore
            )

        case .deleteBackward:
            if range.length > 0 {
                return commit(
                    snapshot,
                    range: range,
                    replacement: "",
                    action: "Delete",
                    grouping: grouping,
                    selectionBefore: selectionBefore
                )
            }
            guard range.location > 0 else { return .refused(.invalidRange) }
            return commit(
                snapshot,
                range: NSRange(location: range.location - 1, length: 1),
                replacement: "",
                action: "Delete",
                grouping: grouping,
                selectionBefore: selectionBefore
            )

        case .toggleBold:
            return InlineEditPlanner.wrap(
                snapshot: snapshot,
                range: range,
                delimiters: [("**", "**"), ("__", "__")],
                action: "Bold",
                grouping: grouping,
                selectionBefore: selectionBefore
            ) { if case .strong = $0 { return true }; return false }
        case .toggleItalic:
            return InlineEditPlanner.wrap(
                snapshot: snapshot,
                range: range,
                delimiters: [("*", "*"), ("_", "_")],
                action: "Italic",
                grouping: grouping,
                selectionBefore: selectionBefore
            ) { if case .emphasis = $0 { return true }; return false }
        case .toggleStrikethrough:
            return InlineEditPlanner.wrap(
                snapshot: snapshot,
                range: range,
                delimiters: [("~~", "~~")],
                action: "Strikethrough",
                grouping: grouping,
                selectionBefore: selectionBefore
            ) { if case .strikethrough = $0 { return true }; return false }
        case .toggleInlineCode:
            return InlineEditPlanner.wrapCode(
                snapshot: snapshot,
                range: range,
                grouping: grouping,
                selectionBefore: selectionBefore
            )

        case .setHeading(let level):
            return BlockEditPlanner.setHeading(
                snapshot: snapshot, range: range, level: level,
                grouping: grouping, selectionBefore: selectionBefore
            )
        case .setParagraph:
            return BlockEditPlanner.setParagraph(
                snapshot: snapshot, range: range,
                grouping: grouping, selectionBefore: selectionBefore
            )

        case .toggleUnorderedList:
            return ListEditPlanner.toggle(
                snapshot: snapshot, range: range, prefix: "- ", action: "Unordered List",
                grouping: grouping, selectionBefore: selectionBefore
            )
        case .toggleOrderedList:
            return ListEditPlanner.toggle(
                snapshot: snapshot, range: range, prefix: "1. ", action: "Ordered List",
                grouping: grouping, selectionBefore: selectionBefore
            )
        case .toggleTaskList:
            return ListEditPlanner.toggle(
                snapshot: snapshot, range: range, prefix: "- [ ] ", action: "Task List",
                grouping: grouping, selectionBefore: selectionBefore
            )
        case .toggleBlockQuote:
            return ListEditPlanner.toggleBlockQuote(
                snapshot: snapshot, range: range,
                grouping: grouping, selectionBefore: selectionBefore
            )
        case .toggleCodeBlock:
            return BlockEditPlanner.toggleCodeFence(
                snapshot: snapshot, range: range,
                grouping: grouping, selectionBefore: selectionBefore
            )

        case .setLink(let destination):
            return LinkEditPlanner.setLink(
                snapshot: snapshot, range: range, destination: destination,
                grouping: grouping, selectionBefore: selectionBefore
            )

        case .insertImageMarkdown(let markdown):
            return commit(
                snapshot,
                range: range,
                replacement: markdown,
                action: "Insert Image",
                grouping: .discrete,
                selectionBefore: selectionBefore
            )

        case .toggleTask, .replaceTableCell:
            return .refused(.unsupportedCommand)
        }
    }

    // MARK: - WYSIWYG mode

    private static func applyWYSIWYG(
        command: SemanticCommand,
        selection: ProjectionSelection,
        snapshot: SourceSnapshot,
        presentation: PresentationSnapshot,
        tree: MarkdownTree?,
        grouping: MutationGrouping
    ) -> SemanticEditResult {
        guard presentation.sourceRevision.value == snapshot.sourceVersion,
              selection.range.revision.snapshotID == presentation.id else {
            return .refused(.staleVersion)
        }
        let projection = presentation.asProjectionModel
        let selectionRange = selection.range.utf16
        let classification = ProjectionSelectionClassifier.classify(
            selection: selectionRange,
            affinity: selection.affinity,
            snapshot: presentation
        )

        switch command {
        case .toggleTask(let nodeID):
            guard case .taskMarker(let classifiedNodeID) = classification,
                  classifiedNodeID == nodeID else {
                return .refused(.ambiguousSelection)
            }
            // History selection is the exact source marker span (set inside toggleTaskMarker).
            return toggleTaskMarker(
                snapshot: snapshot,
                tree: tree,
                nodeID: nodeID,
                selectionBefore: SourceSelection(
                    utf16: NSRange(location: 0, length: 0),
                    affinity: selection.affinity
                )
            )

        case .replaceTableCell(let nodeID, let text):
            guard case .tableCell(let classifiedNodeID, let cellSource, _) = classification,
                  classifiedNodeID == nodeID else {
                return .refused(.ambiguousSelection)
            }
            let before = SourceSelection(utf16: cellSource, affinity: selection.affinity)
            return TableCellEditPlanner.replace(
                snapshot: snapshot,
                tree: tree,
                nodeID: nodeID,
                text: text,
                grouping: grouping,
                selectionBefore: before
            )

        case .insertImageMarkdown(let markdown):
            guard let sourceRange = sourceRange(for: classification, affinity: selection.affinity)
            else { return refusal(for: classification) }
            return commit(
                snapshot,
                range: sourceRange,
                replacement: markdown,
                action: "Insert Image",
                grouping: .discrete,
                selectionBefore: SourceSelection(utf16: sourceRange, affinity: selection.affinity)
            )

        case .insertText(let text):
            switch classification {
            case .tableCell(let nodeID, _, _):
                // Rebuild cell content from the projected edit intent.
                return applyTableCellTyping(
                    text: text,
                    nodeID: nodeID,
                    selection: selection,
                    snapshot: snapshot,
                    projection: projection,
                    tree: tree,
                    grouping: grouping,
                    deletingBackward: false
                )
            case .uneditable:
                return .refused(.unsupportedCommand)
            case .taskMarker(let nodeID):
                if text.isEmpty {
                    return .refused(.unsupportedCommand)
                }
                return toggleTaskMarker(
                    snapshot: snapshot,
                    tree: tree,
                    nodeID: nodeID,
                    selectionBefore: SourceSelection(
                        utf16: NSRange(location: 0, length: 0),
                        affinity: selection.affinity
                    )
                )
            case .ambiguous:
                return .refused(.ambiguousSelection)
            case .mixed:
                return .refused(.ambiguousSelection)
            case .crossCell:
                return .refused(.ambiguousSelection)
            case .identityText, .atomicText, .syntheticInsertion:
                break
            }
            guard let sourceRange = sourceRange(for: classification, affinity: selection.affinity)
            else { return refusal(for: classification) }
            return commit(
                snapshot,
                range: sourceRange,
                replacement: text,
                action: "Typing",
                grouping: grouping,
                selectionBefore: SourceSelection(utf16: sourceRange, affinity: selection.affinity)
            )

        case .deleteBackward:
            if case .tableCell(let nodeID, _, _) = classification {
                return applyTableCellTyping(
                    text: "",
                    nodeID: nodeID,
                    selection: selection,
                    snapshot: snapshot,
                    projection: projection,
                    tree: tree,
                    grouping: grouping,
                    deletingBackward: true
                )
            }
            guard let sourceRange = sourceRange(for: classification, affinity: selection.affinity)
            else { return refusal(for: classification) }
            if sourceRange.length > 0 {
                return commit(
                    snapshot,
                    range: sourceRange,
                    replacement: "",
                    action: "Delete",
                    grouping: grouping,
                    selectionBefore: SourceSelection(utf16: sourceRange, affinity: selection.affinity)
                )
            }
            guard sourceRange.location > 0 else { return .refused(.invalidRange) }
            return commit(
                snapshot,
                range: NSRange(location: sourceRange.location - 1, length: 1),
                replacement: "",
                action: "Delete",
                grouping: grouping,
                selectionBefore: SourceSelection(utf16: sourceRange, affinity: selection.affinity)
            )

        case .toggleBold, .toggleItalic, .toggleStrikethrough, .toggleInlineCode,
             .setHeading, .setParagraph, .toggleOrderedList, .toggleUnorderedList,
             .toggleTaskList, .toggleBlockQuote, .toggleCodeBlock, .setLink:
            // REQ-113/087; ARC-009; PR #32 review: a **block** rewrite reshapes the whole line,
            // so it may act only on a selection proven to be that line's own identity text. A
            // caret on a synthetic paragraph break classifies as `.syntheticInsertion` and folds
            // to a declared source location, which would make the planner silently rewrite the
            // *preceding* line. Before COR-25/COR-26 that mutation was planned and then rescued
            // by an unmappable post-edit selection refusing the whole edit; giving every planner
            // a projectable caret removed that accident, so the refusal is now stated where it
            // belongs instead of emerging from a mapping failure.
            //
            // Inline commands are unaffected: they wrap the selected span rather than reshaping
            // a line, so an atomic or synthetic endpoint stays legitimate for them.
            if command.reshapesWholeLine {
                guard case .identityText = classification else {
                    return refusal(for: classification)
                }
            }
            guard let sourceRange = sourceRange(for: classification, affinity: selection.affinity)
            else { return refusal(for: classification) }
            let sourceSelection = SourceSelection(utf16: sourceRange, affinity: selection.affinity)
            return applySource(
                command: command,
                selection: sourceSelection,
                snapshot: snapshot,
                grouping: grouping
            )
        }
    }

    /// Apply a native table-cell edit through `TableCellEditPlanner` using source cell bytes.
    ///
    /// Edits the canonical cell source (preserving escapes like `\|`) by mapping the projection
    /// selection into the cell's source span rather than rebuilding from rendered text.
    private static func applyTableCellTyping(
        text: String,
        nodeID: MarkdownNodeID,
        selection: ProjectionSelection,
        snapshot: SourceSnapshot,
        projection: MarkdownProjectionModel,
        tree: MarkdownTree?,
        grouping: MutationGrouping,
        deletingBackward: Bool
    ) -> SemanticEditResult {
        guard let cell = projection.tables.flatMap(\.cells).first(where: { $0.nodeID == nodeID }),
              let cellSource = cell.sourceUTF16Range else {
            return .refused(.mappingFailure)
        }
        let ns = snapshot.text as NSString
        let cellText = ns.substring(with: cellSource) as NSString

        // Require the selection to be wholly within the projected cell body.
        let cellProj = cell.utf16Range
        var bodyLength = cellProj.length
        let rendered = projection.renderedString as NSString
        if bodyLength > 0,
           NSMaxRange(cellProj) <= rendered.length,
           rendered.character(at: NSMaxRange(cellProj) - 1) == 0x09 {
            bodyLength -= 1
        }
        let bodyProj = NSRange(location: cellProj.location, length: bodyLength)
        var editedProjection = selection.range.utf16
        if editedProjection == cellProj {
            editedProjection = bodyProj
        }
        guard editedProjection.location >= bodyProj.location,
              NSMaxRange(editedProjection) <= NSMaxRange(bodyProj) else {
            return .refused(.mappingFailure)
        }
        if deletingBackward, editedProjection.length == 0 {
            guard editedProjection.location > bodyProj.location else {
                return .refused(.unsupportedCommand)
            }
            editedProjection = rendered.rangeOfComposedCharacterSequence(
                at: editedProjection.location - 1
            )
        }

        let encodedText: String
        if text.isEmpty {
            encodedText = ""
        } else {
            switch MarkdownLiteralEncoder.encode(
                LiteralEncodeContext(
                    intendedVisibleText: text,
                    precedingSourceCharacter: nil,
                    followingSourceCharacter: nil,
                    atLineStart: false,
                    container: .tableCell,
                    dialect: .formalGFM
                )
            ) {
            case .encoded(let spelling):
                encodedText = spelling
            case .refused:
                return .refused(.ambiguousSelection)
            }
        }

        // Full projected-body selection → replace the entire source cell (matches select-all-in-cell).
        if editedProjection == bodyProj {
            return TableCellEditPlanner.replaceExactCell(
                snapshot: snapshot,
                tree: tree,
                sourceRange: cellSource,
                text: encodedText,
                grouping: grouping,
                selectionBefore: SourceSelection(utf16: cellSource, affinity: selection.affinity)
            )
        }

        // Preferred path: exact coordinate-map into the cell source span.
        if let mapped = mapProjectionSelectionToSource(
            editedProjection,
            affinity: selection.affinity,
            projection: projection
        ),
           mapped.location >= cellSource.location,
           NSMaxRange(mapped) <= NSMaxRange(cellSource) {
            let local = NSRange(
                location: mapped.location - cellSource.location,
                length: mapped.length
            )
            guard local.location >= 0, NSMaxRange(local) <= cellText.length else {
                return .refused(.mappingFailure)
            }
            let newCellText = cellText.replacingCharacters(in: local, with: encodedText)
            return TableCellEditPlanner.replaceExactCell(
                snapshot: snapshot,
                tree: tree,
                sourceRange: cellSource,
                text: newCellText,
                grouping: grouping,
                selectionBefore: SourceSelection(utf16: mapped, affinity: selection.affinity)
            )
        }

        // Escape-aware fallback: projection may be shorter than source (`a\|b` → `a|b`).
        let localProj = NSRange(
            location: editedProjection.location - bodyProj.location,
            length: editedProjection.length
        )
        guard let localSource = mapProjectedCellRangeToSource(
            projected: localProj,
            sourceCell: cellText as String
        ) else {
            return .refused(.mappingFailure)
        }
        let newCellText = cellText.replacingCharacters(in: localSource, with: encodedText)
        let absolute = NSRange(
            location: cellSource.location + localSource.location,
            length: localSource.length
        )
        return TableCellEditPlanner.replaceExactCell(
            snapshot: snapshot,
            tree: tree,
            sourceRange: cellSource,
            text: newCellText,
            grouping: grouping,
            selectionBefore: SourceSelection(utf16: absolute, affinity: selection.affinity)
        )
    }

    private static func tablePresentationEdit(
        command: SemanticCommand,
        selection: NSRange,
        body: NSRange,
        rendered: String
    ) -> (replacement: String, selectionLocation: Int)? {
        guard selection.location >= body.location,
              NSMaxRange(selection) <= NSMaxRange(body) else {
            return nil
        }
        let ns = rendered as NSString
        let currentBody = ns.substring(with: body) as NSString
        var local = NSRange(location: selection.location - body.location, length: selection.length)
        let replacement: String
        switch command {
        case .insertText(let text):
            replacement = text
        case .deleteBackward:
            replacement = ""
            if local.length == 0 {
                guard local.location > 0 else { return nil }
                local = currentBody.rangeOfComposedCharacterSequence(at: local.location - 1)
            }
        case .replaceTableCell(_, let text):
            local = NSRange(location: 0, length: currentBody.length)
            replacement = text
        default:
            return nil
        }
        let nextBody = currentBody.replacingCharacters(in: local, with: replacement)
        return (
            replacement: nextBody,
            selectionLocation: body.location + local.location + (replacement as NSString).length
        )
    }

    /// Reparse the completed source context and prove that it renders exactly as the
    /// native literal insertion intended. This catches syntax assembled across edits.
    private static func literalCandidatePreservesPresentation(
        mutation: SourceMutation,
        snapshot: SourceSnapshot,
        presentation: PresentationSnapshot,
        projectionRange: NSRange,
        visibleReplacement: String,
        nextSnapshotID: PresentationSnapshot.ID
    ) -> Bool {
        let source = snapshot.text as NSString
        guard mutation.range.location >= 0, NSMaxRange(mutation.range) <= source.length else {
            return false
        }
        let candidate = source.replacingCharacters(in: mutation.range, with: mutation.replacement)
        let expected = (presentation.renderedString as NSString).replacingCharacters(
            in: projectionRange,
            with: visibleReplacement
        )
        guard let built = AuthoritativePresentationBuilder.build(
            source: candidate,
            sourceRevision: mutation.expectedRevision &+ 1,
            snapshotID: nextSnapshotID,
            locationGeneration: presentation.locationGeneration
        ) else {
            return false
        }
        // Equal visible strings are insufficient: a list marker, entity, or other
        // control run can emerge without changing the plain text. Compare semantic
        // structure while deliberately ignoring node IDs, shifted ranges, and atom
        // fragmentation, which are representation details of a fresh parse.
        return built.renderedString == expected
            && sameRunSemantics(built.runs, presentation.runs)
            && sameAttachmentSemantics(built.attachments, presentation.attachments)
            && sameTableSemantics(built.tables, presentation.tables)
            && sameListSemantics(built.listMarkers, presentation.listMarkers)
    }

    private static func sameRunSemantics(_ lhs: [ProjectionRun], _ rhs: [ProjectionRun]) -> Bool {
        lhs.count == rhs.count && zip(lhs, rhs).allSatisfy {
            $0.styles == $1.styles
                && $0.linkDestination == $1.linkDestination
                && $0.isLiteralFallback == $1.isLiteralFallback
        }
    }

    private static func sameAttachmentSemantics(
        _ lhs: [ProjectionAttachment],
        _ rhs: [ProjectionAttachment]
    ) -> Bool {
        lhs.count == rhs.count && zip(lhs, rhs).allSatisfy {
            switch ($0.kind, $1.kind) {
            case (.task(let a, _), .task(let b, _)): return a == b
            case (.image(let a, _), .image(let b, _)): return a == b
            case (.thematicBreak, .thematicBreak): return true
            default: return false
            }
        }
    }

    private static func sameTableSemantics(_ lhs: [ProjectionTable], _ rhs: [ProjectionTable]) -> Bool {
        lhs.count == rhs.count && zip(lhs, rhs).allSatisfy {
            $0.columnCount == $1.columnCount
                && $0.alignments == $1.alignments
                && $0.cells.count == $1.cells.count
        }
    }

    private static func sameListSemantics(
        _ lhs: [ProjectionListMarker],
        _ rhs: [ProjectionListMarker]
    ) -> Bool {
        lhs.count == rhs.count && zip(lhs, rhs).allSatisfy {
            $0.text == $1.text && $0.nesting == $1.nesting && $0.kind == $1.kind
        }
    }

    /// If syntax emerged from earlier literal keystrokes, protect the closest source
    /// punctuation that caused it and validate the completed context again.
    private static func contextualLiteralMutation(
        original: SourceMutation,
        encodedInsertion: String,
        snapshot: SourceSnapshot,
        presentation: PresentationSnapshot,
        projectionRange: NSRange,
        visibleReplacement: String,
        nextSnapshotID: PresentationSnapshot.ID
    ) -> SourceMutation? {
        guard original.range.length == 0 else { return nil }
        let source = snapshot.text as NSString
        let line = source.lineRange(for: NSRange(location: original.range.location, length: 0))
        let lowerBound = max(line.location, original.range.location - 128)
        guard original.range.location > lowerBound else { return nil }

        for location in stride(from: original.range.location - 1, through: lowerBound, by: -1) {
            let scalar = source.character(at: location)
            let protection: String
            if scalar == 0x26 { // & — backslash escaping does not suppress entities.
                protection = "&amp;"
            } else if isASCIIPunctuation(scalar) {
                protection = "\\" + source.substring(with: NSRange(location: location, length: 1))
            } else {
                continue
            }
            let between = source.substring(
                with: NSRange(
                    location: location + 1,
                    length: original.range.location - location - 1
                )
            )
            guard let candidate = SourceMutation.exact(
                snapshot: snapshot,
                range: NSRange(location: location, length: original.range.location - location),
                replacement: protection + between + encodedInsertion,
                selectionBefore: original.selectionBefore,
                actionName: original.actionName,
                grouping: original.grouping
            ) else {
                continue
            }
            if literalCandidatePreservesPresentation(
                mutation: candidate,
                snapshot: snapshot,
                presentation: presentation,
                projectionRange: projectionRange,
                visibleReplacement: visibleReplacement,
                nextSnapshotID: nextSnapshotID
            ) {
                return candidate
            }
        }
        return nil
    }

    private static func isASCIIPunctuation(_ scalar: unichar) -> Bool {
        guard scalar < 128, let unicode = UnicodeScalar(scalar) else { return false }
        return CharacterSet.punctuationCharacters.contains(unicode)
            || scalar == 0x2A || scalar == 0x2B || scalar == 0x2D
    }

    /// Map a range in the projected (unescaped) cell body into the raw source cell body.
    ///
    /// Walks source escapes (`\|`, `\\`) so a caret after projected `a` in `a|b` lands after
    /// source `a` in `a\|b`, preserving the escape when the edit is applied.
    private static func mapProjectedCellRangeToSource(
        projected: NSRange,
        sourceCell: String
    ) -> NSRange? {
        let source = sourceCell as NSString
        var sourceIndex = 0
        var projectedIndex = 0
        var startSource: Int?
        let targetStart = projected.location
        let targetEnd = NSMaxRange(projected)

        func advance() -> Bool {
            guard sourceIndex < source.length else { return false }
            let c = source.character(at: sourceIndex)
            if c == 0x5C, sourceIndex + 1 < source.length { // backslash escape
                sourceIndex += 2
            } else {
                sourceIndex += 1
            }
            projectedIndex += 1
            return true
        }

        while projectedIndex < targetStart {
            guard advance() else { return nil }
        }
        startSource = sourceIndex
        if projected.length == 0 {
            return NSRange(location: sourceIndex, length: 0)
        }
        while projectedIndex < targetEnd {
            guard advance() else { return nil }
        }
        guard let start = startSource else { return nil }
        return NSRange(location: start, length: sourceIndex - start)
    }

    // MARK: - Helpers

    private static func sourceRange(
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

    private static func refusal(for classification: ProjectionSelectionClass) -> SemanticEditResult {
        switch classification {
        case .mixed, .crossCell, .ambiguous:
            return .refused(.ambiguousSelection)
        case .uneditable, .taskMarker:
            return .refused(.unsupportedCommand)
        case .identityText, .atomicText, .syntheticInsertion, .tableCell:
            return .refused(.mappingFailure)
        }
    }

    private static func commit(
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

    private static func mapProjectionSelectionToSource(
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

    private static func toggleTaskMarker(
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

    private static func findNode(id: MarkdownNodeID, in node: MarkdownNode) -> MarkdownNode? {
        if node.id == id { return node }
        for child in node.children {
            if let found = findNode(id: id, in: child) { return found }
        }
        return nil
    }
}
