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
        grouping: MutationGrouping = .discrete,
        selectionBefore: SourceSelection? = nil,
        intent: IntentContext? = nil,
        selectionAfter: SourceSelection? = nil,
        postcondition: @escaping @Sendable (MarkdownTree, String) -> Bool
    ) -> SemanticEditResult {
        let ns = snapshot.text as NSString
        guard range.location >= 0, NSMaxRange(range) <= ns.length else {
            return .refused(.invalidRange)
        }
        let newText = ns.replacingCharacters(in: range, with: replacement)
        let isValid = EditorSemanticWorker.sync(intent: intent) {
            guard case .success(let tree) = MarkdownParser.parse(
                newText,
                sourceVersion: snapshot.sourceVersion &+ 1,
                intent: intent
            ) else {
                return false
            }
            return postcondition(tree, newText)
        }
        guard isValid else { return .refused(.ambiguousSelection) }
        let before = selectionBefore ?? SourceSelection(utf16: range)
        guard let mutation = SourceMutation.exact(
            snapshot: snapshot,
            range: range,
            replacement: replacement,
            selectionBefore: before,
            selectionAfter: selectionAfter,
            actionName: action,
            grouping: grouping
        ) else {
            return .refused(.invalidRange)
        }
        return .mutation(mutation)
    }

    /// Caret at a concrete source position **inside** a rewritten block's own content.
    ///
    /// // REQ-113; COR-26: `SourceMutation.exact` otherwise defaults the post-command caret to
    /// // `range.location + replacement.length`. For a block rewrite whose replacement ends in a
    /// // newline that lands on the block *boundary* — the blank-line separator between blocks —
    /// // which has no exact projection preimage, so `planAuthoritativeTransition` refuses the
    /// // whole command with `mappingFailure`. Every block planner therefore states where its
    /// // rewritten content ends, and that offset is always inside the block's identity text.
    ///
    /// This rule exists once. Eleven inlined copies of the same arithmetic is the defect that
    /// produced COR-25 and then four more refusing commands.
    static func caretInsideContent(
        lineStart: Int,
        offsetInReplacement: Int,
        selectionBefore: SourceSelection?
    ) -> SourceSelection {
        SourceSelection(
            utf16: NSRange(location: lineStart + max(0, offsetInReplacement), length: 0),
            affinity: selectionBefore?.affinity ?? .downstream
        )
    }

    /// Length of `replacement` excluding its **complete** line terminator.
    ///
    /// // REQ-007/015; PR #32 review: subtracting a single UTF-16 unit is wrong for CRLF. It
    /// // places the caret between `\r` and `\n`, an offset belonging to neither the paragraph's
    /// // identity atom nor its synthetic break, so `planAuthoritativeTransition` still refuses
    /// // with `mappingFailure` — in exactly the CRLF documents REQ-007 requires this app to
    /// // preserve byte-for-byte.
    static func contentLength(of replacement: String) -> Int {
        trimmedLength(of: replacement)
    }

    /// UTF-16 length of `text` with one trailing CRLF, LF, or CR removed.
    static func trimmedLength(of text: String) -> Int {
        let ns = text as NSString
        var end = ns.length
        if end > 0, ns.character(at: end - 1) == 0x0A { end -= 1 }
        if end > 0, ns.character(at: end - 1) == 0x0D { end -= 1 }
        return end
    }
}

nonisolated enum InlineEditPlanner {
    static func wrap(
        snapshot: SourceSnapshot,
        range: NSRange,
        delimiters: [(String, String)],
        action: String,
        grouping: MutationGrouping = .discrete,
        selectionBefore: SourceSelection? = nil,
        intent: IntentContext? = nil,
        expectsKind: @escaping @Sendable (MarkdownNodeKind) -> Bool
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
                    action: action,
                    grouping: grouping,
                    selectionBefore: selectionBefore,
                    intent: intent
                ) { _, _ in true }
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
                            action: action,
                            grouping: grouping,
                            selectionBefore: selectionBefore,
                            intent: intent
                        ) { _, _ in true }
                    }
                }
            }
        }
        let (open, close) = delimiters.first { open, _ in !selected.contains(open) } ?? delimiters[0]
        let replacement = open + selected + close
        let cover = NSRange(location: range.location, length: (replacement as NSString).length)
        return SemanticPlannerGate.commitIfValid(
            snapshot: snapshot,
            range: range,
            replacement: replacement,
            action: action,
            grouping: grouping,
            selectionBefore: selectionBefore,
            intent: intent
        ) { tree, newText in
            containsKind(tree, source: newText, covering: cover, where: expectsKind)
        }
    }

    static func wrapCode(
        snapshot: SourceSnapshot,
        range: NSRange,
        grouping: MutationGrouping = .discrete,
        selectionBefore: SourceSelection? = nil,
        intent: IntentContext? = nil
    ) -> SemanticEditResult {
        let selected = (snapshot.text as NSString).substring(with: range)
        var ticks = "`"
        while selected.contains(ticks) { ticks += "`" }
        let replacement = ticks + selected + ticks
        let cover = NSRange(location: range.location, length: (replacement as NSString).length)
        return SemanticPlannerGate.commitIfValid(
            snapshot: snapshot,
            range: range,
            replacement: replacement,
            action: "Inline Code",
            grouping: grouping,
            selectionBefore: selectionBefore,
            intent: intent
        ) { tree, newText in
            containsKind(tree, source: newText, covering: cover) { kind in
                if case .code = kind { return true }
                return false
            }
        }
    }
}

