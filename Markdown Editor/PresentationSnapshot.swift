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
    let blocks: [PresentationBlock]
    let listMarkers: [ProjectionListMarker]
    let atoms: [ProjectionAtom]
    let sourceUTF16Count: Int
    /// Coordinate map built once at construction — never re-derived from mutable arrays.
    let coordinateMap: ProjectionCoordinateMap
    /// Oracle result is fixed with the immutable snapshot; callers must not re-run the whole
    /// document validation pass for the same identity.
    private let oracleValid: Bool

    var isOracleValid: Bool { oracleValid }

    var projectionRevision: ProjectionRevision {
        ProjectionRevision(snapshotID: id)
    }

    var segments: [ProjectionSegment] {
        ProjectionAtom.toSegments(atoms)
    }

    /// The local transition route proves its snapshot by preserving every affected atom and
    /// coordinate boundary in `PresentationTransitionPlanner`. It must not repeat the
    /// whole-document oracle on the input callback; authoritative snapshots still use the
    /// oracle during reconciliation.
    enum ConstructionProof: Sendable {
        case authoritative
        case locallyProven
        case boundedLocallyProven
    }

    /// COR-40: Total block identification for `reshapesWholeLine` — `caretLocation ∈ projectionRange`.
    /// Total when `caret ∈ renderedString`; `table`/`tableRow`/`tableCell` stay exact via classifier.
    func enclosingBlock(at location: Int) -> PresentationBlock? {
        let candidates = blocks.filter {
            NSLocationInRange(location, $0.projectionRange) || location == NSMaxRange($0.projectionRange)
        }
        // Smallest enclosing wins (most specific block).
        return candidates
            .filter {
                switch $0.kind {
                case .table, .tableRow, .tableCell: return false
                default: return true
                }
            }
            .min(by: { $0.projectionRange.length < $1.projectionRange.length })
    }

    /// Compatibility view used while planners still consume `MarkdownProjectionModel`.
    var asProjectionModel: MarkdownProjectionModel {
        MarkdownProjectionModel(
            sourceVersion: sourceRevision.value,
            renderedString: renderedString,
            runs: runs,
            attachments: attachments,
            tables: tables,
            blocks: blocks,
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
        blocks: [PresentationBlock] = [],
        listMarkers: [ProjectionListMarker] = [],
        atoms: [ProjectionAtom],
        sourceUTF16Count: Int
    ) -> PresentationSnapshot {
        make(
            id: id,
            sourceRevision: sourceRevision,
            locationGeneration: locationGeneration,
            renderedString: renderedString,
            runs: runs,
            attachments: attachments,
            tables: tables,
            blocks: blocks,
            listMarkers: listMarkers,
            atoms: atoms,
            sourceUTF16Count: sourceUTF16Count,
            proof: .authoritative
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
        blocks: [PresentationBlock] = [],
        listMarkers: [ProjectionListMarker] = [],
        atoms: [ProjectionAtom],
        sourceUTF16Count: Int,
        proof: ConstructionProof
    ) -> PresentationSnapshot {
        let segments = ProjectionAtom.toSegments(atoms)
        let map = ProjectionCoordinateMap(
            segments: segments,
            projectionUTF16Count: (renderedString as NSString).length,
            sourceUTF16Count: sourceUTF16Count
        )
        let candidate = PresentationSnapshot(
            id: id,
            sourceRevision: sourceRevision,
            locationGeneration: locationGeneration,
            renderedString: renderedString,
            runs: runs,
            attachments: attachments,
            tables: tables,
            blocks: blocks,
            listMarkers: listMarkers,
            atoms: atoms,
            sourceUTF16Count: sourceUTF16Count,
            coordinateMap: map,
            oracleValid: true
        )
        let valid: Bool
        switch proof {
        case .authoritative:
            if case .success = ProjectionOracle.validate(snapshot: candidate) {
                valid = true
            } else {
                valid = false
            }
        case .locallyProven, .boundedLocallyProven:
            valid = true
        }
        return PresentationSnapshot(
            id: candidate.id,
            sourceRevision: candidate.sourceRevision,
            locationGeneration: candidate.locationGeneration,
            renderedString: candidate.renderedString,
            runs: candidate.runs,
            attachments: candidate.attachments,
            tables: candidate.tables,
            blocks: candidate.blocks,
            listMarkers: candidate.listMarkers,
            atoms: candidate.atoms,
            sourceUTF16Count: candidate.sourceUTF16Count,
            coordinateMap: candidate.coordinateMap,
            oracleValid: valid
        )
    }

    private init(
        id: ID,
        sourceRevision: SourceRevision,
        locationGeneration: UInt64,
        renderedString: String,
        runs: [ProjectionRun],
        attachments: [ProjectionAttachment],
        tables: [ProjectionTable],
        blocks: [PresentationBlock],
        listMarkers: [ProjectionListMarker],
        atoms: [ProjectionAtom],
        sourceUTF16Count: Int,
        coordinateMap: ProjectionCoordinateMap,
        oracleValid: Bool
    ) {
        self.id = id
        self.sourceRevision = sourceRevision
        self.locationGeneration = locationGeneration
        self.renderedString = renderedString
        self.runs = runs
        self.attachments = attachments
        self.tables = tables
        self.blocks = blocks
        self.listMarkers = listMarkers
        self.atoms = atoms
        self.sourceUTF16Count = sourceUTF16Count
        self.coordinateMap = coordinateMap
        self.oracleValid = oracleValid
    }

    static func from(
        model: MarkdownProjectionModel,
        id: ID,
        locationGeneration: UInt64,
        sourceText: String
    ) -> PresentationSnapshot {
        make(
            id: id,
            sourceRevision: SourceRevision(value: model.sourceVersion),
            locationGeneration: locationGeneration,
            renderedString: model.renderedString,
            runs: model.runs,
            attachments: model.attachments,
            tables: model.tables,
            blocks: model.blocks,
            listMarkers: model.listMarkers,
            atoms: ProjectionAtom.from(
                segments: model.segments,
                sourceText: sourceText,
                renderedText: model.renderedString
            ),
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
