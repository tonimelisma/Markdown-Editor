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
            return wrapInline(snapshot, range: range, delimiters: [("**", "**"), ("__", "__")], action: "Bold")
        case .toggleItalic:
            return wrapInline(snapshot, range: range, delimiters: [("*", "*"), ("_", "_")], action: "Italic")
        case .toggleStrikethrough:
            return wrapInline(snapshot, range: range, delimiters: [("~~", "~~")], action: "Strikethrough")
        case .toggleInlineCode:
            return wrapCode(snapshot, range: range)

        case .setHeading(let level):
            return setBlockPrefix(snapshot, range: range, prefix: String(repeating: "#", count: max(1, min(level, 6))) + " ", action: "Heading")
        case .setParagraph:
            return stripBlockPrefix(snapshot, range: range, action: "Paragraph")

        case .toggleUnorderedList:
            return toggleLinePrefix(snapshot, range: range, prefix: "- ", action: "Unordered List")
        case .toggleOrderedList:
            return toggleLinePrefix(snapshot, range: range, prefix: "1. ", action: "Ordered List")
        case .toggleTaskList:
            return toggleLinePrefix(snapshot, range: range, prefix: "- [ ] ", action: "Task List")
        case .toggleBlockQuote:
            return toggleLinePrefix(snapshot, range: range, prefix: "> ", action: "Quote")
        case .toggleCodeBlock:
            return toggleCodeFence(snapshot, range: range)

        case .setLink(let destination):
            return setLinkSource(snapshot, range: range, destination: destination)

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
            return replaceNodeLiteral(snapshot: snapshot, tree: tree, nodeID: nodeID, replacement: text, action: "Edit Cell")

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

    private static func wrapInline(
        _ snapshot: SourceSnapshot,
        range: NSRange,
        delimiters: [(String, String)],
        action: String
    ) -> SemanticEditResult {
        let ns = snapshot.text as NSString
        let selected = ns.substring(with: range)
        for (open, close) in delimiters {
            // Unwrap if already wrapped with this delimiter.
            if selected.hasPrefix(open), selected.hasSuffix(close), selected.count >= open.count + close.count {
                let inner = String(selected.dropFirst(open.count).dropLast(close.count))
                return commit(snapshot, range: range, replacement: inner, action: action)
            }
            // Prefer existing surrounding delimiters.
            let beforeStart = range.location >= open.count
            if beforeStart {
                let before = ns.substring(with: NSRange(location: range.location - open.count, length: open.count))
                let afterLoc = NSMaxRange(range)
                if afterLoc + close.count <= ns.length {
                    let after = ns.substring(with: NSRange(location: afterLoc, length: close.count))
                    if before == open && after == close {
                        let expanded = NSRange(location: range.location - open.count, length: range.length + open.count + close.count)
                        return commit(snapshot, range: expanded, replacement: selected, action: action)
                    }
                }
            }
        }
        // Choose a delimiter that does not conflict with content.
        let (open, close) = delimiters.first { open, _ in !selected.contains(open) } ?? delimiters[0]
        return commit(snapshot, range: range, replacement: open + selected + close, action: action)
    }

    private static func wrapCode(_ snapshot: SourceSnapshot, range: NSRange) -> SemanticEditResult {
        let selected = (snapshot.text as NSString).substring(with: range)
        var ticks = "`"
        while selected.contains(ticks) {
            ticks += "`"
        }
        return commit(snapshot, range: range, replacement: ticks + selected + ticks, action: "Inline Code")
    }

    private static func lineRange(in text: NSString, containing range: NSRange) -> NSRange {
        text.lineRange(for: range)
    }

    private static func setBlockPrefix(
        _ snapshot: SourceSnapshot,
        range: NSRange,
        prefix: String,
        action: String
    ) -> SemanticEditResult {
        let ns = snapshot.text as NSString
        let line = lineRange(in: ns, containing: range)
        var content = ns.substring(with: line)
        let hadNewline = content.hasSuffix("\n")
        if hadNewline { content = String(content.dropLast()) }
        let stripped = stripKnownBlockPrefixes(content)
        let replacement = prefix + stripped + (hadNewline ? "\n" : "")
        return commit(snapshot, range: line, replacement: replacement, action: action)
    }

    private static func stripBlockPrefix(
        _ snapshot: SourceSnapshot,
        range: NSRange,
        action: String
    ) -> SemanticEditResult {
        let ns = snapshot.text as NSString
        let line = lineRange(in: ns, containing: range)
        var content = ns.substring(with: line)
        let hadNewline = content.hasSuffix("\n")
        if hadNewline { content = String(content.dropLast()) }
        let stripped = stripKnownBlockPrefixes(content)
        let replacement = stripped + (hadNewline ? "\n" : "")
        return commit(snapshot, range: line, replacement: replacement, action: action)
    }

    private static func toggleLinePrefix(
        _ snapshot: SourceSnapshot,
        range: NSRange,
        prefix: String,
        action: String
    ) -> SemanticEditResult {
        let ns = snapshot.text as NSString
        let line = lineRange(in: ns, containing: range)
        var content = ns.substring(with: line)
        let hadNewline = content.hasSuffix("\n")
        if hadNewline { content = String(content.dropLast()) }
        let stripped = stripKnownBlockPrefixes(content)
        let replacement: String
        if content.hasPrefix(prefix) {
            replacement = stripped + (hadNewline ? "\n" : "")
        } else {
            replacement = prefix + stripped + (hadNewline ? "\n" : "")
        }
        return commit(snapshot, range: line, replacement: replacement, action: action)
    }

    private static func toggleCodeFence(_ snapshot: SourceSnapshot, range: NSRange) -> SemanticEditResult {
        let ns = snapshot.text as NSString
        let line = lineRange(in: ns, containing: range)
        let content = ns.substring(with: line)
        if content.hasPrefix("```") {
            return .refused(.ambiguousSelection)
        }
        var body = content
        let hadNewline = body.hasSuffix("\n")
        if hadNewline { body = String(body.dropLast()) }
        let replacement = "```\n" + body + "\n```" + (hadNewline ? "\n" : "")
        return commit(snapshot, range: line, replacement: replacement, action: "Code Block")
    }

    private static func setLinkSource(
        _ snapshot: SourceSnapshot,
        range: NSRange,
        destination: String?
    ) -> SemanticEditResult {
        let ns = snapshot.text as NSString
        let selected = ns.substring(with: range)
        guard let destination else {
            // Remove link if selection looks like [text](url)
            if selected.hasPrefix("["), let close = selected.firstIndex(of: "]"),
               selected[selected.index(after: close)...].hasPrefix("("), selected.hasSuffix(")") {
                let text = String(selected[selected.index(after: selected.startIndex)..<close])
                return commit(snapshot, range: range, replacement: text, action: "Remove Link")
            }
            return .refused(.ambiguousSelection)
        }
        let label = selected.isEmpty ? destination : selected
        return commit(snapshot, range: range, replacement: "[\(label)](\(destination))", action: "Link")
    }

    private static func stripKnownBlockPrefixes(_ line: String) -> String {
        var s = line
        while true {
            if s.hasPrefix("> ") {
                s = String(s.dropFirst(2))
                continue
            }
            if let match = s.range(of: #"^#{1,6}\s+"#, options: .regularExpression) {
                s = String(s[match.upperBound...])
                continue
            }
            if s.hasPrefix("- [ ] ") || s.hasPrefix("- [x] ") || s.hasPrefix("- [X] ") {
                s = String(s.dropFirst(6))
                continue
            }
            if s.hasPrefix("- ") || s.hasPrefix("* ") || s.hasPrefix("+ ") {
                s = String(s.dropFirst(2))
                continue
            }
            if let match = s.range(of: #"^\d+[.)]\s+"#, options: .regularExpression) {
                s = String(s[match.upperBound...])
                continue
            }
            break
        }
        return s
    }

    private static func mapProjectionSelectionToSource(
        _ range: NSRange,
        projection: MarkdownProjectionModel
    ) -> NSRange? {
        let anchors = projection.sourceAnchors
        guard !anchors.isEmpty else { return nil }
        let startIdx = max(0, min(range.location, anchors.count - 1))
        let endIdx = max(0, min(NSMaxRange(range), anchors.count - 1))
        let start = anchors[startIdx]
        let end = anchors[endIdx]
        guard start >= 0, end >= start else { return nil }
        return NSRange(location: start, length: end - start)
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
            // Prefer replacing the first unchecked marker.
            if let r = slice.range(of: "[ ]") {
                replacement = slice.replacingCharacters(in: r, with: "[x]")
            } else {
                return .refused(.ambiguousSelection)
            }
        }
        return commit(snapshot, range: sourceRange, replacement: replacement, action: "Toggle Task")
    }

    private static func replaceNodeLiteral(
        snapshot: SourceSnapshot,
        tree: MarkdownTree?,
        nodeID: MarkdownNodeID,
        replacement: String,
        action: String
    ) -> SemanticEditResult {
        guard let tree, let node = findNode(id: nodeID, in: tree.root) else {
            return .refused(.mappingFailure)
        }
        let index = MarkdownSourceIndex(source: snapshot.text, sourceVersion: snapshot.sourceVersion)
        guard case .success(let sourceRange) = index.utf16Range(for: node.position) else {
            return .refused(.mappingFailure)
        }
        return commit(snapshot, range: sourceRange, replacement: replacement, action: action)
    }

    private static func findNode(id: MarkdownNodeID, in node: MarkdownNode) -> MarkdownNode? {
        if node.id == id { return node }
        for child in node.children {
            if let found = findNode(id: id, in: child) { return found }
        }
        return nil
    }
}