nonisolated enum BlockEditPlanner {
    static func setHeading(
        snapshot: SourceSnapshot,
        range: NSRange,
        level: Int,
        grouping: MutationGrouping = .discrete,
        selectionBefore: SourceSelection? = nil,
        intent: IntentContext? = nil
    ) -> SemanticEditResult {
        let prefix = String(repeating: "#", count: max(1, min(level, 6))) + " "
        return transformLine(
            snapshot: snapshot,
            range: range,
            action: "Heading",
            grouping: grouping,
            selectionBefore: selectionBefore,
            intent: intent
        ) { content, hadNewline in
            let stripped = stripSameLineBlockChrome(content)
            return prefix + stripped + (hadNewline ? "\n" : "")
        } postcondition: { tree, _ in
            contains(tree.root) {
                if case .heading(let l) = $0.kind { return l == level }
                return false
            }
        }
    }

    static func setParagraph(
        snapshot: SourceSnapshot,
        range: NSRange,
        grouping: MutationGrouping = .discrete,
        selectionBefore: SourceSelection? = nil,
        intent: IntentContext? = nil
    ) -> SemanticEditResult {
        transformLine(
            snapshot: snapshot,
            range: range,
            action: "Paragraph",
            grouping: grouping,
            selectionBefore: selectionBefore,
            intent: intent
        ) { content, hadNewline in
            stripSameLineBlockChrome(content) + (hadNewline ? "\n" : "")
        } postcondition: { _, _ in true }
    }

    static func toggleCodeFence(
        snapshot: SourceSnapshot,
        range: NSRange,
        grouping: MutationGrouping = .discrete,
        selectionBefore: SourceSelection? = nil,
        intent: IntentContext? = nil
    ) -> SemanticEditResult {
        let ns = snapshot.text as NSString
        let line = ns.lineRange(for: range)
        let content = ns.substring(with: line)
        if content.hasPrefix("```") {
            return .refused(.ambiguousSelection)
        }
        var body = content
        let (trimmedBody, hadNewline, _) = body.crlfAwareTrimmingNewline()
        body = trimmedBody
        let openingFence = "```\n"
        let replacement = openingFence + body + "\n```" + (hadNewline ? "\n" : "")
        return SemanticPlannerGate.commitIfValid(
            snapshot: snapshot,
            range: line,
            replacement: replacement,
            action: "Code Block",
            grouping: grouping,
            selectionBefore: selectionBefore,
            intent: intent,
            // REQ-113; COR-26: the caret belongs at the end of the fenced *content*, not past
            // the closing fence. Both fences are synthetic in WYSIWYG, so a caret after the
            // closing fence has no exact projection preimage just as one past a trailing
            // newline does.
            selectionAfter: SemanticPlannerGate.caretInsideContent(
                lineStart: line.location,
                offsetInReplacement: (openingFence as NSString).length
                    + SemanticPlannerGate.trimmedLength(of: body),
                selectionBefore: selectionBefore
            )
        ) { tree, _ in
            contains(tree.root) { if case .codeBlock = $0.kind { return true }; return false }
        }
    }

    private static func transformLine(
        snapshot: SourceSnapshot,
        range: NSRange,
        action: String,
        grouping: MutationGrouping = .discrete,
        selectionBefore: SourceSelection? = nil,
        intent: IntentContext? = nil,
        transform: (String, Bool) -> String,
        postcondition: @escaping @Sendable (MarkdownTree, String) -> Bool
    ) -> SemanticEditResult {
        let ns = snapshot.text as NSString
        let line = ns.lineRange(for: range)
        var content = ns.substring(with: line)
        let (trimmedContent, hadNewline, _) = content.crlfAwareTrimmingNewline()
        content = trimmedContent
        let replacement = transform(content, hadNewline)
        return SemanticPlannerGate.commitIfValid(
            snapshot: snapshot,
            range: line,
            replacement: replacement,
            action: action,
            grouping: grouping,
            selectionBefore: selectionBefore,
            intent: intent,
            // REQ-113; COR-26: a heading's `#` chrome is synthetic in WYSIWYG, and even for a
            // plain paragraph the default caret would land past the line's newline on the block
            // boundary. Both refuse; the content end never does.
            selectionAfter: SemanticPlannerGate.caretInsideContent(
                lineStart: line.location,
                offsetInReplacement: SemanticPlannerGate.contentLength(of: replacement),
                selectionBefore: selectionBefore
            ),
            postcondition: postcondition
        )
    }
}

