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

nonisolated struct ProjectionListMarker: Sendable, Equatable {
    let nodeID: MarkdownNodeID
    let utf16Range: NSRange
    let text: String
    let nesting: Int
    let kind: MarkdownListKind
}

nonisolated struct LogicalSelection: Sendable, Equatable {
    /// Mode-local UTF-16 selection.
    let range: NSRange
}

/// Off-main projection snapshot for one source version.
///
/// // REQ-054–056/087: typed segments replace proportional anchors.
nonisolated struct MarkdownProjectionModel: Sendable, Equatable {
    let sourceVersion: UInt64
    let renderedString: String
    let runs: [ProjectionRun]
    let attachments: [ProjectionAttachment]
    let tables: [ProjectionTable]
    let segments: [ProjectionSegment]
    let listMarkers: [ProjectionListMarker]
    let sourceUTF16Count: Int

    var coordinateMap: ProjectionCoordinateMap {
        ProjectionCoordinateMap(
            segments: segments,
            projectionUTF16Count: (renderedString as NSString).length,
            sourceUTF16Count: sourceUTF16Count
        )
    }
}

extension MarkdownProjectionModel {
    /// Build a delimiter-free projection from a parsed tree + source index.
    ///
    /// // REQ-054–056/055/087: unsupported/HTML → literal fallback; mapping failures → literal.
    nonisolated static func build(
        tree: MarkdownTree,
        index: MarkdownSourceIndex
    ) -> MarkdownProjectionModel {
        ProjectionCompiler.compile(tree: tree, map: SourceCoordinateMap(index: index))
    }
}
