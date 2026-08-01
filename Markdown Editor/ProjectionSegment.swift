//
//  ProjectionSegment.swift
//  Markdown Editor
//

import Foundation

/// Why a synthetic projection unit exists and where an insertion lands in source.
nonisolated enum SyntheticKind: Sendable, Equatable {
    case paragraphBreak
    case listMarker(text: String, nesting: Int)
    case taskCheckbox(checked: Bool)
    case thematicBreak
    case tableCellSeparator
    case tableRowBreak
    case attachmentPlaceholder
    case softLineBreak
    case hardLineBreak
}

nonisolated enum SyntheticInsertionPolicy: Sendable, Equatable {
    /// Insert at this absolute UTF-16 source location (both boundaries).
    case atSourceLocation(Int)
    /// Distinct before/after source boundaries (e.g. list markers spanning `- ` / `1. `).
    case atSourceBoundaries(before: Int, after: Int)
    /// Refuse edits that land only on this synthetic unit.
    case refuse
}

nonisolated enum ProjectionRefusal: Sendable, Equatable {
    case ambiguous
    case stale
    case outOfBounds
    case unsupported
    case uneditableSynthetic
}

/// One lossless coverage unit of WYSIWYG storage.
///
/// // REQ-054–056/087: exact source, synthetic+policy, literal fallback, or uneditable.
nonisolated enum ProjectionSegment: Sendable, Equatable {
    case source(
        projection: NSRange,
        source: NSRange,
        insertionBefore: Int,
        insertionAfter: Int
    )
    case synthetic(
        projection: NSRange,
        kind: SyntheticKind,
        insertion: SyntheticInsertionPolicy
    )
    case literalFallback(projection: NSRange, source: NSRange)
    case uneditable(projection: NSRange, reason: ProjectionRefusal)
}

nonisolated enum SelectionAffinity: Sendable, Equatable {
    case upstream
    case downstream
}

nonisolated enum CoordinateMappingResult: Sendable, Equatable {
    case exact(NSRange)
    case refused(ProjectionRefusal)
}
