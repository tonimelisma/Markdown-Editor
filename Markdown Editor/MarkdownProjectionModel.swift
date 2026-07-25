//
//  MarkdownProjectionModel.swift
//  Markdown Editor
//

import Foundation

/// Semantic style applied to a projection run (AppKit-free).
///
/// // REQ-054–056/080/084: Sendable projection model — no NSFont/NSColor/NSTextAttachment.
nonisolated enum ProjectionStyle: Sendable, Equatable {
    case plain
    case heading(level: Int)
    case emphasis
    case strong
    case strikethrough
    case code
    case link
    case blockQuote
    case literalFallback
}

nonisolated enum ProjectionAttachmentKind: Sendable, Equatable {
    case task(checked: Bool, label: String)
    case image(destination: String, description: String)
    case thematicBreak
}

nonisolated struct ProjectionRun: Sendable, Equatable {
    let nodeID: MarkdownNodeID
    let utf16Range: NSRange
    let styles: Set<ProjectionStyleTag>
    let linkDestination: String?
    let isLiteralFallback: Bool
}

/// Hashable style tag for run sets (heading carries level).
nonisolated enum ProjectionStyleTag: Hashable, Sendable {
    case heading(Int)
    case emphasis
    case strong
    case strikethrough
    case code
    case link
    case blockQuote
    case literalFallback
}

nonisolated struct ProjectionAttachment: Sendable, Equatable {
    let nodeID: MarkdownNodeID
    let utf16Location: Int
    let kind: ProjectionAttachmentKind
    let sourceUTF16Range: NSRange?
}

nonisolated struct ProjectionTableCell: Sendable, Equatable {
    let nodeID: MarkdownNodeID
    let row: Int
    let column: Int
    let isHeader: Bool
    let alignment: TableAlignment
    let utf16Range: NSRange
    let sourceUTF16Range: NSRange?
}

nonisolated struct ProjectionTable: Sendable, Equatable {
    let nodeID: MarkdownNodeID
    let columnCount: Int
    let alignments: [TableAlignment]
    let cells: [ProjectionTableCell]
    let utf16Range: NSRange
}

nonisolated struct LogicalSelection: Sendable, Equatable {
    /// Mode-local UTF-16 selection.
    let range: NSRange
}

/// Off-main projection snapshot for one source version.
nonisolated struct MarkdownProjectionModel: Sendable, Equatable {
    let sourceVersion: UInt64
    let renderedString: String
    let runs: [ProjectionRun]
    let attachments: [ProjectionAttachment]
    let tables: [ProjectionTable]
    /// Maps each projection UTF-16 index to a source UTF-16 insertion anchor (length renderedString+1).
    let sourceAnchors: [Int]
    /// Source UTF-16 range covered by each projection UTF-16 unit (parallel to renderedString.utf16).
    let sourceUTF16ForProjectionUnit: [NSRange]
}

extension MarkdownProjectionModel {
    /// Build a delimiter-free projection from a parsed tree + source index.
    ///
    /// // REQ-054–056/055/087: unsupported/HTML → literal fallback; mapping failures → literal.
    static func build(
        tree: MarkdownTree,
        index: MarkdownSourceIndex
    ) -> MarkdownProjectionModel {
        var builder = ProjectionBuilder(index: index, sourceVersion: tree.sourceVersion)
        builder.emit(tree.root, styleStack: [], inQuote: false)
        return builder.finish()
    }
}

// MARK: - Builder

private struct ProjectionBuilder {
    let index: MarkdownSourceIndex
    let sourceVersion: UInt64

    private var pieces: [String] = []
    private var runs: [ProjectionRun] = []
    private var attachments: [ProjectionAttachment] = []
    private var tables: [ProjectionTable] = []
    private var sourceAnchors: [Int] = [0]
    private var sourceUTF16ForProjectionUnit: [NSRange] = []
    private var utf16Length = 0

    mutating func finish() -> MarkdownProjectionModel {
        MarkdownProjectionModel(
            sourceVersion: sourceVersion,
            renderedString: pieces.joined(),
            runs: runs,
            attachments: attachments,
            tables: tables,
            sourceAnchors: sourceAnchors,
            sourceUTF16ForProjectionUnit: sourceUTF16ForProjectionUnit
        )
    }

