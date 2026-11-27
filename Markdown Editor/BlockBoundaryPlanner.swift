//
//  BlockBoundaryPlanner.swift
//  Markdown Editor
//

import Foundation

/// Return and Backspace at block boundaries in WYSIWYG, planned from the source structure.
///
/// A typed line break is not a paragraph in Markdown: inserted as text it became a soft break
/// inside the paragraph, which the projection cannot show, and Return was refused
/// (`mappingFailure`, agent-drive tour 45957180019). Backspace at the start of a block met a
/// synthetic break whose source is not one character. Both are planned here as the source
/// change a Markdown writer would make, and the exact next presentation is built from it
/// (`SemanticEditEngine.planAuthoritativeTransition`).
///
/// Return, by the block the caret is in:
/// - a code block: a line break, keeping the line's indentation;
/// - a table: refused;
/// - a list item: the next item, with the same marker (a number one higher) and a fresh task
///   box for a task; in an empty item, the list ends and an empty paragraph follows;
/// - at the start of a paragraph or heading: an empty paragraph before it;
/// - anywhere else, quotes included: a new paragraph (two line breaks).
///
/// Backspace at the start of a block:
/// - in an empty paragraph, or after one: the empty paragraph goes;
/// - at a list item's text: the marker goes and the text becomes a paragraph;
/// - at a heading's text: the heading becomes a paragraph;
/// - at a paragraph: it joins the paragraph or heading before it, or the rule before it goes.
nonisolated enum BlockBoundaryPlanner {

    // MARK: - Return

    static func paragraphBreak(
        selection: ProjectionSelection,
        snapshot: SourceSnapshot,
        presentation: PresentationSnapshot,
        tree: MarkdownTree?,
        grouping: MutationGrouping,
        intent: IntentContext? = nil
    ) -> SemanticEditResult {
        guard case .exact(let range) = presentation.coordinateMap.sourceRange(
            forProjection: selection.range.utf16,
            affinity: selection.affinity
        ) else { return .refused(.mappingFailure) }
        guard let context = Context(snapshot: snapshot, tree: tree) else { return .refused(.mappingFailure) }
        let before = SourceSelection(utf16: range, affinity: selection.affinity)
        let newline = context.lineEnding
        let chain = context.chain(at: range.location)

        func commit(_ target: NSRange, _ replacement: String, caret: Int? = nil) -> SemanticEditResult {
            SemanticEditEngine.commit(
                snapshot,
                range: target,
                replacement: replacement,
                action: UndoActionName.typing.title,
                grouping: grouping,
                selectionBefore: before,
                selectionAfter: caret.map { SourceSelection(utf16: NSRange(location: $0, length: 0), affinity: selection.affinity) },
                intent: intent
            )
        }

        if chain.contains(where: { $0.isTable }) { return .refused(.unsupportedCommand) }

        if chain.contains(where: { $0.isCodeBlock }) {
            let quoteDepth = chain.filter(\.isBlockQuote).count
            let lineStart = context.lineStart(of: range.location)
            var index = lineStart
            var quotes = 0
            while index < range.location {
                let c = context.source.character(at: index)
                if c == Context.space || c == Context.tab { index += 1; continue }
                if c == Context.quoteMarker, quotes < quoteDepth { quotes += 1; index += 1; continue }
                break
            }
            let indentation = context.source.substring(with: NSRange(location: lineStart, length: index - lineStart))
            return commit(range, newline + indentation)
        }

        if let item = context.listItem(around: range.location, chain: chain) {
            if item.isEmpty, range.length == 0 {
                // Return in an empty item ends the list: the item's line becomes the blank line
                // before a new empty paragraph.
                return commit(NSRange(location: item.lineStart, length: item.lineEnd - item.lineStart), newline)
            }
            let blankLine = item.isLoose ? item.prefix.trimmingTrailingBlanks + newline : ""
            let continuation = newline + blankLine + item.prefix + item.nextMarker
            if range.length == 0, range.location < item.contentStart {
                return commit(NSRange(location: item.contentStart, length: 0), continuation)
            }
            return commit(range, continuation)
        }

        if range.length == 0,
           let leaf = chain.last,
           leaf.isParagraph || leaf.isHeading,
           let contentStart = context.contentStart(of: leaf),
           range.location == contentStart,
           contentStart < NSMaxRange(leaf.range) {
            // Return before a block's text opens an empty paragraph above it and leaves the
            // block, and the caret, as they were.
            let lineStart = context.lineStart(of: leaf.range.location)
            let inserted = newline + newline
            return commit(
                NSRange(location: lineStart, length: 0),
                inserted,
                caret: range.location + (inserted as NSString).length
            )
        }

        return commit(range, newline + newline)
    }

    // MARK: - Backspace

    /// Whether Backspace with the caret at `caret` deletes a block boundary: the character before
    /// it is a paragraph break, an empty paragraph, or a list item's marker or task box.
    static func deletesBlockBoundary(atCaret caret: Int, in presentation: PresentationSnapshot) -> Bool {
        guard caret > 0 else { return false }
        let previous = caret - 1
        for segment in presentation.coordinateMap.segments {
            let range = segment.projectionRange
            guard range.location <= previous, previous < NSMaxRange(range) else { continue }
            guard case .synthetic(_, let kind, _) = segment else { return false }
            switch kind {
            case .paragraphBreak, .listMarker, .taskCheckbox:
                return true
            case .thematicBreak, .tableCellSeparator, .tableRowBreak, .attachmentPlaceholder,
                 .softLineBreak, .hardLineBreak:
                return false
            }
        }
        return false
    }

    static func joinBackward(
        selection: ProjectionSelection,
        snapshot: SourceSnapshot,
        presentation: PresentationSnapshot,
        tree: MarkdownTree?,
        grouping: MutationGrouping,
        intent: IntentContext? = nil
    ) -> SemanticEditResult {
        let projectionCaret = selection.range.utf16
        guard projectionCaret.length == 0 else { return .refused(.ambiguousSelection) }
        // The caret's own position, not the end of the break before it: downstream.
        guard case .exact(let caretRange) = presentation.coordinateMap.sourceRange(
            forProjection: projectionCaret,
            affinity: .downstream
        ) else { return .refused(.mappingFailure) }
        guard let context = Context(snapshot: snapshot, tree: tree) else { return .refused(.mappingFailure) }
        let caret = caretRange.location
        let before = SourceSelection(utf16: NSRange(location: caret, length: 0), affinity: selection.affinity)
        let source = context.source

        func remove(_ target: NSRange, replacement: String = "", caret after: Int) -> SemanticEditResult {
            SemanticEditEngine.commit(
                snapshot,
                range: target,
                replacement: replacement,
                action: UndoActionName.delete.title,
                grouping: grouping,
                selectionBefore: before,
                selectionAfter: SourceSelection(utf16: NSRange(location: after, length: 0), affinity: selection.affinity),
                intent: intent
            )
        }

        // In an empty paragraph: it goes, with the two line breaks that made it.
        if context.emptyParagraphSlots.contains(where: { $0.before == caret || $0.after == caret }) {
            // A single blank line before the first block shows as one too.
            guard let breaks = context.lineBreaks(before: caret, count: 2) ?? context.lineBreaks(before: caret, count: 1) else {
                return .refused(.mappingFailure)
            }
            return remove(breaks, caret: breaks.location)
        }

        let chain = context.chain(at: caret)

        // At a list item's text: the marker goes. After another line the text keeps a blank line
        // above it, so it becomes a paragraph of its own rather than a continuation.
        if let item = context.listItem(around: caret, chain: chain), caret == item.contentStart {
            let previousLineBlank = item.lineStart == 0 || context.isBlankLine(before: item.lineStart)
            let replacement = previousLineBlank ? "" : context.lineEnding + item.prefix
            return remove(
                NSRange(location: item.markerStart, length: item.contentStart - item.markerStart),
                replacement: replacement,
                caret: item.markerStart + (replacement as NSString).length
            )
        }

        guard let leaf = chain.last, let contentStart = context.contentStart(of: leaf), caret == contentStart else {
            return .refused(.unsupportedCommand)
        }

        // At a heading's text: it becomes a paragraph.
        if leaf.isHeading {
            guard source.character(at: leaf.range.location) == Context.hash else { return .refused(.unsupportedCommand) }
            return remove(
                NSRange(location: leaf.range.location, length: contentStart - leaf.range.location),
                caret: leaf.range.location
            )
        }
        guard leaf.isParagraph, let top = chain.first else { return .refused(.unsupportedCommand) }

        let previousLeaf: Located?
        if let first = context.firstLeaf(of: top), first.node.id == leaf.node.id {
            guard let index = context.topLevel.firstIndex(where: { $0.node.id == top.node.id }) else {
                return .refused(.mappingFailure)
            }
            let previousEnd = index > 0 ? NSMaxRange(context.topLevel[index - 1].range) : nil
            // After an empty paragraph: that paragraph goes, and this one moves up.
            if !EmptyParagraphLayout.slots(in: source, previousEnd: previousEnd, nextStart: top.range.location).isEmpty {
                let lineStart = context.lineStart(of: top.range.location)
                guard let breaks = context.lineBreaks(before: lineStart, count: 2) ?? context.lineBreaks(before: lineStart, count: 1) else {
                    return .refused(.mappingFailure)
                }
                return remove(breaks, caret: caret - breaks.length)
            }
            guard index > 0 else { return .refused(.unsupportedCommand) }
            let previous = context.topLevel[index - 1]
            if previous.isThematicBreak {
                let lineStart = context.lineStart(of: top.range.location)
                let rule = NSRange(location: previous.range.location, length: lineStart - previous.range.location)
                return remove(rule, caret: caret - rule.length)
            }
            previousLeaf = context.lastLeaf(of: previous)
        } else {
            previousLeaf = context.leaf(before: leaf, within: top)
        }

        // At a paragraph: it joins the paragraph or heading before it.
        guard let previousLeaf, previousLeaf.isParagraph || previousLeaf.isHeading else {
            return .refused(.unsupportedCommand)
        }
        var joinStart = min(NSMaxRange(previousLeaf.range), caret)
        while joinStart > previousLeaf.range.location, Context.isLineBreak(source.character(at: joinStart - 1)) {
            joinStart -= 1
        }
        let gap = NSRange(location: joinStart, length: caret - joinStart)
        for index in gap.location..<NSMaxRange(gap) {
            let c = source.character(at: index)
            guard Context.isLineBreak(c) || c == Context.space || c == Context.tab || c == Context.quoteMarker else {
                return .refused(.unsupportedCommand)
            }
        }
        return remove(gap, caret: joinStart)
    }

    // MARK: - Structure

    nonisolated struct Located {
        let node: MarkdownNode
        let range: NSRange

        var isTable: Bool { if case .table = node.kind { return true }; return false }
        var isCodeBlock: Bool { if case .codeBlock = node.kind { return true }; return false }
        var isBlockQuote: Bool { if case .blockQuote = node.kind { return true }; return false }
        var isItem: Bool { if case .item = node.kind { return true }; return false }
        var isParagraph: Bool { if case .paragraph = node.kind { return true }; return false }
        var isHeading: Bool { if case .heading = node.kind { return true }; return false }
        var isThematicBreak: Bool { if case .thematicBreak = node.kind { return true }; return false }
        var isLeaf: Bool { isParagraph || isHeading || isCodeBlock || isTable || isThematicBreak || isHTML }
        var isHTML: Bool { if case .htmlBlock = node.kind { return true }; return false }
        var isBlock: Bool {
            switch node.kind {
            case .blockQuote, .list, .item, .codeBlock, .htmlBlock, .paragraph, .heading,
                 .thematicBreak, .table:
                return true
            default:
                return false
            }
        }
    }

    /// A list item's marker as its source spells it, found from the tree or, for an item with no
    /// text, from its line: cmark's span for an empty item need not reach the caret.
    nonisolated struct ListItemLine {
        let lineStart: Int
        let lineEnd: Int
        /// Quote markers and indentation before the marker, copied to the next item.
        let prefix: String
        let markerStart: Int
        let contentStart: Int
        /// The next item's marker, its spacing and, for a task, an unchecked box.
        let nextMarker: String
        let isEmpty: Bool
        let isLoose: Bool
    }

    nonisolated struct Context {
        static let space: unichar = 0x20
        static let tab: unichar = 0x09
        static let quoteMarker: unichar = 0x3E // >
        static let hash: unichar = 0x23
        static func isLineBreak(_ c: unichar) -> Bool { c == 0x0A || c == 0x0D }

        let source: NSString
        let index: MarkdownSourceIndex
        let root: MarkdownNode
        let topLevel: [Located]

        init?(snapshot: SourceSnapshot, tree: MarkdownTree?) {
            let current: MarkdownTree
            if let tree, tree.sourceVersion == snapshot.sourceVersion {
                current = tree
            } else {
                guard case .success(let parsed) = MarkdownParser.parse(snapshot.text, sourceVersion: snapshot.sourceVersion) else {
                    return nil
                }
                current = parsed
            }
            let sourceIndex = MarkdownSourceIndex(source: snapshot.text, sourceVersion: snapshot.sourceVersion)
            source = snapshot.text as NSString
            index = sourceIndex
            root = current.root
            topLevel = current.root.children.compactMap { child in
                guard case .success(let range) = sourceIndex.utf16Range(for: child.position) else { return nil }
                return Located(node: child, range: range)
            }
        }

        var lineEnding: String {
            let newline = source.range(of: "\n")
            if newline.location != NSNotFound, newline.location > 0, source.character(at: newline.location - 1) == 0x0D {
                return "\r\n"
            }
            return "\n"
        }

        func located(_ node: MarkdownNode) -> Located? {
            guard case .success(let range) = index.utf16Range(for: node.position) else { return nil }
            return Located(node: node, range: range)
        }

        /// The blocks containing `location`, outermost first, the document itself left out.
        func chain(at location: Int) -> [Located] {
            var result: [Located] = []
            var children = root.children
            while true {
                guard let next = children.lazy.compactMap({ located($0) }).first(where: {
                    $0.isBlock && $0.range.location <= location && location <= NSMaxRange($0.range)
                }) else { break }
                result.append(next)
                if next.isLeaf { break }
                children = next.node.children
            }
            return result
        }

        var emptyParagraphSlots: [EmptyParagraphLayout.Slot] {
            if topLevel.isEmpty {
                return EmptyParagraphLayout.slots(in: source, previousEnd: nil, nextStart: nil)
            }
            var slots: [EmptyParagraphLayout.Slot] = []
            var previousEnd: Int?
            for block in topLevel {
                slots += EmptyParagraphLayout.slots(in: source, previousEnd: previousEnd, nextStart: block.range.location)
                previousEnd = NSMaxRange(block.range)
            }
            slots += EmptyParagraphLayout.slots(in: source, previousEnd: previousEnd, nextStart: nil)
            return slots
        }

        func lineStart(of location: Int) -> Int {
            var start = min(max(location, 0), source.length)
            while start > 0, !Self.isLineBreak(source.character(at: start - 1)) { start -= 1 }
            return start
        }

        func lineEnd(from location: Int) -> Int {
            var end = min(max(location, 0), source.length)
            while end < source.length, !Self.isLineBreak(source.character(at: end)) { end += 1 }
            return end
        }

        /// The `count` line breaks that end just before `location`, CRLF counted as one.
        func lineBreaks(before location: Int, count: Int) -> NSRange? {
            var start = location
            for _ in 0..<count {
                guard start > 0 else { return nil }
                let c = source.character(at: start - 1)
                if c == 0x0A {
                    start -= 1
                    if start > 0, source.character(at: start - 1) == 0x0D { start -= 1 }
                } else if c == 0x0D {
                    start -= 1
                } else {
                    return nil
                }
            }
            return NSRange(location: start, length: location - start)
        }

        /// Whether the line before the one starting at `lineStart` holds nothing but quote
        /// markers and blanks.
        func isBlankLine(before lineStart: Int) -> Bool {
            guard let breaks = lineBreaks(before: lineStart, count: 1) else { return true }
            let start = self.lineStart(of: breaks.location)
            for index in start..<breaks.location {
                let c = source.character(at: index)
                guard c == Self.space || c == Self.tab || c == Self.quoteMarker else { return false }
            }
            return true
        }

        /// Where a paragraph's or heading's text starts: after an ATX heading's `#`s and the
        /// blanks that follow them.
        func contentStart(of leaf: Located) -> Int? {
            if leaf.isParagraph { return leaf.range.location }
            guard leaf.isHeading else { return nil }
            var index = leaf.range.location
            let end = lineEnd(from: index)
            guard index < end, source.character(at: index) == Self.hash else { return index }
            while index < end, source.character(at: index) == Self.hash { index += 1 }
            while index < end, source.character(at: index) == Self.space || source.character(at: index) == Self.tab { index += 1 }
            return index
        }

        /// Whether anything but blanks and line breaks stands in `from..<to`.
        func hasText(from: Int, to: Int) -> Bool {
            let end = min(to, source.length)
            guard from < end else { return false }
            for index in from..<end {
                let c = source.character(at: index)
                if !(Self.isLineBreak(c) || c == Self.space || c == Self.tab) { return true }
            }
            return false
        }

        func firstLeaf(of block: Located) -> Located? {
            if block.isLeaf { return block }
            for child in block.node.children {
                if let child = located(child), child.isBlock, let leaf = firstLeaf(of: child) { return leaf }
            }
            return nil
        }

        func lastLeaf(of block: Located) -> Located? {
            if block.isLeaf { return block }
            for child in block.node.children.reversed() {
                if let child = located(child), child.isBlock, let leaf = lastLeaf(of: child) { return leaf }
            }
            return nil
        }

        /// The leaf block that comes just before `leaf` in document order, inside `block`.
        func leaf(before leaf: Located, within block: Located) -> Located? {
            var leaves: [Located] = []
            func collect(_ node: Located) {
                if node.isLeaf { leaves.append(node); return }
                for child in node.node.children {
                    if let child = located(child), child.isBlock { collect(child) }
                }
            }
            collect(block)
            guard let position = leaves.firstIndex(where: { $0.node.id == leaf.node.id }), position > 0 else { return nil }
            return leaves[position - 1]
        }

        /// The list item whose line holds `location`, if the caret is in one.
        func listItem(around location: Int, chain: [Located]) -> ListItemLine? {
            if let item = chain.last(where: \.isItem) {
                let list = chain.last(where: { if case .list = $0.node.kind { return true }; return false })
                let isLoose: Bool = {
                    if case .list(let info) = list?.node.kind { return !info.tight }
                    return false
                }()
                return itemLine(markerAt: item.range.location, isLoose: isLoose, itemEnd: NSMaxRange(item.range))
            }
            // An item with no text: its line alone says so.
            let lineStart = self.lineStart(of: location)
            var markerStart = lineStart
            while markerStart < location {
                let c = source.character(at: markerStart)
                guard c == Self.space || c == Self.tab || c == Self.quoteMarker else { break }
                markerStart += 1
            }
            guard let line = itemLine(markerAt: markerStart, isLoose: false, itemEnd: nil),
                  line.isEmpty, location >= line.contentStart else { return nil }
            return line
        }

        /// `itemEnd` is where the item's source ends, when the tree says: an item whose first line
        /// is empty but which goes on below it is not empty.
        private func itemLine(markerAt markerStart: Int, isLoose: Bool, itemEnd: Int?) -> ListItemLine? {
            let lineStart = self.lineStart(of: markerStart)
            let lineEnd = self.lineEnd(from: markerStart)
            guard markerStart < lineEnd else { return nil }
            var index = markerStart
            let first = source.character(at: index)
            let marker: String
            if first == 0x2D || first == 0x2A || first == 0x2B { // - * +
                marker = String(utf16CodeUnits: [first], count: 1)
                index += 1
            } else {
                var digits = ""
                while index < lineEnd, digits.count < 9,
                      let scalar = Unicode.Scalar(source.character(at: index)),
                      CharacterSet.decimalDigits.contains(scalar),
                      scalar.isASCII {
                    digits.append(Character(scalar))
                    index += 1
                }
                guard !digits.isEmpty, index < lineEnd, let number = Int(digits) else { return nil }
                let delimiter = source.character(at: index)
                guard delimiter == 0x2E || delimiter == 0x29 else { return nil } // . )
                marker = "\(number + 1)" + String(utf16CodeUnits: [delimiter], count: 1)
                index += 1
            }
            // A marker is followed by blanks, or ends its line.
            let spacingStart = index
            while index < lineEnd, source.character(at: index) == Self.space || source.character(at: index) == Self.tab { index += 1 }
            guard index > spacingStart || index == lineEnd else { return nil }
            var spacing = source.substring(with: NSRange(location: spacingStart, length: index - spacingStart))
            if spacing.isEmpty || spacing.count > 4 { spacing = " " }
            var contentStart = index
            var task = false
            if contentStart + 3 <= lineEnd,
               source.character(at: contentStart) == 0x5B, // [
               [0x20, 0x78, 0x58].contains(source.character(at: contentStart + 1)), // space x X
               source.character(at: contentStart + 2) == 0x5D, // ]
               contentStart + 3 == lineEnd || source.character(at: contentStart + 3) == Self.space {
                task = true
                contentStart += 3
                while contentStart < lineEnd, source.character(at: contentStart) == Self.space { contentStart += 1 }
            }
            var textEnd = lineEnd
            while textEnd > contentStart, source.character(at: textEnd - 1) == Self.space || source.character(at: textEnd - 1) == Self.tab {
                textEnd -= 1
            }
            let prefix = source.substring(with: NSRange(location: lineStart, length: markerStart - lineStart))
            return ListItemLine(
                lineStart: lineStart,
                lineEnd: lineEnd,
                prefix: prefix,
                markerStart: markerStart,
                contentStart: contentStart,
                nextMarker: marker + spacing + (task ? "[ ] " : ""),
                isEmpty: textEnd == contentStart && (itemEnd.map { !hasText(from: lineEnd, to: $0) } ?? true),
                isLoose: isLoose
            )
        }
    }
}

private extension String {
    var trimmingTrailingBlanks: String {
        var result = self
        while let last = result.last, last == " " || last == "\t" { result.removeLast() }
        return result
    }
}
