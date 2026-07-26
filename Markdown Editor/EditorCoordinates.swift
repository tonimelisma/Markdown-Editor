//
//  EditorCoordinates.swift
//  Markdown Editor
//

import Foundation

/// Canonical-source revision counter owned by `MarkdownDocument`.
///
/// // REQ-016/087: typed revision — never confuse with projection revision.
nonisolated struct SourceRevision: Sendable, Equatable, Hashable, Comparable {
    let value: UInt64

    static func < (lhs: SourceRevision, rhs: SourceRevision) -> Bool {
        lhs.value < rhs.value
    }
}

/// Identity of one presented WYSIWYG snapshot — not a source revision.
///
/// // REQ-091; ARC-003: interchangeable only with `PresentationSnapshot.ID`.
nonisolated struct ProjectionRevision: Sendable, Equatable, Hashable {
    let value: UInt64

    init(snapshotID: PresentationSnapshot.ID) {
        value = snapshotID.value
    }

    init(value: UInt64) {
        self.value = value
    }

    var snapshotID: PresentationSnapshot.ID {
        PresentationSnapshot.ID(value: value)
    }
}

/// UTF-16 range in canonical Markdown source.
///
/// // REQ-087: distinct from `ProjectionRange` so the compiler blocks cross-domain mixups.
nonisolated struct SourceRange: Sendable, Equatable {
    let utf16: NSRange

    init(_ utf16: NSRange) {
        self.utf16 = utf16
    }

    var location: Int { utf16.location }
    var length: Int { utf16.length }
    var nsMax: Int { NSMaxRange(utf16) }
}

/// UTF-16 range in WYSIWYG projection storage for a known projection revision.
nonisolated struct ProjectionRange: Sendable, Equatable {
    let utf16: NSRange
    let revision: ProjectionRevision

    init(_ utf16: NSRange, revision: ProjectionRevision) {
        self.utf16 = utf16
        self.revision = revision
    }
}

/// Source-domain selection with affinity.
///
/// // REQ-083/084: affinity is part of the typed selection, not a side channel.
nonisolated struct SourceSelection: Sendable, Equatable {
    let range: SourceRange
    let affinity: SelectionAffinity

    init(range: SourceRange, affinity: SelectionAffinity = .downstream) {
        self.range = range
        self.affinity = affinity
    }

    init(utf16: NSRange, affinity: SelectionAffinity = .downstream) {
        self.range = SourceRange(utf16)
        self.affinity = affinity
    }

    /// Compatibility: callers that historically treated selection as a bare NSRange.
    var nsRange: NSRange { range.utf16 }
}

/// Projection-domain selection with affinity and revision.
nonisolated struct ProjectionSelection: Sendable, Equatable {
    let range: ProjectionRange
    let affinity: SelectionAffinity

    init(range: ProjectionRange, affinity: SelectionAffinity = .downstream) {
        self.range = range
        self.affinity = affinity
    }

    init(utf16: NSRange, revision: ProjectionRevision, affinity: SelectionAffinity = .downstream) {
        self.range = ProjectionRange(utf16, revision: revision)
        self.affinity = affinity
    }

    var nsRange: NSRange { range.utf16 }
}

/// Selection domain for a single edit request.
nonisolated enum EditorSelection: Sendable, Equatable {
    case source(SourceSelection)
    case projection(ProjectionSelection)
}

/// One typed request into the semantic edit pipeline.
///
/// // REQ-057/083/087: every adapter submits domain, revision, grouping, and command together.
nonisolated struct EditorEditRequest: Sendable, Equatable {
    let command: SemanticCommand
    let selection: EditorSelection
    let expectedSourceRevision: SourceRevision
    let grouping: MutationGrouping
}

/// Semantic context intersecting a WYSIWYG edit.
nonisolated enum SemanticEditContext: Sendable, Equatable {
    case plainText
    case inlineSemantics
    case linkLabel
    case tableCell(nodeID: MarkdownNodeID)
    case codeContent
    case taskMarker(nodeID: MarkdownNodeID)
    case uneditable
    case ambiguous
}