    mutating func emit(_ node: MarkdownNode, styleStack: [ProjectionStyleTag], inQuote: Bool) {
        switch node.kind {
        case .document:
            for child in node.children {
                emit(child, styleStack: styleStack, inQuote: inQuote)
            }

        case .paragraph:
            emitInlineChildren(node, styleStack: styleStack, inQuote: inQuote)
            appendBlockBreak(after: node)

        case .heading(let level):
            var stack = styleStack
            stack.append(.heading(level))
            emitInlineChildren(node, styleStack: stack, inQuote: inQuote)
            appendBlockBreak(after: node)

        case .blockQuote:
            var stack = styleStack
            stack.append(.blockQuote)
            for child in node.children {
                emit(child, styleStack: stack, inQuote: true)
            }

        case .list:
            for child in node.children {
                emit(child, styleStack: styleStack, inQuote: inQuote)
            }

        case .item(let taskChecked):
            if let checked = taskChecked {
                let label = plainText(of: node)
                appendAttachment(
                    nodeID: node.id,
                    kind: .task(checked: checked, label: label),
                    source: sourceUTF16(of: node)
                )
                append(" ", source: sourceUTF16(of: node), styles: styleStack, link: nil, literal: false, nodeID: node.id)
            }
            for child in node.children {
                emit(child, styleStack: styleStack, inQuote: inQuote)
            }

        case .codeBlock(_, let literal, _, _, _):
            let styles = styleStack + [.code]
            append(literal, source: sourceUTF16(of: node), styles: styles, link: nil, literal: false, nodeID: node.id)
            if !literal.hasSuffix("\n") {
                append("\n", source: sourceUTF16(of: node), styles: styles, link: nil, literal: false, nodeID: node.id)
            }

        case .htmlBlock(let literal):
            append(literal, source: sourceUTF16(of: node), styles: styleStack + [.literalFallback], link: nil, literal: true, nodeID: node.id)
            if !literal.hasSuffix("\n") {
                append("\n", source: sourceUTF16(of: node), styles: [.literalFallback], link: nil, literal: true, nodeID: node.id)
            }

        case .thematicBreak:
            appendAttachment(nodeID: node.id, kind: .thematicBreak, source: sourceUTF16(of: node))
            append("\n", source: sourceUTF16(of: node), styles: styleStack, link: nil, literal: false, nodeID: node.id)

        case .text(let text):
            append(text, source: sourceUTF16(of: node), styles: styleStack, link: nil, literal: false, nodeID: node.id)

        case .softBreak:
            append("\n", source: sourceUTF16(of: node), styles: styleStack, link: nil, literal: false, nodeID: node.id)

        case .lineBreak:
            append("\n", source: sourceUTF16(of: node), styles: styleStack, link: nil, literal: false, nodeID: node.id)

        case .code(let literal):
            append(literal, source: sourceUTF16(of: node), styles: styleStack + [.code], link: nil, literal: false, nodeID: node.id)

        case .htmlInline(let literal):
            append(literal, source: sourceUTF16(of: node), styles: styleStack + [.literalFallback], link: nil, literal: true, nodeID: node.id)

        case .emphasis:
            emitInlineChildren(node, styleStack: styleStack + [.emphasis], inQuote: inQuote)

        case .strong:
            emitInlineChildren(node, styleStack: styleStack + [.strong], inQuote: inQuote)

        case .strikethrough:
            emitInlineChildren(node, styleStack: styleStack + [.strikethrough], inQuote: inQuote)

        case .link(let destination, _):
            emitInlineChildren(node, styleStack: styleStack + [.link], inQuote: inQuote, linkDestination: destination)

        case .image(let destination, _):
            let description = plainText(of: node)
            appendAttachment(
                nodeID: node.id,
                kind: .image(destination: destination, description: description),
                source: sourceUTF16(of: node)
            )

        case .table(let columnCount, let alignments):
            emitTable(node, columnCount: columnCount, alignments: alignments, styleStack: styleStack)

        case .tableRow, .tableCell:
            // Handled by emitTable.
            break

        case .unsupported:
            // Literal fallback: emit exact source slice when mappable; otherwise children text.
            if let slice = substring(of: node) {
                append(slice, source: sourceUTF16(of: node), styles: styleStack + [.literalFallback], link: nil, literal: true, nodeID: node.id)
            } else {
                emitInlineChildren(node, styleStack: styleStack + [.literalFallback], inQuote: inQuote)
            }
        }
    }

    mutating func emitInlineChildren(
        _ node: MarkdownNode,
        styleStack: [ProjectionStyleTag],
        inQuote: Bool,
        linkDestination: String? = nil
    ) {
        for child in node.children {
            if let linkDestination {
                // Force link destination onto leaf appends via temporary stack walk:
                emitLinked(child, styleStack: styleStack, destination: linkDestination)
            } else {
                emit(child, styleStack: styleStack, inQuote: inQuote)
            }
        }
    }

