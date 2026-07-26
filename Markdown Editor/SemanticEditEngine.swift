//
//  SemanticEditEngine.swift
//  Markdown Editor
//

import Foundation

/// Logical selection interpreted against source or projection.
///
/// Prefer `EditorEditRequest` for new call sites. Kept for toolbar/test compatibility.
nonisolated struct SemanticSelection: Sendable, Equatable {
    enum Mode: Sendable, Equatable {
        case source
        case wysiwyg
    }

    let mode: Mode
    let utf16Range: NSRange
    let sourceVersion: UInt64
    let affinity: SelectionAffinity

    init(
        mode: Mode,
        utf16Range: NSRange,
        sourceVersion: UInt64,
        affinity: SelectionAffinity = .downstream
    ) {
        self.mode = mode
        self.utf16Range = utf16Range
        self.sourceVersion = sourceVersion
        self.affinity = affinity
    }
}

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
    /// Primary pipeline entry — typed request with grouping and domain.
    static func apply(_ request: EditorEditRequest,
                      snapshot: SourceSnapshot,
                      projection: MarkdownProjectionModel?,
                      tree: MarkdownTree?) -> SemanticEditResult {
        guard request.expectedSourceRevision.value == snapshot.sourceVersion else {
            return .refused(.staleVersion)
        }

        let selection: SemanticSelection
        switch request.selection {
        case .source(let sourceSel):
            selection = SemanticSelection(
                mode: .source,
                utf16Range: sourceSel.nsRange,
                sourceVersion: snapshot.sourceVersion,
                affinity: sourceSel.affinity
            )
        case .projection(let projSel):
            guard let projection, projection.sourceVersion == projSel.range.revision.value else {
                return .refused(.staleVersion)
            }
            selection = SemanticSelection(
                mode: .wysiwyg,
                utf16Range: projSel.nsRange,
                sourceVersion: snapshot.sourceVersion,
                affinity: projSel.affinity
            )
        }

        return apply(
            command: request.command,
            selection: selection,
            snapshot: snapshot,
            projection: projection,
            tree: tree,
            grouping: request.grouping
        )
    }

    static func apply(
        command: SemanticCommand,
        selection: SemanticSelection,
        snapshot: SourceSnapshot,
        projection: MarkdownProjectionModel?,
        tree: MarkdownTree?,
        grouping: MutationGrouping? = nil
    ) -> SemanticEditResult {
        guard selection.sourceVersion == snapshot.sourceVersion else {
            return .refused(.staleVersion)
        }
        let resolvedGrouping = grouping ?? defaultGrouping(for: command)

        switch selection.mode {
        case .source:
            return applySource(
                command: command,
                selection: selection,
                snapshot: snapshot,
                grouping: resolvedGrouping
            )
        case .wysiwyg:
            return applyWYSIWYG(
                command: command,
                selection: selection,
                snapshot: snapshot,
                projection: projection,
                tree: tree,
                grouping: resolvedGrouping
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

    // MARK: - Context classification (COR-08)

    /// Classify the semantic context intersecting a projection selection.
    static func classifyContext(
        projectionSelection: NSRange,
        projection: MarkdownProjectionModel,
        tree: MarkdownTree?
    ) -> SemanticEditContext {
        // Task attachment hit.
        for attachment in projection.attachments {
            if case .task = attachment.kind,
               projectionSelection.length <= 1,
               projectionSelection.location == attachment.utf16Location
                || NSLocationInRange(attachment.utf16Location, projectionSelection) {
                return .taskMarker(nodeID: attachment.nodeID)
            }
        }

        // Table cell containing the selection.
        for table in projection.tables {
            for cell in table.cells {
                if NSIntersectionRange(cell.utf16Range, projectionSelection).length > 0
                    || (projectionSelection.length == 0
                        && NSLocationInRange(projectionSelection.location, cell.utf16Range)
                        || projectionSelection.location == cell.utf16Range.location
                        || projectionSelection.location == NSMaxRange(cell.utf16Range)) {
                    // Prefer the cell whose range contains the caret/selection start.
                    if projectionSelection.length == 0 {
                        let loc = projectionSelection.location
                        if loc >= cell.utf16Range.location && loc <= NSMaxRange(cell.utf16Range) {
                            return .tableCell(nodeID: cell.nodeID)
                        }
                    } else if NSIntersectionRange(cell.utf16Range, projectionSelection).length > 0 {
                        return .tableCell(nodeID: cell.nodeID)
                    }
                }
            }
        }

        // Inspect overlapping segments.
        var sawCode = false
        var sawLink = false
        var sawInline = false
        var sawPlain = false
        var sawUneditable = false
        for segment in projection.segments {
            let overlap = NSIntersectionRange(segment.projectionRange, projectionSelection)
            let caretOnBoundary = projectionSelection.length == 0
                && (projectionSelection.location == segment.projectionRange.location
                    || projectionSelection.location == NSMaxRange(segment.projectionRange)
                    || (projectionSelection.location > segment.projectionRange.location
                        && projectionSelection.location < NSMaxRange(segment.projectionRange)))
            guard overlap.length > 0 || caretOnBoundary else { continue }
            switch segment {
            case .uneditable:
                sawUneditable = true
            case .synthetic(_, let kind, let insertion):
                if case .refuse = insertion { sawUneditable = true }
                if case .taskCheckbox = kind { /* handled above */ }
            case .source, .literalFallback:
                sawPlain = true
            }
        }
        for run in projection.runs {
            let overlap = NSIntersectionRange(run.utf16Range, projectionSelection)
            guard overlap.length > 0
                    || (projectionSelection.length == 0
                        && projectionSelection.location >= run.utf16Range.location
                        && projectionSelection.location <= NSMaxRange(run.utf16Range)) else {
                continue
            }
            if run.styles.contains(.code) { sawCode = true }
            if run.linkDestination != nil || run.styles.contains(.link) { sawLink = true }
            if run.styles.contains(.emphasis)
                || run.styles.contains(.strong)
                || run.styles.contains(.strikethrough) {
                sawInline = true
            }
        }

        if sawUneditable { return .uneditable }
        if sawCode { return .codeContent }
        if sawLink { return .linkLabel }
        if sawInline { return .inlineSemantics }
        if sawPlain { return .plainText }
        _ = tree
        return .plainText
    }

    // MARK: - Source mode

    private static func applySource(
        command: SemanticCommand,
        selection: SemanticSelection,
        snapshot: SourceSnapshot,
        grouping: MutationGrouping
    ) -> SemanticEditResult {
        let ns = snapshot.text as NSString
        let range = selection.utf16Range
        guard range.location >= 0, NSMaxRange(range) <= ns.length else {
            return .refused(.invalidRange)
        }
        let selectionBefore = SourceSelection(utf16: range, affinity: selection.affinity)

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
        selection: SemanticSelection,
        snapshot: SourceSnapshot,
        projection: MarkdownProjectionModel?,
        tree: MarkdownTree?,
        grouping: MutationGrouping
    ) -> SemanticEditResult {
        guard let projection, projection.sourceVersion == snapshot.sourceVersion else {
            return .refused(.staleVersion)
        }
        let selectionBefore = SourceSelection(utf16: selection.utf16Range, affinity: selection.affinity)

        switch command {
        case .toggleTask(let nodeID):
            return toggleTaskMarker(
                snapshot: snapshot,
                tree: tree,
                nodeID: nodeID,
                selectionBefore: selectionBefore
            )

        case .replaceTableCell(let nodeID, let text):
            return TableCellEditPlanner.replace(
                snapshot: snapshot,
                tree: tree,
                nodeID: nodeID,
                text: text,
                grouping: grouping,
                selectionBefore: selectionBefore
            )

        case .insertImageMarkdown(let markdown):
            guard let sourceRange = mapProjectionSelectionToSource(
                selection.utf16Range,
                affinity: selection.affinity,
                projection: projection
            ) else {
                return .refused(.mappingFailure)
            }
            return commit(
                snapshot,
                range: sourceRange,
                replacement: markdown,
                action: "Insert Image",
                grouping: .discrete,
                selectionBefore: SourceSelection(utf16: sourceRange, affinity: selection.affinity)
            )

        case .insertText(let text):
            let context = classifyContext(
                projectionSelection: selection.utf16Range,
                projection: projection,
                tree: tree
            )
            switch context {
            case .tableCell(let nodeID):
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
                    selectionBefore: selectionBefore
                )
            case .ambiguous:
                return .refused(.ambiguousSelection)
            case .plainText, .inlineSemantics, .linkLabel, .codeContent:
                break
            }
            guard let sourceRange = mapProjectionSelectionToSource(
                selection.utf16Range,
                affinity: selection.affinity,
                projection: projection
            ) else {
                return .refused(.mappingFailure)
            }
            return commit(
                snapshot,
                range: sourceRange,
                replacement: text,
                action: "Typing",
                grouping: grouping,
                selectionBefore: SourceSelection(utf16: sourceRange, affinity: selection.affinity)
            )

        case .deleteBackward:
            let context = classifyContext(
                projectionSelection: selection.utf16Range,
                projection: projection,
                tree: tree
            )
            if case .tableCell(let nodeID) = context {
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
            if case .uneditable = context {
                return .refused(.unsupportedCommand)
            }
            guard let sourceRange = mapProjectionSelectionToSource(
                selection.utf16Range,
                affinity: selection.affinity,
                projection: projection
            ) else {
                return .refused(.mappingFailure)
            }
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
            guard let sourceRange = mapProjectionSelectionToSource(
                selection.utf16Range,
                affinity: selection.affinity,
                projection: projection
            ) else {
                return .refused(.mappingFailure)
            }
            let sourceSelection = SemanticSelection(
                mode: .source,
                utf16Range: sourceRange,
                sourceVersion: selection.sourceVersion,
                affinity: selection.affinity
            )
            return applySource(
                command: command,
                selection: sourceSelection,
                snapshot: snapshot,
                grouping: grouping
            )
        }
    }

    /// Apply a native table-cell edit through `TableCellEditPlanner`.
    private static func applyTableCellTyping(
        text: String,
        nodeID: MarkdownNodeID,
        selection: SemanticSelection,
        snapshot: SourceSnapshot,
        projection: MarkdownProjectionModel,
        tree: MarkdownTree?,
        grouping: MutationGrouping
    ) -> SemanticEditResult {
        guard let cell = projection.tables.flatMap(\.cells).first(where: { $0.nodeID == nodeID }),
              let cellSource = cell.sourceUTF16Range else {
            return .refused(.mappingFailure)
        }
        // Current projected cell text with the native replacement applied.
        let rendered = projection.renderedString as NSString
        let cellProj = cell.utf16Range
        guard NSMaxRange(cellProj) <= rendered.length else { return .refused(.mappingFailure) }
        let before = rendered.substring(with: cellProj) as NSString
        let local = NSRange(
            location: selection.utf16Range.location - cellProj.location,
            length: selection.utf16Range.length
        )
        guard local.location >= 0, NSMaxRange(local) <= before.length else {
            return .refused(.mappingFailure)
        }
        let newCellText = before.replacingCharacters(in: local, with: text)
        // Strip synthetic tab separators that may appear in multi-column projection.
        let cleaned = newCellText.replacingOccurrences(of: "\t", with: "")
        return TableCellEditPlanner.replace(
            snapshot: snapshot,
            tree: tree,
            nodeID: nodeID,
            text: cleaned,
            grouping: grouping,
            selectionBefore: SourceSelection(utf16: cellSource, affinity: selection.affinity)
        )
    }

    // MARK: - Helpers

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
        let index = MarkdownSourceIndex(source: snapshot.text, sourceVersion: snapshot.sourceVersion)
        guard case .success(let itemRange) = index.utf16Range(for: node.position) else {
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
        return SemanticPlannerGate.commitIfValid(
            snapshot: snapshot,
            range: markerRange,
            replacement: replacement,
            action: "Toggle Task",
            grouping: .discrete,
            selectionBefore: selectionBefore
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
