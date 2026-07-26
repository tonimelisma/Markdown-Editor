//
//  PresentationSnapshot.swift
//  Markdown Editor
//

import Foundation

/// Indivisible WYSIWYG presentation for one editable revision.
///
/// // REQ-091/093; ARC-003/004/005: fields travel together; never mix two snapshots.
nonisolated struct PresentationSnapshot: Sendable, Equatable {
    /// Opaque monotonic identity — not interchangeable with `SourceRevision`.
    struct ID: Hashable, Sendable, Comparable {
        let value: UInt64

        static func < (lhs: ID, rhs: ID) -> Bool {
            lhs.value < rhs.value
        }
    }

    let id: ID
    let sourceRevision: SourceRevision
    let locationGeneration: UInt64
    let renderedString: String
    let runs: [ProjectionRun]
    let attachments: [ProjectionAttachment]
    let tables: [ProjectionTable]
    let listMarkers: [ProjectionListMarker]
    let atoms: [ProjectionAtom]
    let sourceUTF16Count: Int
    /// Coordinate map built once at construction — never re-derived from mutable arrays.
    let coordinateMap: ProjectionCoordinateMap

    var projectionRevision: ProjectionRevision {
        ProjectionRevision(snapshotID: id)
    }

    var segments: [ProjectionSegment] {
        ProjectionAtom.toSegments(atoms)
    }

    /// Compatibility view used while planners still consume `MarkdownProjectionModel`.
    var asProjectionModel: MarkdownProjectionModel {
        MarkdownProjectionModel(
            sourceVersion: sourceRevision.value,
            renderedString: renderedString,
            runs: runs,
            attachments: attachments,
            tables: tables,
            segments: segments,
            listMarkers: listMarkers,
            sourceUTF16Count: sourceUTF16Count,
            prebuiltMap: coordinateMap
        )
    }

    static func make(
        id: ID,
        sourceRevision: SourceRevision,
        locationGeneration: UInt64,
        renderedString: String,
        runs: [ProjectionRun],
        attachments: [ProjectionAttachment],
        tables: [ProjectionTable],
        listMarkers: [ProjectionListMarker] = [],
        atoms: [ProjectionAtom],
        sourceUTF16Count: Int
    ) -> PresentationSnapshot {
        let segments = ProjectionAtom.toSegments(atoms)
        let map = ProjectionCoordinateMap(
            segments: segments,
            projectionUTF16Count: (renderedString as NSString).length,
            sourceUTF16Count: sourceUTF16Count
        )
        return PresentationSnapshot(
            id: id,
            sourceRevision: sourceRevision,
            locationGeneration: locationGeneration,
            renderedString: renderedString,
            runs: runs,
            attachments: attachments,
            tables: tables,
            listMarkers: listMarkers,
            atoms: atoms,
            sourceUTF16Count: sourceUTF16Count,
            coordinateMap: map
        )
    }

    static func from(
        model: MarkdownProjectionModel,
        id: ID,
        locationGeneration: UInt64
    ) -> PresentationSnapshot {
        make(
            id: id,
            sourceRevision: SourceRevision(value: model.sourceVersion),
            locationGeneration: locationGeneration,
            renderedString: model.renderedString,
            runs: model.runs,
            attachments: model.attachments,
            tables: model.tables,
            listMarkers: model.listMarkers,
            atoms: ProjectionAtom.from(segments: model.segments),
            sourceUTF16Count: model.sourceUTF16Count
        )
    }
}

/// Monotonic factory for presentation snapshot identities.
@MainActor
final class PresentationSnapshotIDFactory {
    private var next: UInt64 = 1

    func make() -> PresentationSnapshot.ID {
        defer { next &+= 1 }
        return PresentationSnapshot.ID(value: next)
    }
}