    mutating func emitLinked(_ node: MarkdownNode, styleStack: [ProjectionStyleTag], destination: String) {
        switch node.kind {
        case .text(let text):
            append(text, source: sourceUTF16(of: node), styles: styleStack, link: destination, literal: false, nodeID: node.id)
        case .softBreak, .lineBreak:
            append("\n", source: sourceUTF16(of: node), styles: styleStack, link: destination, literal: false, nodeID: node.id)
        case .code(let literal):
            append(literal, source: sourceUTF16(of: node), styles: styleStack + [.code], link: destination, literal: false, nodeID: node.id)
        case .emphasis:
            for c in node.children { emitLinked(c, styleStack: styleStack + [.emphasis], destination: destination) }
        case .strong:
            for c in node.children { emitLinked(c, styleStack: styleStack + [.strong], destination: destination) }
        case .strikethrough:
            for c in node.children { emitLinked(c, styleStack: styleStack + [.strikethrough], destination: destination) }
        default:
            emit(node, styleStack: styleStack, inQuote: false)
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
                emitInlineChildren(cell, styleStack: styleStack, inQuote: false)
                // Separate cells with tab for linear fallback; RichTextBuilder uses table metadata.
                if col + 1 < columnCount {
                    append("\t", source: sourceUTF16(of: cell), styles: styleStack, link: nil, literal: false, nodeID: cell.id)
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
            append("\n", source: sourceUTF16(of: row), styles: styleStack, link: nil, literal: false, nodeID: row.id)
            rowIndex += 1
        }
        let tableRange = NSRange(location: tableStart, length: utf16Length - tableStart)
        tables.append(
            ProjectionTable(
                nodeID: node.id,
                columnCount: columnCount,
                alignments: alignments,
                cells: cells,
                utf16Range: tableRange
            )
        )
    }

    mutating func appendBlockBreak(after node: MarkdownNode) {
        append("\n", source: sourceUTF16(of: node), styles: [], link: nil, literal: false, nodeID: node.id)
    }

    mutating func appendAttachment(nodeID: MarkdownNodeID, kind: ProjectionAttachmentKind, source: NSRange?) {
        let location = utf16Length
        // Object Replacement Character occupies one UTF-16 unit in storage.
        let replacement = "\u{FFFC}"
        append(replacement, source: source, styles: [], link: nil, literal: false, nodeID: nodeID)
        attachments.append(
            ProjectionAttachment(nodeID: nodeID, utf16Location: location, kind: kind, sourceUTF16Range: source)
        )
    }

    mutating func append(
        _ string: String,
        source: NSRange?,
        styles: [ProjectionStyleTag],
        link: String?,
        literal: Bool,
        nodeID: MarkdownNodeID
    ) {
        guard !string.isEmpty else { return }
        let start = utf16Length
        pieces.append(string)
        let utf16 = (string as NSString).length
        utf16Length += utf16

        let src = source ?? NSRange(location: NSNotFound, length: 0)
        let anchor = (src.location == NSNotFound) ? (sourceAnchors.last ?? 0) : src.location
        for i in 0..<utf16 {
            let unitSource: NSRange
            if src.location == NSNotFound {
                unitSource = NSRange(location: NSNotFound, length: 0)
            } else if src.length == 0 {
                unitSource = NSRange(location: src.location, length: 0)
            } else {
                // Distribute source range across projection units proportionally by index.
                let loc = src.location + min(i, max(src.length - 1, 0))
                unitSource = NSRange(location: loc, length: 1)
            }
            sourceUTF16ForProjectionUnit.append(unitSource)
            let nextAnchor = (src.location == NSNotFound)
                ? anchor
                : src.location + min(i + 1, src.length)
            sourceAnchors.append(nextAnchor)
        }

        var styleSet = Set(styles)
        if literal { styleSet.insert(.literalFallback) }
        if link != nil { styleSet.insert(.link) }
        runs.append(
            ProjectionRun(
                nodeID: nodeID,
                utf16Range: NSRange(location: start, length: utf16),
                styles: styleSet,
                linkDestination: link,
                isLiteralFallback: literal
            )
        )
    }

    func sourceUTF16(of node: MarkdownNode) -> NSRange? {
        switch index.utf16Range(for: node.position) {
        case .success(let range): return range
        case .failure: return nil
        }
    }

    func substring(of node: MarkdownNode) -> String? {
        switch index.substring(position: node.position) {
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
}
