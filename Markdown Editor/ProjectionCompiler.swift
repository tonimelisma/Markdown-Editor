//
//  ProjectionCompiler.swift
//  Markdown Editor
//

import Foundation

/// Compiles a parsed tree + concrete source into a delimiter-free projection with typed segments.
///
/// // REQ-054–056/080/087: no proportional mapping; formal-GFM + literal fallback.
nonisolated enum ProjectionCompiler {
    static func compile(
        tree: MarkdownTree,
        map: SourceCoordinateMap
    ) -> MarkdownProjectionModel {
        var builder = CompilerBuilder(map: map, sourceVersion: tree.sourceVersion)
        builder.emit(tree.root, styleStack: [], listNesting: 0)
        return builder.finish()
    }
}

// MARK: - Builder

private nonisolated struct CompilerBuilder {
    let map: SourceCoordinateMap
    let sourceVersion: UInt64

    private var pieces: [String] = []
    private var runs: [ProjectionRun] = []
    private var attachments: [ProjectionAttachment] = []
    private var tables: [ProjectionTable] = []
    private var blocks: [PresentationBlock] = []
    private var segments: [ProjectionSegment] = []
    private var listMarkers: [ProjectionListMarker] = []
    private var utf16Length = 0
    /// Where the last source-backed piece ended, for a synthetic break whose node has no source
    /// position of its own: cmark gives none to soft and hard line breaks. They fell back to
    /// location 0, so the local transition shifted that 0 with every keystroke before them and the
    /// parse put it back, and each such keystroke was a COR-71 disagreement
    /// (`typingAWordIntoTheRichFixtureIsReconciledWithoutRecovery`).
    private var lastSourceEnd = 0

    mutating func finish() -> MarkdownProjectionModel {
        MarkdownProjectionModel(
            sourceVersion: sourceVersion,
            renderedString: pieces.joined(),
            runs: runs,
            attachments: attachments,
            tables: tables,
            blocks: blocks,
            segments: segments,
            listMarkers: listMarkers,
            sourceUTF16Count: (map.source as NSString).length
        )
    }

    mutating func emit(_ node: MarkdownNode, styleStack: [ProjectionStyleTag], listNesting: Int) {
        switch node.kind {
        case .document:
            var previousEnd: Int?
            for child in node.children {
                if let start = sourceUTF16(of: child)?.location {
                    appendEmptyParagraphs(gap: previousEnd, nextStart: start, documentNode: node)
                }
                emit(child, styleStack: styleStack, listNesting: listNesting)
                previousEnd = sourceUTF16(of: child).map { EmptyParagraphLayout.blockEnd($0, in: map.source as NSString) } ?? previousEnd
            }
            appendEmptyParagraphs(gap: previousEnd, nextStart: nil, documentNode: node)

        case .paragraph:
            let blockStart = utf16Length
            emitInlineChildren(node, styleStack: styleStack)
            appendTrailingWhitespace(of: node, styles: styleStack)
            appendSyntheticBreak(after: node, kind: .paragraphBreak)
            appendBlock(node, start: blockStart, kind: .paragraph)

        case .heading(let level):
            let blockStart = utf16Length
            emitInlineChildren(node, styleStack: styleStack + [.heading(level)])
            appendTrailingWhitespace(of: node, styles: styleStack + [.heading(level)])
            appendSyntheticBreak(after: node, kind: .paragraphBreak)
            appendBlock(node, start: blockStart, kind: .heading(level: level))

        case .blockQuote:
            let blockStart = utf16Length
            for child in node.children {
                emit(child, styleStack: styleStack + [.blockQuote], listNesting: listNesting)
            }
            // Quote depth is how many quotes enclose this one, which the style stack already
            // tracks. List nesting is a different axis and must not stand in for it.
            let quoteDepth = styleStack.filter { $0 == .blockQuote }.count + 1
            appendBlock(node, start: blockStart, kind: .blockQuote(depth: quoteDepth))

        case .list(let info):
            for (itemIndex, child) in node.children.enumerated() {
                emitListItem(
                    child,
                    info: info,
                    styleStack: styleStack,
                    nesting: listNesting,
                    itemIndex: itemIndex
                )
            }

        case .item:
            // List items are emitted via emitListItem from the parent list.
            for child in node.children {
                emit(child, styleStack: styleStack, listNesting: listNesting)
            }

        case .codeBlock(_, let literal, _, _, _):
            let blockStart = utf16Length
            appendSourceBacked(
                literal.hasSuffix("\n") ? literal : literal + "\n",
                node: node,
                // REQ-107; COR-28: `.codeBlock`, not `.code`. Fenced content must not carry the
                // inline-code run background on top of its own container background.
                styles: styleStack + [.codeBlock],
                link: nil,
                literalFallback: false
            )
            appendBlock(node, start: blockStart, kind: .codeBlock(languageHintPresent: {
                if case .codeBlock(let info, _, _, _, _) = node.kind { return !info.isEmpty }
                return false
            }()) )

        case .htmlBlock(let literal):
            let blockStart = utf16Length
            let text = literal.hasSuffix("\n") ? literal : literal + "\n"
            appendLiteralFallback(text, node: node, styles: styleStack)
            appendBlock(node, start: blockStart, kind: .literalHTML)

        case .thematicBreak:
            let blockStart = utf16Length
            appendAttachment(nodeID: node.id, kind: .thematicBreak, source: sourceUTF16(of: node))
            appendSynthetic("\u{FFFC}", kind: .thematicBreak, after: node, refuseEdits: true)
            appendSyntheticBreak(after: node, kind: .paragraphBreak)
            appendBlock(node, start: blockStart, kind: .thematicBreak)

        case .text(let text):
            appendSourceBacked(text, node: node, styles: styleStack, link: nil, literalFallback: false)

        case .softBreak:
            appendSynthetic(" ", kind: .softLineBreak, after: node, refuseEdits: false)

        case .lineBreak:
            appendSynthetic("\n", kind: .hardLineBreak, after: node, refuseEdits: false)

        case .code(let literal):
            appendSourceBacked(literal, node: node, styles: styleStack + [.code], link: nil, literalFallback: false)

        case .htmlInline(let literal):
            appendLiteralFallback(literal, node: node, styles: styleStack)

        case .emphasis:
            emitInlineChildren(node, styleStack: styleStack + [.emphasis])
        case .strong:
            emitInlineChildren(node, styleStack: styleStack + [.strong])
        case .strikethrough:
            emitInlineChildren(node, styleStack: styleStack + [.strikethrough])
        case .link(let destination, _, let preservesLiteralSource):
            if preservesLiteralSource, let source = substring(of: node) {
                appendLiteralFallback(source, node: node, styles: styleStack)
            } else {
                emitLinkedChildren(node, styleStack: styleStack + [.link], destination: destination)
            }

        case .image(let destination, _):
            let blockStart = utf16Length
            let description = plainText(of: node)
            appendAttachment(
                nodeID: node.id,
                kind: .image(destination: destination, description: description),
                source: sourceUTF16(of: node)
            )
            appendSynthetic("\u{FFFC}", kind: .attachmentPlaceholder, after: node, refuseEdits: false)
            appendBlock(node, start: blockStart, kind: .image)

        case .table(let columnCount, let alignments):
            let blockStart = utf16Length
            emitTable(node, columnCount: columnCount, alignments: alignments, styleStack: styleStack)
            appendBlock(node, start: blockStart, kind: .table)

        case .tableRow, .tableCell:
            break

        case .unsupported:
            if let slice = substring(of: node) {
                appendLiteralFallback(slice, node: node, styles: styleStack)
            } else {
                emitInlineChildren(node, styleStack: styleStack + [.literalFallback])
            }
        }
    }

    mutating func emitListItem(
        _ node: MarkdownNode,
        info: MarkdownListInfo,
        styleStack: [ProjectionStyleTag],
        nesting: Int,
        itemIndex: Int
    ) {
        guard case .item(let parsedTaskChecked) = node.kind else {
            emit(node, styleStack: styleStack, listNesting: nesting)
            return
        }
        // An item whose only text is a task box, as Return leaves one (`- [ ] `), is no task to
        // cmark-gfm until text follows the box. Shown as the text "[ ]", the first letter typed
        // after it turned it into a checkbox, which the edit's proof took for a change of
        // structure and refused. It is shown as the empty task it is about to be.
        let boxOnly: Bool? = {
            guard parsedTaskChecked == nil,
                  node.children.count == 1,
                  case .paragraph = node.children[0].kind,
                  let text = substring(of: node.children[0])?.trimmingCharacters(in: .whitespaces) else { return nil }
            switch text {
            case "[ ]": return false
            case "[x]", "[X]": return true
            default: return nil
            }
        }()
        let taskChecked = parsedTaskChecked ?? boxOnly

        let task = taskChecked != nil
        let markerText: String
        let sourceMarkerText: String
        if task {
            markerText = ""
            sourceMarkerText = ""
        } else {
        switch info.kind {
        case .bullet:
            markerText = markerGlyph(info.marker, nesting: nesting) + " "
            sourceMarkerText = bulletSourceMarker(info.marker) + " "
        case .ordered(let start, let delimiter):
            let delim = delimiter == .period ? "." : ")"
            // REQ / review: each item shows start + index, not the list start alone.
            markerText = "\(start + itemIndex)\(delim) "
            sourceMarkerText = "\(start + itemIndex)\(delim) "
        }
        }

        let itemStart = sourceUTF16(of: node)?.location ?? 0
        // Trailing caret after the visible marker maps after the concrete source marker.
        let afterMarker: Int
        if let firstChild = node.children.first(where: {
            switch $0.kind {
            case .list: return false
            default: return true
            }
        }), let childStart = sourceUTF16(of: firstChild)?.location {
            afterMarker = childStart
        } else {
            // An empty item ends at its line's end: `-` alone at the end of a file has no space
            // after it to map past.
            afterMarker = min(itemStart + (markerText as NSString).length, lineEnd(from: itemStart))
        }
        let markerStart = utf16Length
        pieces.append(markerText)
        let markerUTF16 = (markerText as NSString).length
        utf16Length += markerUTF16
        let markerRange = NSRange(location: markerStart, length: markerUTF16)
        lastSourceEnd = afterMarker
        if markerUTF16 > 0 {
            segments.append(
                .synthetic(
                    projection: markerRange,
                    kind: .listMarker(displayedText: markerText, sourceText: sourceMarkerText, nesting: nesting),
                    insertion: .atSourceBoundaries(before: itemStart, after: afterMarker)
                )
            )
            listMarkers.append(
                ProjectionListMarker(
                    nodeID: node.id,
                    utf16Range: markerRange,
                    displayedText: markerText,
                    sourceText: sourceMarkerText,
                    nesting: nesting,
                    kind: info.kind
                )
            )
            runs.append(
                ProjectionRun(
                    nodeID: node.id,
                    utf16Range: markerRange,
                    styles: Set(styleStack),
                    linkDestination: nil,
                    isLiteralFallback: false
                )
            )
        }

        if let checked = taskChecked {
            let label = boxOnly == nil ? plainText(of: node) : ""
            // The box and the space after it anchor at the item's start. Anchored at its end,
            // they claimed the caret at the end of the task's text, which then mapped before the
            // box, and the next letter typed was refused (CI 45965037736).
            let boxLocation: Int? = itemStart
            appendAttachment(
                nodeID: node.id,
                kind: .task(checked: checked, label: label),
                source: sourceUTF16(of: node)
            )
            appendSynthetic(
                "\u{FFFC}",
                kind: .taskCheckbox(checked: checked),
                after: node,
                refuseEdits: false,
                at: boxLocation
            )
            appendSynthetic(
                " ",
                kind: .listMarker(displayedText: " ", sourceText: " ", nesting: nesting),
                after: node,
                refuseEdits: false,
                at: boxLocation
            )
        }

        // An item with no text of its own, as Return leaves one, still ends its line. Without a
        // break the next block ran on after its marker, and the caret after the marker had no
        // place of its own to map to.
        if boxOnly != nil || !node.children.contains(where: { if case .list = $0.kind { return false }; return true }) {
            let projection = NSRange(location: utf16Length, length: 1)
            pieces.append("\n")
            utf16Length += 1
            let location = lineEnd(from: itemStart)
            segments.append(.synthetic(projection: projection, kind: .paragraphBreak, insertion: .atSourceLocation(location)))
            runs.append(ProjectionRun(nodeID: node.id, utf16Range: projection, styles: Set(styleStack), linkDestination: nil, isLiteralFallback: false))
            lastSourceEnd = location
        }

        for child in node.children where boxOnly == nil {
            if case .list = child.kind {
                emit(child, styleStack: styleStack, listNesting: nesting + 1)
            } else {
                emit(child, styleStack: styleStack, listNesting: nesting)
            }
        }
        appendBlock(
            node,
            start: markerStart,
            kind: .listItem(kind: info.kind, nesting: nesting, task: task)
        )
    }

    mutating func emitInlineChildren(_ node: MarkdownNode, styleStack: [ProjectionStyleTag]) {
        for child in node.children {
            emit(child, styleStack: styleStack, listNesting: 0)
        }
    }

    mutating func emitLinkedChildren(_ node: MarkdownNode, styleStack: [ProjectionStyleTag], destination: String) {
        for child in node.children {
            switch child.kind {
            case .text(let text):
                appendSourceBacked(text, node: child, styles: styleStack, link: destination, literalFallback: false)
            case .softBreak:
                appendSynthetic(" ", kind: .softLineBreak, after: child, refuseEdits: false)
            case .lineBreak:
                appendSynthetic("\n", kind: .hardLineBreak, after: child, refuseEdits: false)
            case .code(let literal):
                appendSourceBacked(literal, node: child, styles: styleStack + [.code], link: destination, literalFallback: false)
            case .emphasis:
                emitLinkedChildren(child, styleStack: styleStack + [.emphasis], destination: destination)
            case .strong:
                emitLinkedChildren(child, styleStack: styleStack + [.strong], destination: destination)
            case .strikethrough:
                emitLinkedChildren(child, styleStack: styleStack + [.strikethrough], destination: destination)
            default:
                emit(child, styleStack: styleStack, listNesting: 0)
            }
        }
    }

    mutating func emitTable(
        _ node: MarkdownNode,
        columnCount: Int,
        alignments: [TableAlignment],
        styleStack: [ProjectionStyleTag]
    ) {
        let tableStart = utf16Length
        var cells: [ProjectionTableCell] = []
        var rowIndex = 0
        for row in node.children {
            guard case .tableRow(let isHeader) = row.kind else { continue }
            var col = 0
            for cell in row.children {
                guard case .tableCell = cell.kind else { continue }
                let cellStart = utf16Length
                emitInlineChildren(cell, styleStack: styleStack)
                let cellRange = NSRange(location: cellStart, length: utf16Length - cellStart)
                let alignment = col < alignments.count ? alignments[col] : .none
                cells.append(
                    ProjectionTableCell(
                        nodeID: cell.id,
                        row: rowIndex,
                        column: col,
                        isHeader: isHeader,
                        alignment: alignment,
                        utf16Range: cellRange,
                        sourceUTF16Range: sourceUTF16(of: cell)
                    )
                )
                appendBlock(cell, start: cellStart, kind: .tableCell(alignment: alignment, header: isHeader))
                if col + 1 < columnCount {
                    // NSTextTableBlock is paragraph geometry: cells must be distinct paragraphs,
                    // not tab-delimited runs in one paragraph.
                    appendSynthetic("\n", kind: .tableCellSeparator, after: cell, refuseEdits: false)
                }
                col += 1
            }
            appendSynthetic("\n", kind: .tableRowBreak, after: row, refuseEdits: false)
            appendBlock(
                row,
                start: cells.last(where: { $0.row == rowIndex })?.utf16Range.location ?? tableStart,
                kind: .tableRow(header: isHeader)
            )
            rowIndex += 1
        }
        tables.append(
            ProjectionTable(
                nodeID: node.id,
                columnCount: columnCount,
                alignments: alignments,
                cells: cells,
                utf16Range: NSRange(location: tableStart, length: utf16Length - tableStart)
            )
        )
    }

    // MARK: - Append helpers

    mutating func appendSourceBacked(
        _ string: String,
        node: MarkdownNode,
        styles: [ProjectionStyleTag],
        link: String?,
        literalFallback: Bool
    ) {
        guard !string.isEmpty else { return }
        let start = utf16Length
        pieces.append(string)
        let utf16 = (string as NSString).length
        utf16Length += utf16
        let projection = NSRange(location: start, length: utf16)

        let sourceRange = sourceUTF16(of: node)
        if let sourceRange {
            lastSourceEnd = NSMaxRange(sourceRange)
            guard let contentSource = resolveContentSource(node: node, rendered: string, full: sourceRange) else {
                // Normalized code/fence bodies are not 1:1 with rendered text — refuse edits.
                segments.append(.uneditable(projection: projection, reason: .ambiguous))
                var styleSet = Set(styles)
                if literalFallback { styleSet.insert(.literalFallback) }
                if link != nil { styleSet.insert(.link) }
                runs.append(
                    ProjectionRun(
                        nodeID: node.id,
                        utf16Range: projection,
                        styles: styleSet,
                        linkDestination: link,
                        isLiteralFallback: literalFallback
                    )
                )
                return
            }
            lastSourceEnd = NSMaxRange(contentSource)
            if literalFallback {
                segments.append(.literalFallback(projection: projection, source: contentSource))
            } else {
                segments.append(
                    .source(
                        projection: projection,
                        source: contentSource,
                        insertionBefore: contentSource.location,
                        insertionAfter: NSMaxRange(contentSource)
                    )
                )
            }
        } else {
            // Exact source unavailable — still render, but mark uneditable rather than invent a span.
            segments.append(.uneditable(projection: projection, reason: .unsupported))
            var styleSet = Set(styles)
            if literalFallback { styleSet.insert(.literalFallback) }
            if link != nil { styleSet.insert(.link) }
            runs.append(
                ProjectionRun(
                    nodeID: node.id,
                    utf16Range: projection,
                    styles: styleSet,
                    linkDestination: link,
                    isLiteralFallback: literalFallback
                )
            )
            return
        }

        var styleSet = Set(styles)
        if literalFallback { styleSet.insert(.literalFallback) }
        if link != nil { styleSet.insert(.link) }
        runs.append(
            ProjectionRun(
                nodeID: node.id,
                utf16Range: projection,
                styles: styleSet,
                linkDestination: link,
                isLiteralFallback: literalFallback
            )
        )
    }

    mutating func appendLiteralFallback(
        _ string: String,
        node: MarkdownNode,
        styles: [ProjectionStyleTag]
    ) {
        appendSourceBacked(string, node: node, styles: styles + [.literalFallback], link: nil, literalFallback: true)
    }

    /// The spaces that end a paragraph's or heading's last line, shown as the source text they
    /// are. cmark trims them, so a space typed at the end of a word had no presentation, could
    /// not be proved, and was refused: in WYSIWYG every word typed at the end of a line ran into
    /// the next (agent-drive tour 45957180019: "WeeklynotesToday…").
    mutating func appendTrailingWhitespace(of node: MarkdownNode, styles: [ProjectionStyleTag]) {
        guard let block = sourceUTF16(of: node) else { return }
        let source = map.source as NSString
        func isNewline(_ c: unichar) -> Bool { c == 0x0A || c == 0x0D }
        func isBlank(_ c: unichar) -> Bool { c == 0x20 || c == 0x09 }
        var lineEnd = min(NSMaxRange(block), source.length)
        while lineEnd > block.location, isNewline(source.character(at: lineEnd - 1)) { lineEnd -= 1 }
        while lineEnd < source.length, isBlank(source.character(at: lineEnd)) { lineEnd += 1 }
        var start = lineEnd
        let floor = max(block.location, lastSourceEnd)
        while start > floor, isBlank(source.character(at: start - 1)) { start -= 1 }
        guard start < lineEnd else { return }
        let range = NSRange(location: start, length: lineEnd - start)
        let text = source.substring(with: range)
        let projection = NSRange(location: utf16Length, length: range.length)
        pieces.append(text)
        utf16Length += range.length
        segments.append(.source(projection: projection, source: range, insertionBefore: range.location, insertionAfter: NSMaxRange(range)))
        runs.append(ProjectionRun(nodeID: node.id, utf16Range: projection, styles: Set(styles), linkDestination: nil, isLiteralFallback: false))
        lastSourceEnd = NSMaxRange(range)
    }

    /// Empty paragraphs between top-level blocks, and before the first and after the last, laid
    /// out by `EmptyParagraphLayout`, which Backspace's planner reads too.
    mutating func appendEmptyParagraphs(gap previousEnd: Int?, nextStart: Int?, documentNode: MarkdownNode) {
        for slot in EmptyParagraphLayout.slots(in: map.source as NSString, previousEnd: previousEnd, nextStart: nextStart) {
            let projection = NSRange(location: utf16Length, length: 1)
            pieces.append("\n")
            utf16Length += 1
            let insertion: SyntheticInsertionPolicy = slot.before == slot.after
                ? .atSourceLocation(slot.before)
                : .atSourceBoundaries(before: slot.before, after: slot.after)
            segments.append(.synthetic(projection: projection, kind: .paragraphBreak, insertion: insertion))
            runs.append(ProjectionRun(nodeID: documentNode.id, utf16Range: projection, styles: [], linkDestination: nil, isLiteralFallback: false))
        }
    }

    mutating func appendSyntheticBreak(after node: MarkdownNode, kind: SyntheticKind) {
        appendSynthetic("\n", kind: kind, after: node, refuseEdits: false)
    }

    mutating func appendSynthetic(
        _ string: String,
        kind: SyntheticKind,
        after node: MarkdownNode,
        refuseEdits: Bool,
        at location: Int? = nil
    ) {
        guard !string.isEmpty else { return }
        let start = utf16Length
        pieces.append(string)
        let utf16 = (string as NSString).length
        utf16Length += utf16
        let projection = NSRange(location: start, length: utf16)
        let insertAt = location ?? sourceUTF16(of: node).map(NSMaxRange) ?? lastSourceEnd
        let policy: SyntheticInsertionPolicy = refuseEdits ? .refuse : .atSourceLocation(insertAt)
        segments.append(.synthetic(projection: projection, kind: kind, insertion: policy))
        runs.append(
            ProjectionRun(
                nodeID: node.id,
                utf16Range: projection,
                styles: [],
                linkDestination: nil,
                isLiteralFallback: false
            )
        )
    }

    mutating func appendAttachment(nodeID: MarkdownNodeID, kind: ProjectionAttachmentKind, source: NSRange?) {
        attachments.append(
            ProjectionAttachment(
                nodeID: nodeID,
                utf16Location: utf16Length,
                kind: kind,
                sourceUTF16Range: source
            )
        )
    }

    mutating func appendBlock(
        _ node: MarkdownNode,
        start: Int,
        kind: PresentationBlockKind
    ) {
        let range = NSRange(location: start, length: max(0, utf16Length - start))
        guard range.length > 0 else { return }
        blocks.append(
            PresentationBlock(
                nodeID: node.id,
                projectionRange: range,
                sourceRange: sourceUTF16(of: node),
                kind: kind
            )
        )
    }

    /// Map rendered leaf text to the exact source slice derived from concrete structure.
    ///
    /// // REQ-057/087: never locate parser-owned content via `range(of: rendered)`.
    /// Returns `nil` when structure is present but not identity-mappable (normalized code).
    func resolveContentSource(node: MarkdownNode, rendered: String, full: NSRange) -> NSRange? {
        switch node.kind {
        case .text:
            return full
        case .code:
            return StructuralSourceSpans.inlineCodeBody(full: full, rendered: rendered, map: map)
        case .codeBlock(let info, let literal, let fenced, let fenceChar, let fenceLength):
            if fenced, let fenceChar, fenceLength > 0 {
                return StructuralSourceSpans.fencedCodeBody(
                    full: full,
                    info: info,
                    literal: literal,
                    rendered: rendered,
                    fenceChar: fenceChar,
                    fenceLength: fenceLength,
                    map: map
                )
            }
            // Indented code: body is the node span only when identical to rendered.
            // COR-33 stage 2: allow CRLF normalisation for indented code as well.
            if case .success(let slice) = map.substring(utf16: full) {
                if slice == rendered { return full }
                if slice.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "") == rendered {
                    return full
                }
            }
            return nil
        default:
            break
        }
        if case .success(let slice) = map.substring(utf16: full) {
            if slice == rendered { return full }
            // For generic nodes, CRLF normalisation is not an allowed atomic — only code blocks are.
            // Keep exact identity here; code blocks already handled above.
        }
        return nil
    }

    /// Where the source line holding `location` ends, before its line break.
    func lineEnd(from location: Int) -> Int {
        let source = map.source as NSString
        var end = min(max(location, 0), source.length)
        while end < source.length {
            let c = source.character(at: end)
            if c == 0x0A || c == 0x0D { break }
            end += 1
        }
        return end
    }

    func sourceUTF16(of node: MarkdownNode) -> NSRange? {
        switch map.utf16Range(for: node.position) {
        case .success(let range): return range
        case .failure: return nil
        }
    }

    func substring(of node: MarkdownNode) -> String? {
        switch map.substring(position: node.position) {
        case .success(let s): return s
        case .failure: return nil
        }
    }

    func plainText(of node: MarkdownNode) -> String {
        switch node.kind {
        case .text(let t): return t
        case .code(let t): return t
        case .softBreak, .lineBreak: return " "
        default:
            return node.children.map(plainText(of:)).joined()
        }
    }

    func markerGlyph(_ marker: MarkdownListMarker, nesting: Int) -> String {
        // Source spelling remains in the atomic marker's source boundaries; the reader sees
        // semantic list depth, never the delimiter chosen by the author.
        _ = marker
        let glyphs = MarkdownTypography.listMarkerGlyphs
        return glyphs[((max(nesting, 0) % glyphs.count) + glyphs.count) % glyphs.count]
    }

    func bulletSourceMarker(_ marker: MarkdownListMarker) -> String {
        switch marker {
        case .dash: return "-"
        case .plus: return "+"
        case .asterisk: return "*"
        case .other: return "-"
        }
    }
}
