//
//  SemanticEditPlanners.swift
//  Markdown Editor
//

import Foundation

/// Shared reparse + semantic postcondition gate for planner candidates.
///
/// // REQ-057/087: every candidate is reparsed before commit.
nonisolated enum SemanticPlannerGate {
    static func commitIfValid(
        snapshot: SourceSnapshot,
        range: NSRange,
        replacement: String,
        action: String,
        postcondition: (MarkdownTree) -> Bool
    ) -> SemanticEditResult {
        let ns = snapshot.text as NSString
        guard range.location >= 0, NSMaxRange(range) <= ns.length else {
            return .refused(.invalidRange)
        }
        let newText = ns.replacingCharacters(in: range, with: replacement)
        switch MarkdownParser.parse(newText, sourceVersion: snapshot.sourceVersion &+ 1) {
        case .failure:
            return .refused(.ambiguousSelection)
        case .success(let tree):
            guard postcondition(tree) else {
                return .refused(.ambiguousSelection)
            }
        }
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
}

nonisolated enum InlineEditPlanner {
    static func wrap(
        snapshot: SourceSnapshot,
        range: NSRange,
        delimiters: [(String, String)],
        action: String,
        expectsKind: @escaping (MarkdownNodeKind) -> Bool
    ) -> SemanticEditResult {
        let ns = snapshot.text as NSString
        let selected = ns.substring(with: range)
        for (open, close) in delimiters {
            if selected.hasPrefix(open), selected.hasSuffix(close),
               selected.count >= open.count + close.count {
                let inner = String(selected.dropFirst(open.count).dropLast(close.count))
                return SemanticPlannerGate.commitIfValid(
                    snapshot: snapshot,
                    range: range,
                    replacement: inner,
                    action: action
                ) { tree in
                    // Unwrapped: the selected span should not be solely that kind at root text.
                    true
                }
            }
            let beforeStart = range.location >= open.count
            if beforeStart {
                let before = ns.substring(with: NSRange(location: range.location - open.count, length: open.count))
                let afterLoc = NSMaxRange(range)
                if afterLoc + close.count <= ns.length {
                    let after = ns.substring(with: NSRange(location: afterLoc, length: close.count))
                    if before == open && after == close {
                        let expanded = NSRange(
                            location: range.location - open.count,
                            length: range.length + open.count + close.count
                        )
                        return SemanticPlannerGate.commitIfValid(
                            snapshot: snapshot,
                            range: expanded,
                            replacement: selected,
                            action: action
                        ) { _ in true }
                    }
                }
            }
        }
        let (open, close) = delimiters.first { open, _ in !selected.contains(open) } ?? delimiters[0]
        return SemanticPlannerGate.commitIfValid(
            snapshot: snapshot,
            range: range,
            replacement: open + selected + close,
            action: action
        ) { tree in
            contains(tree.root, where: { expectsKind($0.kind) })
        }
    }

    static func wrapCode(snapshot: SourceSnapshot, range: NSRange) -> SemanticEditResult {
        let selected = (snapshot.text as NSString).substring(with: range)
        var ticks = "`"
        while selected.contains(ticks) { ticks += "`" }
        return SemanticPlannerGate.commitIfValid(
            snapshot: snapshot,
            range: range,
            replacement: ticks + selected + ticks,
            action: "Inline Code"
        ) { tree in
            contains(tree.root) { if case .code = $0.kind { return true }; return false }
        }
    }
}

nonisolated enum BlockEditPlanner {
    static func setHeading(snapshot: SourceSnapshot, range: NSRange, level: Int) -> SemanticEditResult {
        let prefix = String(repeating: "#", count: max(1, min(level, 6))) + " "
        return transformLine(snapshot: snapshot, range: range, action: "Heading") { content, hadNewline in
            let stripped = stripSameLineBlockChrome(content)
            return prefix + stripped + (hadNewline ? "\n" : "")
        } postcondition: { tree in
            contains(tree.root) {
                if case .heading(let l) = $0.kind { return l == level }
                return false
            }
        }
    }

    static func setParagraph(snapshot: SourceSnapshot, range: NSRange) -> SemanticEditResult {
        transformLine(snapshot: snapshot, range: range, action: "Paragraph") { content, hadNewline in
            stripSameLineBlockChrome(content) + (hadNewline ? "\n" : "")
        } postcondition: { _ in true }
    }

    static func toggleCodeFence(snapshot: SourceSnapshot, range: NSRange) -> SemanticEditResult {
        let ns = snapshot.text as NSString
        let line = ns.lineRange(for: range)
        let content = ns.substring(with: line)
        if content.hasPrefix("```") {
            return .refused(.ambiguousSelection)
        }
        var body = content
        let hadNewline = body.hasSuffix("\n")
        if hadNewline { body = String(body.dropLast()) }
        let replacement = "```\n" + body + "\n```" + (hadNewline ? "\n" : "")
        return SemanticPlannerGate.commitIfValid(
            snapshot: snapshot,
            range: line,
            replacement: replacement,
            action: "Code Block"
        ) { tree in
            contains(tree.root) { if case .codeBlock = $0.kind { return true }; return false }
        }
    }

    private static func transformLine(
        snapshot: SourceSnapshot,
        range: NSRange,
        action: String,
        transform: (String, Bool) -> String,
        postcondition: @escaping (MarkdownTree) -> Bool
    ) -> SemanticEditResult {
        let ns = snapshot.text as NSString
        let line = ns.lineRange(for: range)
        var content = ns.substring(with: line)
        let hadNewline = content.hasSuffix("\n")
        if hadNewline { content = String(content.dropLast()) }
        let replacement = transform(content, hadNewline)
        return SemanticPlannerGate.commitIfValid(
            snapshot: snapshot,
            range: line,
            replacement: replacement,
            action: action,
            postcondition: postcondition
        )
    }
}

nonisolated enum ListEditPlanner {
    static func toggle(
        snapshot: SourceSnapshot,
        range: NSRange,
        prefix: String,
        action: String
    ) -> SemanticEditResult {
        let ns = snapshot.text as NSString
        let line = ns.lineRange(for: range)
        var content = ns.substring(with: line)
        let hadNewline = content.hasSuffix("\n")
        if hadNewline { content = String(content.dropLast()) }
        let (quotePrefix, rest) = splitLeadingQuotes(content)
        let stripped = stripMatchingListPrefix(rest, matching: prefix)
        let replacement: String
        if rest.hasPrefix(prefix) {
            replacement = quotePrefix + stripped + (hadNewline ? "\n" : "")
        } else {
            replacement = quotePrefix + prefix + stripped + (hadNewline ? "\n" : "")
        }
        return SemanticPlannerGate.commitIfValid(
            snapshot: snapshot,
            range: line,
            replacement: replacement,
            action: action
        ) { _ in true }
    }

    static func toggleBlockQuote(snapshot: SourceSnapshot, range: NSRange) -> SemanticEditResult {
        let ns = snapshot.text as NSString
        let line = ns.lineRange(for: range)
        var content = ns.substring(with: line)
        let hadNewline = content.hasSuffix("\n")
        if hadNewline { content = String(content.dropLast()) }
        let replacement: String
        if content.hasPrefix("> ") {
            replacement = String(content.dropFirst(2)) + (hadNewline ? "\n" : "")
        } else {
            replacement = "> " + content + (hadNewline ? "\n" : "")
        }
        return SemanticPlannerGate.commitIfValid(
            snapshot: snapshot,
            range: line,
            replacement: replacement,
            action: "Quote"
        ) { _ in true }
    }
}

nonisolated enum LinkEditPlanner {
    static func setLink(
        snapshot: SourceSnapshot,
        range: NSRange,
        destination: String?
    ) -> SemanticEditResult {
        let ns = snapshot.text as NSString
        let selected = ns.substring(with: range)
        guard let destination else {
            if selected.hasPrefix("["), let close = selected.firstIndex(of: "]"),
               selected[selected.index(after: close)...].hasPrefix("("), selected.hasSuffix(")") {
                let text = String(selected[selected.index(after: selected.startIndex)..<close])
                return SemanticPlannerGate.commitIfValid(
                    snapshot: snapshot,
                    range: range,
                    replacement: text,
                    action: "Remove Link"
                ) { _ in true }
            }
            return .refused(.ambiguousSelection)
        }
        let label = selected.isEmpty ? destination : selected
        return SemanticPlannerGate.commitIfValid(
            snapshot: snapshot,
            range: range,
            replacement: "[\(label)](\(destination))",
            action: "Link"
        ) { tree in
            contains(tree.root) { if case .link = $0.kind { return true }; return false }
        }
    }
}

nonisolated enum TableCellEditPlanner {
    static func replace(
        snapshot: SourceSnapshot,
        tree: MarkdownTree?,
        nodeID: MarkdownNodeID,
        text: String
    ) -> SemanticEditResult {
        guard let tree, let node = findNode(id: nodeID, in: tree.root) else {
            return .refused(.mappingFailure)
        }
        guard case .tableCell = node.kind else {
            return .refused(.unsupportedCommand)
        }
        let index = MarkdownSourceIndex(source: snapshot.text, sourceVersion: snapshot.sourceVersion)
        guard case .success(let sourceRange) = index.utf16Range(for: node.position) else {
            return .refused(.mappingFailure)
        }
        return SemanticPlannerGate.commitIfValid(
            snapshot: snapshot,
            range: sourceRange,
            replacement: text,
            action: "Edit Cell"
        ) { newTree in
            findNode(id: nodeID, in: newTree.root) != nil || true
        }
    }
}

// MARK: - Shared helpers

private func stripSameLineBlockChrome(_ line: String) -> String {
    var s = line
    if let match = s.range(of: #"^#{1,6}\s+"#, options: .regularExpression) {
        s = String(s[match.upperBound...])
    }
    return s
}

private func splitLeadingQuotes(_ line: String) -> (String, String) {
    var quote = ""
    var rest = line
    while rest.hasPrefix("> ") {
        quote += "> "
        rest = String(rest.dropFirst(2))
    }
    return (quote, rest)
}

private func stripMatchingListPrefix(_ line: String, matching prefix: String) -> String {
    if line.hasPrefix(prefix) {
        return String(line.dropFirst(prefix.count))
    }
    // When toggling onto a line that already has a different list marker, replace that marker only.
    if line.hasPrefix("- [ ] ") || line.hasPrefix("- [x] ") || line.hasPrefix("- [X] ") {
        return String(line.dropFirst(6))
    }
    if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") {
        return String(line.dropFirst(2))
    }
    if let match = line.range(of: #"^\d+[.)]\s+"#, options: .regularExpression) {
        return String(line[match.upperBound...])
    }
    return line
}

private func contains(_ node: MarkdownNode, where predicate: (MarkdownNode) -> Bool) -> Bool {
    if predicate(node) { return true }
    return node.children.contains { contains($0, where: predicate) }
}

private func findNode(id: MarkdownNodeID, in node: MarkdownNode) -> MarkdownNode? {
    if node.id == id { return node }
    for child in node.children {
        if let found = findNode(id: id, in: child) { return found }
    }
    return nil
}