nonisolated enum ListEditPlanner {
    static func toggle(
        snapshot: SourceSnapshot,
        range: NSRange,
        prefix: String,
        action: String,
        grouping: MutationGrouping = .discrete,
        selectionBefore: SourceSelection? = nil,
        intent: IntentContext? = nil
    ) -> SemanticEditResult {
        let ns = snapshot.text as NSString
        let line = ns.lineRange(for: range)
        var content = ns.substring(with: line)
        let (trimmedContent, hadNewline, _) = content.crlfAwareTrimmingNewline()
        content = trimmedContent
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
            action: action,
            grouping: grouping,
            selectionBefore: selectionBefore,
            intent: intent,
            // REQ-113; COR-26: the list marker is synthetic in WYSIWYG, so the caret stays at
            // the concrete end of this rewritten line rather than past its newline.
            selectionAfter: SemanticPlannerGate.caretInsideContent(
                lineStart: line.location,
                offsetInReplacement: SemanticPlannerGate.contentLength(of: replacement),
                selectionBefore: selectionBefore
            )
        ) { _, _ in true }
    }

    static func toggleBlockQuote(
        snapshot: SourceSnapshot,
        range: NSRange,
        grouping: MutationGrouping = .discrete,
        selectionBefore: SourceSelection? = nil,
        intent: IntentContext? = nil
    ) -> SemanticEditResult {
        let ns = snapshot.text as NSString
        let line = ns.lineRange(for: range)
        var content = ns.substring(with: line)
        let (trimmedContent, hadNewline, _) = content.crlfAwareTrimmingNewline()
        content = trimmedContent
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
            action: "Quote",
            grouping: grouping,
            selectionBefore: selectionBefore,
            intent: intent,
            // REQ-113; COR-26: the `> ` marker is synthetic in WYSIWYG, same as a list marker.
            selectionAfter: SemanticPlannerGate.caretInsideContent(
                lineStart: line.location,
                offsetInReplacement: SemanticPlannerGate.contentLength(of: replacement),
                selectionBefore: selectionBefore
            )
        ) { _, _ in true }
    }
}

nonisolated enum LinkEditPlanner {
    static func setLink(
        snapshot: SourceSnapshot,
        range: NSRange,
        destination: String?,
        grouping: MutationGrouping = .discrete,
        selectionBefore: SourceSelection? = nil,
        intent: IntentContext? = nil
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
                    action: "Remove Link",
                    grouping: grouping,
                    selectionBefore: selectionBefore,
                    intent: intent
                ) { _, _ in true }
            }
            return .refused(.ambiguousSelection)
        }
        let label = selected.isEmpty ? "" : selected
        let replacement = "[\(label)](\(destination))"
        let cover = NSRange(location: range.location, length: (replacement as NSString).length)
        return SemanticPlannerGate.commitIfValid(
            snapshot: snapshot,
            range: range,
            replacement: replacement,
            action: "Link",
            grouping: grouping,
            selectionBefore: selectionBefore,
            intent: intent
        ) { tree, newText in
            containsKind(tree, source: newText, covering: cover) { kind in
                if case .link = kind { return true }
                return false
            }
        }
    }
}

