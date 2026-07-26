//
//  ProjectionAtom.swift
//  Markdown Editor
//

import Foundation

/// Concrete inverse for atomic source representations (entities, escapes, markers).
///
/// // REQ-087/092; ARC-007/008: editable only when decoder and encoder are proven.
nonisolated enum AtomicRepresentationKind: Sendable, Equatable {
    case htmlEntity
    case backslashEscape
    case taskMarker
    case softBreak
    case hardBreak
}

nonisolated struct IdentityAtom: Sendable, Equatable {
    let projection: NSRange
    let source: NSRange
    let insertionBefore: Int
    let insertionAfter: Int
}

nonisolated struct AtomicSourceAtom: Sendable, Equatable {
    let kind: AtomicRepresentationKind
    let projection: NSRange
    let source: NSRange
    let insertionBefore: Int
    let insertionAfter: Int
    let decodedText: String
}

nonisolated struct SyntheticAtom: Sendable, Equatable {
    let projection: NSRange
    let kind: SyntheticKind
    let insertion: SyntheticInsertionPolicy
}

nonisolated struct UneditableAtom: Sendable, Equatable {
    let projection: NSRange
    let reason: ProjectionRefusal
}

/// One coverage unit of a presented WYSIWYG snapshot.
///
/// // REQ-054–056/087; ARC-003/007: identity, atomic, synthetic, or uneditable — never guessed.
nonisolated enum ProjectionAtom: Sendable, Equatable {
    case identity(IdentityAtom)
    case atomic(AtomicSourceAtom)
    case synthetic(SyntheticAtom)
    case uneditable(UneditableAtom)

    var projectionRange: NSRange {
        switch self {
        case .identity(let atom): return atom.projection
        case .atomic(let atom): return atom.projection
        case .synthetic(let atom): return atom.projection
        case .uneditable(let atom): return atom.projection
        }
    }

    /// Build atoms from legacy projection segments (identity-mapped until encoder coverage expands).
    static func from(segments: [ProjectionSegment]) -> [ProjectionAtom] {
        segments.map { segment in
            switch segment {
            case .source(let projection, let source, let before, let after):
                return .identity(
                    IdentityAtom(
                        projection: projection,
                        source: source,
                        insertionBefore: before,
                        insertionAfter: after
                    )
                )
            case .synthetic(let projection, let kind, let insertion):
                return .synthetic(
                    SyntheticAtom(projection: projection, kind: kind, insertion: insertion)
                )
            case .literalFallback(let projection, let source):
                return .identity(
                    IdentityAtom(
                        projection: projection,
                        source: source,
                        insertionBefore: source.location,
                        insertionAfter: NSMaxRange(source)
                    )
                )
            case .uneditable(let projection, let reason):
                return .uneditable(UneditableAtom(projection: projection, reason: reason))
            }
        }
    }

    /// Convert atoms back to segments for coordinate-map construction.
    static func toSegments(_ atoms: [ProjectionAtom]) -> [ProjectionSegment] {
        atoms.map { atom in
            switch atom {
            case .identity(let a):
                return .source(
                    projection: a.projection,
                    source: a.source,
                    insertionBefore: a.insertionBefore,
                    insertionAfter: a.insertionAfter
                )
            case .atomic(let a):
                return .source(
                    projection: a.projection,
                    source: a.source,
                    insertionBefore: a.insertionBefore,
                    insertionAfter: a.insertionAfter
                )
            case .synthetic(let a):
                return .synthetic(projection: a.projection, kind: a.kind, insertion: a.insertion)
            case .uneditable(let a):
                return .uneditable(projection: a.projection, reason: a.reason)
            }
        }
    }
}
