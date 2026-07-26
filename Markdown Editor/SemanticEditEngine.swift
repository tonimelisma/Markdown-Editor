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

                if case .insertText(let text) = request.command, !text.isEmpty {
                    let classif = ProjectionSelectionClassifier.classify(
                        selection: projSel.range.utf16,
                        affinity: projSel.affinity,
                        snapshot: presentation
                    )
                    switch classif {
                    case .identityText, .atomicText, .syntheticInsertion, .tableCell:
                        let encodeCtx = LiteralEncodeContext(
                            intendedVisibleText: text,
                            precedingSourceCharacter: precedingCharacter(snapshot: snapshot, range: mutation.range),
                            followingSourceCharacter: followingCharacter(snapshot: snapshot, range: mutation.range),
                            atLineStart: isAtLineStart(snapshot: snapshot, location: mutation.range.location),
                            container: container(for: classif),
                            dialect: .formalGFM
                        )
                        switch MarkdownLiteralEncoder.encode(encodeCtx) {
                        case .encoded(let sourceSpelling):
                            // The source mutation initially carries visible text. If encoding
                            // differs, rebuild the mutation with encoded source while keeping
                            // visible replacement for the presentation transition.
                            if sourceSpelling != text {
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
                                return finishIdentityTransition(
                                    mutation: remade,
                                    presentation: presentation,
                                    projectionRange: projSel.range.utf16,
                                    visibleReplacement: text,
                                    nextSnapshotID: nextSnapshotID,
                                    affinity: projSel.affinity
                                )
                            }
                        case .refused:
                            return .refused(.unprovable)
                        }
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
                    projectionRange: projSel.range.utf16,
                    visibleReplacement: replacement,
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
        taskNodeID: MarkdownNodeID? = nil
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
        let idx = range.location - 1
        let scalar = ns.character(at: idx)
        return Character(UnicodeScalar(scalar)!)
    }

    private static func followingCharacter(snapshot: SourceSnapshot, range: NSRange) -> Character? {
        let ns = snapshot.text as NSString
        let idx = NSMaxRange(range)
        guard idx < ns.length else { return nil }
        let scalar = ns.character(at: idx)
        return Character(UnicodeScalar(scalar)!)
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
                    grouping: grouping
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
                    grouping: grouping
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
        grouping: MutationGrouping
    ) -> SemanticEditResult {
        guard let cell = projection.tables.flatMap(\.cells).first(where: { $0.nodeID == nodeID }),
              let cellSource = cell.sourceUTF16Range else {
            return .refused(.mappingFailure)
        }
        let ns = snapshot.text as NSString
        let cellText = ns.substring(with: cellSource) as NSString

        // Clip selection to the projected cell body (exclude trailing separator tab).
        let cellProj = cell.utf16Range
        var bodyLength = cellProj.length
        let rendered = projection.renderedString as NSString
        if bodyLength > 0,
           NSMaxRange(cellProj) <= rendered.length,
           rendered.character(at: NSMaxRange(cellProj) - 1) == 0x09 {
            bodyLength -= 1
        }
        let bodyProj = NSRange(location: cellProj.location, length: bodyLength)
        let clippedLocation = max(selection.range.utf16.location, bodyProj.location)
        let clippedEnd = min(NSMaxRange(selection.range.utf16), NSMaxRange(bodyProj))
        guard clippedEnd >= clippedLocation else { return .refused(.mappingFailure) }
        let clipped = NSRange(location: clippedLocation, length: clippedEnd - clippedLocation)

        // Full projected-body selection → replace the entire source cell (matches select-all-in-cell).
        if clipped.length == bodyProj.length, clipped.location == bodyProj.location {
            return TableCellEditPlanner.replace(
                snapshot: snapshot,
                tree: tree,
                nodeID: nodeID,
                text: text,
                grouping: grouping,
                selectionBefore: SourceSelection(utf16: cellSource, affinity: selection.affinity)
            )
        }

        // Preferred path: exact coordinate-map into the cell source span.
        if let mapped = mapProjectionSelectionToSource(
            clipped,
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
            let newCellText = cellText.replacingCharacters(in: local, with: text)
            return TableCellEditPlanner.replace(
                snapshot: snapshot,
                tree: tree,
                nodeID: nodeID,
                text: newCellText,
                grouping: grouping,
                selectionBefore: SourceSelection(utf16: mapped, affinity: selection.affinity)
            )
        }

        // Escape-aware fallback: projection may be shorter than source (`a\|b` → `a|b`).
        let localProj = NSRange(
            location: clipped.location - bodyProj.location,
            length: clipped.length
        )
        guard let localSource = mapProjectedCellRangeToSource(
            projected: localProj,
            sourceCell: cellText as String
        ) else {
            return .refused(.mappingFailure)
        }
        let newCellText = cellText.replacingCharacters(in: localSource, with: text)
        let absolute = NSRange(
            location: cellSource.location + localSource.location,
            length: localSource.length
        )
        return TableCellEditPlanner.replace(
            snapshot: snapshot,
            tree: tree,
            nodeID: nodeID,
            text: newCellText,
            grouping: grouping,
            selectionBefore: SourceSelection(utf16: absolute, affinity: selection.affinity)
        )
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