nonisolated enum TableCellEditPlanner {
    static func replaceExactCell(
        snapshot: SourceSnapshot,
        tree: MarkdownTree?,
        sourceRange: NSRange,
        text: String,
        grouping: MutationGrouping,
        selectionBefore: SourceSelection,
        intent: IntentContext? = nil
    ) -> SemanticEditResult {
        guard sourceRange.location >= 0,
              NSMaxRange(sourceRange) <= (snapshot.text as NSString).length else {
            return .refused(.mappingFailure)
        }
        return replaceValidated(
            snapshot: snapshot,
            tree: tree,
            sourceRange: sourceRange,
            text: text,
            grouping: grouping,
            selectionBefore: selectionBefore,
            intent: intent
        )
    }

    static func replace(
        snapshot: SourceSnapshot,
        tree: MarkdownTree?,
        nodeID: MarkdownNodeID,
        text: String,
        grouping: MutationGrouping = .discrete,
        selectionBefore: SourceSelection? = nil,
        intent: IntentContext? = nil
    ) -> SemanticEditResult {
        guard let tree, let node = findNode(id: nodeID, in: tree.root) else {
            return .refused(.mappingFailure)
        }
        guard case .tableCell = node.kind else {
            return .refused(.unsupportedCommand)
        }
        let sourceRange: NSRange? = EditorSemanticWorker.sync(intent: intent) {
            let index = MarkdownSourceIndex(
                source: snapshot.text,
                sourceVersion: snapshot.sourceVersion
            )
            guard case .success(let range) = index.utf16Range(for: node.position) else {
                return nil
            }
            return range
        }
        guard let sourceRange else {
            return .refused(.mappingFailure)
        }
        return replaceValidated(
            snapshot: snapshot,
            tree: tree,
            sourceRange: sourceRange,
            text: text,
            grouping: grouping,
            selectionBefore: selectionBefore,
            intent: intent
        )
    }

    private static func replaceValidated(
        snapshot: SourceSnapshot,
        tree: MarkdownTree?,
        sourceRange: NSRange,
        text: String,
        grouping: MutationGrouping,
        selectionBefore: SourceSelection?,
        intent: IntentContext?
    ) -> SemanticEditResult {
        // Unescaped pipes / newlines change GFM table structure — refuse rather than accept
        // a vacuous postcondition. Escaped pipes (`\|`) are literal cell content.
        if containsUnescapedPipe(text) || text.contains("\n") || text.contains("\r") {
            return .refused(.ambiguousSelection)
        }
        guard let tree else { return .refused(.mappingFailure) }
        let beforeTables = countTables(in: tree.root)
        let beforeCells = countTableCells(in: tree.root)
        return SemanticPlannerGate.commitIfValid(
            snapshot: snapshot,
            range: sourceRange,
            replacement: text,
            action: "Edit Cell",
            grouping: grouping,
            selectionBefore: selectionBefore,
            intent: intent
        ) { newTree, newText in
            guard countTables(in: newTree.root) == beforeTables,
                  countTableCells(in: newTree.root) == beforeCells else {
                return false
            }
            // The replacement must appear as some cell's plain content at the edited span.
            let cover = NSRange(location: sourceRange.location, length: (text as NSString).length)
            return containsKind(newTree, source: newText, covering: cover) { kind in
                if case .tableCell = kind { return true }
                return false
            }
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

/// True when `text` contains a `|` that is not escaped by a preceding backslash.
private func containsUnescapedPipe(_ text: String) -> Bool {
    var i = text.startIndex
    while i < text.endIndex {
        if text[i] == "\\" {
            i = text.index(after: i)
            if i < text.endIndex {
                i = text.index(after: i)
            }
            continue
        }
        if text[i] == "|" { return true }
        i = text.index(after: i)
    }
    return false
}

private func containsKind(
    _ tree: MarkdownTree,
    source: String,
    covering range: NSRange,
    where expectsKind: @Sendable (MarkdownNodeKind) -> Bool
) -> Bool {
    let index = MarkdownSourceIndex(source: source, sourceVersion: tree.sourceVersion)
    func walk(_ node: MarkdownNode) -> Bool {
        if expectsKind(node.kind),
           case .success(let nodeRange) = index.utf16Range(for: node.position),
           rangesOverlapOrTouch(nodeRange, range) {
            return true
        }
        return node.children.contains(where: walk)
    }
    return walk(tree.root)
}

/// Non-empty ranges use intersection; a zero-length range (e.g. cleared table cell) matches
/// when the caret point lies inside or on the boundary of the other range.
private func rangesOverlapOrTouch(_ a: NSRange, _ b: NSRange) -> Bool {
    if a.length == 0 {
        return b.location <= a.location && a.location <= NSMaxRange(b)
    }
    if b.length == 0 {
        return a.location <= b.location && b.location <= NSMaxRange(a)
    }
    return NSIntersectionRange(a, b).length > 0
}

private func countTables(in node: MarkdownNode) -> Int {
    let selfCount: Int
    if case .table = node.kind { selfCount = 1 } else { selfCount = 0 }
    return selfCount + node.children.reduce(0) { $0 + countTables(in: $1) }
}

private func countTableCells(in node: MarkdownNode) -> Int {
    let selfCount: Int
    if case .tableCell = node.kind { selfCount = 1 } else { selfCount = 0 }
    return selfCount + node.children.reduce(0) { $0 + countTableCells(in: $1) }
}

private func findNode(id: MarkdownNodeID, in node: MarkdownNode) -> MarkdownNode? {
    if node.id == id { return node }
    for child in node.children {
        if let found = findNode(id: id, in: child) { return found }
    }
    return nil
}
