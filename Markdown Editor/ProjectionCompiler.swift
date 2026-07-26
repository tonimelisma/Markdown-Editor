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
    private var segments: [ProjectionSegment] = []
    private var listMarkers: [ProjectionListMarker] = []
    private var utf16Length = 0

    mutating func finish() -> MarkdownProjectionModel {
        MarkdownProjectionModel(
            sourceVersion: sourceVersion,
            renderedString: pieces.joined(),
            runs: runs,
            attachments: attachments,
            tables: tables,
            segments: segments,
            listMarkers: listMarkers,
            sourceUTF16Count: (map.source as NSString).length
        )
    }

    mutating func emit(_ node: MarkdownNode, styleStack: [ProjectionStyleTag], listNesting: Int) {
        switch node.kind {
        case .document:
            for child in node.children {
                emit(child, styleStack: styleStack, listNesting: listNesting)
            }

        case .paragraph:
            emitInlineChildren(node, styleStack: styleStack)
            appendSyntheticBreak(after: node, kind: .paragraphBreak)

        case .heading(let level):
            emitInlineChildren(node, styleStack: styleStack + [.heading(level)])
            appendSyntheticBreak(after: node, kind: .paragraphBreak)

        case .blockQuote:
            for child in node.children {
                emit(child, styleStack: styleStack + [.blockQuote], listNesting: listNesting)
            }

        case .list(let info):
            for child in node.children {
                emitListItem(child, info: info, styleStack: styleStack, nesting: listNesting)
            }

        case .item:
            // List items are emitted via emitListItem from the parent list.
            for child in node.children {
                emit(child, styleStack: styleStack, listNesting: listNesting)
            }

        case .codeBlock(_, let literal, _, _, _):
            appendSourceBacked(
                literal.hasSuffix("\n") ? literal : literal + "\n",
                node: node,
                styles: styleStack + [.code],
                link: nil,
                literalFallback: false
            )

        case .htmlBlock(let literal):
            let text = literal.hasSuffix("\n") ? literal : literal + "\n"
            appendLiteralFallback(text, node: node, styles: styleStack)

        case .thematicBreak:
            appendAttachment(nodeID: node.id, kind: .thematicBreak, source: sourceUTF16(of: node))
            appendSynthetic("\u{FFFC}", kind: .thematicBreak, after: node, refuseEdits: true)
            appendSyntheticBreak(after: node, kind: .paragraphBreak)

        case .text(let text):
            appendSourceBacked(text, node: node, styles: styleStack, link: nil, literalFallback: false)

        case .softBreak:
            appendSynthetic("\n", kind: .softLineBreak, after: node, refuseEdits: false)

        case .lineBreak:
            appendSynthetic("\n", kind: .softLineBreak, after: node, refuseEdits: false)

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
        case .link(let destination, _):
            emitLinkedChildren(node, styleStack: styleStack + [.link], destination: destination)

        case .image(let destination, _):
            let description = plainText(of: node)
            appendAttachment(
                nodeID: node.id,
                kind: .image(destination: destination, description: description),
                source: sourceUTF16(of: node)
            )
            appendSynthetic("\u{FFFC}", kind: .attachmentPlaceholder, after: node, refuseEdits: false)

        case .table(let columnCount, let alignments):
            emitTable(node, columnCount: columnCount, alignments: alignments, styleStack: styleStack)

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
        nesting: Int
    ) {
        guard case .item(let taskChecked) = node.kind else {
            emit(node, styleStack: styleStack, listNesting: nesting)
            return
        }

        let markerText: String
        switch info.kind {
        case .bullet:
            markerText = markerGlyph(info.marker) + " "
        case .ordered(let start, let delimiter):
            let delim = delimiter == .period ? "." : ")"
            markerText = "\(start)\(delim) "
        }

        let insertAt = sourceUTF16(of: node)?.location ?? 0
        let markerStart = utf16Length
        pieces.append(markerText)
        let markerUTF16 = (markerText as NSString).length
        utf16Length += markerUTF16
        let markerRange = NSRange(location: markerStart, length: markerUTF16)
        segments.append(
            .synthetic(
                projection: markerRange,
                kind: .listMarker(text: markerText, nesting: nesting),
                insertion: .atSourceLocation(insertAt)
            )
        )
        listMarkers.append(
            ProjectionListMarker(
                nodeID: node.id,
                utf16Range: markerRange,
                text: markerText,
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

        if let checked = taskChecked {
            let label = plainText(of: node)
            appendAttachment(
                nodeID: node.id,
                kind: .task(checked: checked, label: label),
                source: sourceUTF16(of: node)
            )
            appendSynthetic(
                "\u{FFFC}",
                kind: .taskCheckbox(checked: checked),
                after: node,
                refuseEdits: false
            )
            appendSynthetic(" ", kind: .listMarker(text: " ", nesting: nesting), after: node, refuseEdits: false)
        }

        for child in node.children {
            if case .list = child.kind {
                emit(child, styleStack: styleStack, listNesting: nesting + 1)
            } else {
                emit(child, styleStack: styleStack, listNesting: nesting)
            }
        }
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
            case .softBreak, .lineBreak:
                appendSynthetic("\n", kind: .softLineBreak, after: child, refuseEdits: false)
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
                if col + 1 < columnCount {
                    appendSynthetic("\t", kind: .tableCellSeparator, after: cell, refuseEdits: false)
                }
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
                col += 1
            }
            appendSynthetic("\n", kind: .tableRowBreak, after: row, refuseEdits: false)
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
        let contentSource: NSRange
        if let sourceRange {
            contentSource = resolveContentSource(node: node, rendered: string, full: sourceRange)
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

    mutating func appendSyntheticBreak(after node: MarkdownNode, kind: SyntheticKind) {
        appendSynthetic("\n", kind: kind, after: node, refuseEdits: false)
    }

    mutating func appendSynthetic(
        _ string: String,
        kind: SyntheticKind,
        after node: MarkdownNode,
        refuseEdits: Bool
    ) {
        guard !string.isEmpty else { return }
        let start = utf16Length
        pieces.append(string)
        let utf16 = (string as NSString).length
        utf16Length += utf16
        let projection = NSRange(location: start, length: utf16)
        let insertAt = NSMaxRange(sourceUTF16(of: node) ?? NSRange(location: 0, length: 0))
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

    /// Map rendered leaf text to the exact source slice of that text when possible.
    func resolveContentSource(node: MarkdownNode, rendered: String, full: NSRange) -> NSRange {
        switch node.kind {
        case .text:
            return full
        case .code, .htmlInline, .htmlBlock, .codeBlock, .unsupported:
            return full
        default:
            break
        }
        // For wrapper nodes that still emit leaf text via children, `full` is the child span.
        if case .success(let slice) = map.substring(utf16: full), slice == rendered {
            return full
        }
        // Search for rendered text inside the full node span (delimiter wrappers).
        if full.location != NSNotFound, full.length > 0,
           case .success(let slice) = map.substring(utf16: full),
           let r = slice.range(of: rendered) {
            let prefix = String(slice[..<r.lowerBound])
            let prefixUTF16 = (prefix as NSString).length
            let renderedUTF16 = (rendered as NSString).length
            return NSRange(location: full.location + prefixUTF16, length: renderedUTF16)
        }
        return full
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

    func markerGlyph(_ marker: MarkdownListMarker) -> String {
        switch marker {
        case .dash: return "-"
        case .plus: return "+"
        case .asterisk: return "*"
        case .other: return "-"
        }
    }
}
