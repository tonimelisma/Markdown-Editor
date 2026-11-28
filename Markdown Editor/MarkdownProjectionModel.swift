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
    /// An inline code span: monospaced plus a subtle run background.
    case code
    /// Content inside a fenced or indented code block.
    ///
    /// // REQ-107; COR-28: distinct from `.code` because the two treatments must not compose.
    /// // The block already carries an `NSTextBlock` container background and padding; when
    /// // fenced content also carried `.code`, the inline run background was drawn *inside* that
    /// // container, producing the darker band visible in the REQ-104 capture at 88b7bd3.
    /// // architecture.md §7 states these are distinct treatments — "Code blocks use block geometry
    /// // and padding. Inline code remains inline" — so the distinction lives in the type rather
    /// // than in a positional test inside the builder.
    case codeBlock
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
    let displayedText: String
    let sourceText: String
    let nesting: Int
    let kind: MarkdownListKind

    /// The displayed spelling remains available to existing presentation consumers; source
    /// fidelity is carried separately in `sourceText`.
    var text: String { displayedText }
}

/// Off-main projection snapshot for one source version.
///
/// // REQ-054–056/087: typed segments replace proportional anchors.
/// Prefer `PresentationSnapshot` for session-owned editable state (ARC-003).
nonisolated struct MarkdownProjectionModel: Sendable, Equatable {
    let sourceVersion: UInt64
    let renderedString: String
    let runs: [ProjectionRun]
    let attachments: [ProjectionAttachment]
    let tables: [ProjectionTable]
    let blocks: [PresentationBlock]
    let segments: [ProjectionSegment]
    let listMarkers: [ProjectionListMarker]
    let sourceUTF16Count: Int

    /// COR-40: total block identification (same as PresentationSnapshot).
    func enclosingBlock(at location: Int) -> PresentationBlock? {
        let candidates = blocks.filter {
            NSLocationInRange(location, $0.projectionRange) || location == NSMaxRange($0.projectionRange)
        }
        return candidates
            .filter {
                switch $0.kind {
                case .table, .tableRow, .tableCell: return false
                default: return true
                }
            }
            .min(by: { $0.projectionRange.length < $1.projectionRange.length })
    }
    private let storedMap: ProjectionCoordinateMap?

    init(
        sourceVersion: UInt64,
        renderedString: String,
        runs: [ProjectionRun],
        attachments: [ProjectionAttachment],
        tables: [ProjectionTable],
        blocks: [PresentationBlock] = [],
        segments: [ProjectionSegment],
        listMarkers: [ProjectionListMarker],
        sourceUTF16Count: Int,
        prebuiltMap: ProjectionCoordinateMap? = nil
    ) {
        self.sourceVersion = sourceVersion
        self.renderedString = renderedString
        self.runs = runs
        self.attachments = attachments
        self.tables = tables
        self.blocks = blocks
        self.segments = segments
        self.listMarkers = listMarkers
        self.sourceUTF16Count = sourceUTF16Count
        self.storedMap = prebuiltMap
    }

    var coordinateMap: ProjectionCoordinateMap {
        if let storedMap { return storedMap }
        return ProjectionCoordinateMap(
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
        index: MarkdownSourceIndex,
        intent: IntentContext? = nil
    ) -> MarkdownProjectionModel {
        if let intent {
            intent.recorder.add(intent) { $0.projectionCompiles += 1 }
        }
        return ProjectionCompiler.compile(tree: tree, map: SourceCoordinateMap(index: index))
    }
}
