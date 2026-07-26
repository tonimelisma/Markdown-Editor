//
//  SemanticEditEngine.swift
//  Markdown Editor
//

import Foundation

/// Logical selection interpreted against source or projection.
nonisolated struct SemanticSelection: Sendable, Equatable {
    enum Mode: Sendable, Equatable {
        case source
        case wysiwyg
    }

    let mode: Mode
    let utf16Range: NSRange
    let sourceVersion: UInt64
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
    case transaction(SourceEdit, postEditSelection: LogicalSelection)
    case refused(SemanticEditRefusal)
}

/// Pure semantic → source translation. Never mutates document state.
///
/// // REQ-057/058/078–080/083/087: preserve spelling when safe; smallest unit rewrite; typed refusal.
nonisolated enum SemanticEditEngine {
    static func apply(
        command: SemanticCommand,
        selection: SemanticSelection,
        snapshot: SourceSnapshot,
        projection: MarkdownProjectionModel?,
        tree: MarkdownTree?
    ) -> SemanticEditResult {
        guard selection.sourceVersion == snapshot.sourceVersion else {
            return .refused(.staleVersion)
        }

        switch selection.mode {
        case .source:
            return applySource(command: command, selection: selection, snapshot: snapshot)
        case .wysiwyg:
            return applyWYSIWYG(
                command: command,
                selection: selection,
                snapshot: snapshot,
                projection: projection,
                tree: tree
            )
        }
    }

    // MARK: - Source mode

    private static func applySource(
        command: SemanticCommand,
        selection: SemanticSelection,
        snapshot: SourceSnapshot
    ) -> SemanticEditResult {
        let ns = snapshot.text as NSString
        let range = selection.utf16Range
        guard range.location >= 0, NSMaxRange(range) <= ns.length else {
            return .refused(.invalidRange)
        }

        switch command {
        case .insertText(let text):
            return commit(snapshot, range: range, replacement: text, action: "Typing")

        case .deleteBackward:
            if range.length > 0 {
                return commit(snapshot, range: range, replacement: "", action: "Delete")
            }
            guard range.location > 0 else { return .refused(.invalidRange) }
            return commit(
                snapshot,
                range: NSRange(location: range.location - 1, length: 1),
                replacement: "",
                action: "Delete"
            )

        case .toggleBold:
            return InlineEditPlanner.wrap(
                snapshot: snapshot,
                range: range,
                delimiters: [("**", "**"), ("__", "__")],
                action: "Bold"
            ) { if case .strong = $0 { return true }; return false }
        case .toggleItalic:
            return InlineEditPlanner.wrap(
                snapshot: snapshot,
                range: range,
                delimiters: [("*", "*"), ("_", "_")],
                action: "Italic"
            ) { if case .emphasis = $0 { return true }; return false }
        case .toggleStrikethrough:
            return InlineEditPlanner.wrap(
                snapshot: snapshot,
                range: range,
                delimiters: [("~~", "~~")],
                action: "Strikethrough"
            ) { if case .strikethrough = $0 { return true }; return false }
        case .toggleInlineCode:
            return InlineEditPlanner.wrapCode(snapshot: snapshot, range: range)

        case .setHeading(let level):
            return BlockEditPlanner.setHeading(snapshot: snapshot, range: range, level: level)
        case .setParagraph:
            return BlockEditPlanner.setParagraph(snapshot: snapshot, range: range)

        case .toggleUnorderedList:
            return ListEditPlanner.toggle(snapshot: snapshot, range: range, prefix: "- ", action: "Unordered List")
        case .toggleOrderedList:
            return ListEditPlanner.toggle(snapshot: snapshot, range: range, prefix: "1. ", action: "Ordered List")
        case .toggleTaskList:
            return ListEditPlanner.toggle(snapshot: snapshot, range: range, prefix: "- [ ] ", action: "Task List")
        case .toggleBlockQuote:
            return ListEditPlanner.toggleBlockQuote(snapshot: snapshot, range: range)
        case .toggleCodeBlock:
            return BlockEditPlanner.toggleCodeFence(snapshot: snapshot, range: range)

        case .setLink(let destination):
            return LinkEditPlanner.setLink(snapshot: snapshot, range: range, destination: destination)

        case .insertImageMarkdown(let markdown):
            return commit(snapshot, range: range, replacement: markdown, action: "Insert Image")

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
        tree: MarkdownTree?
    ) -> SemanticEditResult {
        guard let projection, projection.sourceVersion == snapshot.sourceVersion else {
            return .refused(.staleVersion)
        }

        switch command {
        case .toggleTask(let nodeID):
            return toggleTaskMarker(snapshot: snapshot, tree: tree, nodeID: nodeID)

        case .replaceTableCell(let nodeID, let text):
            return TableCellEditPlanner.replace(
                snapshot: snapshot,
                tree: tree,
                nodeID: nodeID,
                text: text
            )

        case .insertImageMarkdown(let markdown):
            guard let sourceRange = mapProjectionSelectionToSource(selection.utf16Range, projection: projection) else {
                return .refused(.mappingFailure)
            }
            return commit(snapshot, range: sourceRange, replacement: markdown, action: "Insert Image")

        case .insertText(let text):
            guard let sourceRange = mapProjectionSelectionToSource(selection.utf16Range, projection: projection) else {
                return .refused(.mappingFailure)
            }
            return commit(snapshot, range: sourceRange, replacement: text, action: "Typing")

        case .deleteBackward:
            guard let sourceRange = mapProjectionSelectionToSource(selection.utf16Range, projection: projection) else {
                return .refused(.mappingFailure)
            }
            if sourceRange.length > 0 {
                return commit(snapshot, range: sourceRange, replacement: "", action: "Delete")
            }
            guard sourceRange.location > 0 else { return .refused(.invalidRange) }
            return commit(
                snapshot,
                range: NSRange(location: sourceRange.location - 1, length: 1),
                replacement: "",
                action: "Delete"
            )

        case .toggleBold, .toggleItalic, .toggleStrikethrough, .toggleInlineCode,
             .setHeading, .setParagraph, .toggleOrderedList, .toggleUnorderedList,
             .toggleTaskList, .toggleBlockQuote, .toggleCodeBlock, .setLink:
            // Map selection to source then reuse source helpers.
            guard let sourceRange = mapProjectionSelectionToSource(selection.utf16Range, projection: projection) else {
                return .refused(.mappingFailure)
            }
            let sourceSelection = SemanticSelection(
                mode: .source,
                utf16Range: sourceRange,
                sourceVersion: selection.sourceVersion
            )
            return applySource(command: command, selection: sourceSelection, snapshot: snapshot)
        }
    }

    // MARK: - Helpers

    private static func commit(
        _ snapshot: SourceSnapshot,
        range: NSRange,
        replacement: String,
        action: String
    ) -> SemanticEditResult {
        let edit = SourceEdit(
            expectedVersion: snapshot.sourceVersion,
            range: range,
            replacement: replacement,
            actionName: action
        )
        let selection = LogicalSelection(
            range: NSRange(location: range.location + (replacement as NSString).length, length: 0)
        )
        return .transaction(edit, postEditSelection: selection)
    }

    private static func mapProjectionSelectionToSource(
        _ range: NSRange,
        projection: MarkdownProjectionModel
    ) -> NSRange? {
        switch projection.coordinateMap.sourceRange(forProjection: range) {
        case .exact(let mapped):
            return mapped
        case .refused:
            return nil
        }
    }

    private static func toggleTaskMarker(
        snapshot: SourceSnapshot,
        tree: MarkdownTree?,
        nodeID: MarkdownNodeID
    ) -> SemanticEditResult {
        guard let tree, let node = findNode(id: nodeID, in: tree.root) else {
            return .refused(.mappingFailure)
        }
        guard case .item(let checked) = node.kind, let checked else {
            return .refused(.unsupportedCommand)
        }
        let index = MarkdownSourceIndex(source: snapshot.text, sourceVersion: snapshot.sourceVersion)
        guard case .success(let sourceRange) = index.utf16Range(for: node.position) else {
            return .refused(.mappingFailure)
        }
        let ns = snapshot.text as NSString
        let slice = ns.substring(with: sourceRange)
        let replacement: String
        if checked {
            replacement = slice
                .replacingOccurrences(of: "[x]", with: "[ ]")
                .replacingOccurrences(of: "[X]", with: "[ ]")
        } else {
            if let r = slice.range(of: "[ ]") {
                replacement = slice.replacingCharacters(in: r, with: "[x]")
            } else {
                return .refused(.ambiguousSelection)
            }
        }
        return SemanticPlannerGate.commitIfValid(
            snapshot: snapshot,
            range: sourceRange,
            replacement: replacement,
            action: "Toggle Task"
        ) { newTree in
            guard let item = findNode(id: nodeID, in: newTree.root),
                  case .item(let newChecked) = item.kind else {
                // Node IDs are per-parse; accept flipped marker text instead.
                return replacement.contains("[x]") || replacement.contains("[X]") || replacement.contains("[ ]")
            }
            return newChecked != checked
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
