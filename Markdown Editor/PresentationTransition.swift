//
//  PresentationTransition.swift
//  Markdown Editor
//

import Foundation

/// Exact synchronous update from one presentation snapshot to the next.
///
/// // REQ-091; ARC-005: validated before commit; non-failable after source commit.
nonisolated struct PresentationTransition: Sendable, Equatable {
    let fromSnapshotID: PresentationSnapshot.ID
    let nextSnapshot: PresentationSnapshot
    let projectionReplacementRange: NSRange
    let projectionReplacement: String
    let selectionAfter: ProjectionSelection
}

/// Outcome of classifying/planning an edit against current session state.
///
/// // REQ-057/091; ARC-005/009: accepted carries source + presentation together, or neither.
nonisolated struct AcceptedEdit: Sendable, Equatable {
    let sourceMutation: SourceMutation
    let presentationTransition: PresentationTransition?
    let sourceSelectionAfter: SourceSelection
    let projectionSelectionAfter: ProjectionSelection?
}

nonisolated enum EditRefusal: Sendable, Equatable {
    case staleVersion
    case stalePresentation
    case ambiguousSelection
    case unsupportedCommand
    case mappingFailure
    case invalidRange
    case unavailable
    case mixedDomain
    case crossCell
    case unprovable

    var asSemantic: SemanticEditRefusal {
        switch self {
        case .staleVersion, .stalePresentation, .unavailable:
            return .staleVersion
        case .ambiguousSelection, .mixedDomain, .crossCell, .unprovable:
            return .ambiguousSelection
        case .unsupportedCommand:
            return .unsupportedCommand
        case .mappingFailure:
            return .mappingFailure
        case .invalidRange:
            return .invalidRange
        }
    }
}

nonisolated enum EditorEditOutcome: Sendable, Equatable {
    case accepted(AcceptedEdit)
    case refused(EditRefusal)
}

/// Builds provisional presentation transitions for proven local identity edits.
///
/// // REQ-091/092; ARC-005/008: no approximate structural rewrites.
nonisolated enum PresentationTransitionPlanner {
    /// Identity text insert/replace/delete against contiguous identity atoms.
    static func identityReplacement(
        snapshot: PresentationSnapshot,
        projectionRange: NSRange,
        visibleReplacement: String,
        sourceRange: NSRange,
        sourceReplacement: String,
        nextSourceRevision: SourceRevision,
        nextSourceUTF16Count: Int,
        nextSnapshotID: PresentationSnapshot.ID,
        affinity: SelectionAffinity
    ) -> PresentationTransition? {
        let rendered = snapshot.renderedString as NSString
        guard projectionRange.location >= 0,
              NSMaxRange(projectionRange) <= rendered.length,
              sourceRange.location >= 0,
              NSMaxRange(sourceRange) <= snapshot.sourceUTF16Count else {
            return nil
        }

        let projectionDelta = (visibleReplacement as NSString).length - projectionRange.length
        let sourceDelta = (sourceReplacement as NSString).length - sourceRange.length
        let nextRendered = rendered.replacingCharacters(in: projectionRange, with: visibleReplacement)
        let insertEnd = projectionRange.location + (visibleReplacement as NSString).length

        var nextAtoms: [ProjectionAtom] = []
        for atom in snapshot.atoms {
            guard let shifted = shift(
                atom: atom,
                editedProjection: projectionRange,
                editedSource: sourceRange,
                visibleReplacement: visibleReplacement,
                sourceReplacement: sourceReplacement,
                projectionDelta: projectionDelta,
                sourceDelta: sourceDelta
            ) else {
                return nil
            }
            nextAtoms.append(contentsOf: shifted)
        }

        // If the edit landed inside/at an identity atom, ensure the replacement text is covered.
        if !visibleReplacement.isEmpty {
            let covered = nextAtoms.contains { NSIntersectionRange($0.projectionRange, NSRange(location: projectionRange.location, length: (visibleReplacement as NSString).length)).length > 0
                || ($0.projectionRange.length == 0 && $0.projectionRange.location == projectionRange.location) }
            if !covered {
                guard let inserted = ProjectionAtom.concreteAtoms(
                    projectionLocation: projectionRange.location,
                    sourceLocation: sourceRange.location,
                    visible: visibleReplacement,
                    source: sourceReplacement
                ) else { return nil }
                nextAtoms.append(contentsOf: inserted)
                nextAtoms.sort { $0.projectionRange.location < $1.projectionRange.location }
            }
        }

        let nextRuns = shiftRuns(snapshot.runs, edited: projectionRange, delta: projectionDelta)
        let nextAttachments = shiftAttachments(
            snapshot.attachments,
            editedProjection: projectionRange,
            projectionDelta: projectionDelta,
            editedSource: sourceRange,
            sourceDelta: sourceDelta
        )
        let nextTables = shiftTables(
            snapshot.tables,
            editedProjection: projectionRange,
            projectionDelta: projectionDelta,
            editedSource: sourceRange,
            sourceDelta: sourceDelta
        )
        let nextMarkers = shiftListMarkers(snapshot.listMarkers, edited: projectionRange, delta: projectionDelta)

        let next = PresentationSnapshot.make(
            id: nextSnapshotID,
            sourceRevision: nextSourceRevision,
            locationGeneration: snapshot.locationGeneration,
            renderedString: nextRendered,
            runs: nextRuns,
            attachments: nextAttachments,
            tables: nextTables,
            listMarkers: nextMarkers,
            atoms: nextAtoms,
            sourceUTF16Count: nextSourceUTF16Count
        )

        let selection = ProjectionSelection(
            utf16: NSRange(location: insertEnd, length: 0),
            revision: next.projectionRevision,
            affinity: affinity
        )
        return PresentationTransition(
            fromSnapshotID: snapshot.id,
            nextSnapshot: next,
            projectionReplacementRange: projectionRange,
            projectionReplacement: visibleReplacement,
            selectionAfter: selection
        )
    }

    // MARK: - Shifting

    private static func shift(
        atom: ProjectionAtom,
        editedProjection: NSRange,
        editedSource: NSRange,
        visibleReplacement: String,
        sourceReplacement: String,
        projectionDelta: Int,
        sourceDelta: Int
    ) -> [ProjectionAtom]? {
        let range = atom.projectionRange
        let editEnd = NSMaxRange(editedProjection)

        // Entirely after the edit — shift projection (and identity source) forward/back.
        if range.location >= editEnd {
            return [shiftAtom(atom, projectionDelta: projectionDelta, sourceDelta: sourceDelta)]
        }

        // Entirely before the edit — unchanged.
        if NSMaxRange(range) <= editedProjection.location {
            return [atom]
        }

        // Overlaps the edit — only identity atoms with exact coverage may be rewritten locally.
        switch atom {
        case .identity(let identity):
            return rewriteIdentity(
                identity,
                editedProjection: editedProjection,
                editedSource: editedSource,
                visibleReplacement: visibleReplacement,
                sourceReplacement: sourceReplacement
            )
        case .atomic(let atomic):
            guard editedProjection == atomic.projection,
                  editedSource == atomic.source else {
                return nil
            }
            return ProjectionAtom.concreteAtoms(
                projectionLocation: editedProjection.location,
                sourceLocation: editedSource.location,
                visible: visibleReplacement,
                source: sourceReplacement
            )
        case .synthetic, .uneditable:
            // Structural overlap requires a dedicated planner.
            return nil
        }
    }

    private static func rewriteIdentity(
        _ identity: IdentityAtom,
        editedProjection: NSRange,
        editedSource: NSRange,
        visibleReplacement: String,
        sourceReplacement: String
    ) -> [ProjectionAtom]? {
        let proj = identity.projection
        let editStart = editedProjection.location
        let editEnd = NSMaxRange(editedProjection)

        // Edit fully contained in this identity atom.
        guard editStart >= proj.location,
              editEnd <= NSMaxRange(proj),
              editedSource.location >= identity.source.location,
              NSMaxRange(editedSource) <= NSMaxRange(identity.source) else {
            return nil
        }

        let beforeProjectionLength = editedProjection.location - proj.location
        let beforeSourceLength = editedSource.location - identity.source.location
        let afterProjectionLength = NSMaxRange(proj) - NSMaxRange(editedProjection)
        let afterSourceLength = NSMaxRange(identity.source) - NSMaxRange(editedSource)
        guard beforeProjectionLength == beforeSourceLength,
              afterProjectionLength == afterSourceLength else {
            return nil
        }

        var result: [ProjectionAtom] = []
        if beforeProjectionLength > 0 {
            result.append(
                .identity(
                    IdentityAtom(
                        projection: NSRange(location: proj.location, length: beforeProjectionLength),
                        source: NSRange(location: identity.source.location, length: beforeSourceLength),
                        insertionBefore: identity.source.location,
                        insertionAfter: identity.source.location + beforeSourceLength
                    )
                )
            )
        }

        guard let replacement = ProjectionAtom.concreteAtoms(
            projectionLocation: editedProjection.location,
            sourceLocation: editedSource.location,
            visible: visibleReplacement,
            source: sourceReplacement
        ) else { return nil }
        result.append(contentsOf: replacement)

        if afterProjectionLength > 0 {
            let projectionLocation = editedProjection.location + (visibleReplacement as NSString).length
            let sourceLocation = editedSource.location + (sourceReplacement as NSString).length
            result.append(
                .identity(
                    IdentityAtom(
                        projection: NSRange(location: projectionLocation, length: afterProjectionLength),
                        source: NSRange(location: sourceLocation, length: afterSourceLength),
                        insertionBefore: sourceLocation,
                        insertionAfter: sourceLocation + afterSourceLength
                    )
                )
            )
        }
        return result
    }

    private static func shiftAtom(_ atom: ProjectionAtom, projectionDelta: Int, sourceDelta: Int) -> ProjectionAtom {
        switch atom {
        case .identity(let a):
            return .identity(
                IdentityAtom(
                    projection: NSRange(location: a.projection.location + projectionDelta, length: a.projection.length),
                    source: NSRange(location: a.source.location + sourceDelta, length: a.source.length),
                    insertionBefore: a.insertionBefore + sourceDelta,
                    insertionAfter: a.insertionAfter + sourceDelta
                )
            )
        case .atomic(let a):
            return .atomic(
                AtomicSourceAtom(
                    kind: a.kind,
                    projection: NSRange(location: a.projection.location + projectionDelta, length: a.projection.length),
                    source: NSRange(location: a.source.location + sourceDelta, length: a.source.length),
                    insertionBefore: a.insertionBefore + sourceDelta,
                    insertionAfter: a.insertionAfter + sourceDelta,
                    decodedText: a.decodedText
                )
            )
        case .synthetic(let a):
            return .synthetic(
                SyntheticAtom(
                    projection: NSRange(location: a.projection.location + projectionDelta, length: a.projection.length),
                    kind: a.kind,
                    insertion: shiftInsertion(a.insertion, by: sourceDelta)
                )
            )
        case .uneditable(let a):
            return .uneditable(
                UneditableAtom(
                    projection: NSRange(location: a.projection.location + projectionDelta, length: a.projection.length),
                    reason: a.reason
                )
            )
        }
    }

    private static func shiftInsertion(_ policy: SyntheticInsertionPolicy, by delta: Int) -> SyntheticInsertionPolicy {
        switch policy {
        case .atSourceLocation(let loc):
            return .atSourceLocation(loc + delta)
        case .atSourceBoundaries(let before, let after):
            return .atSourceBoundaries(before: before + delta, after: after + delta)
        case .refuse:
            return .refuse
        }
    }

    private static func shiftRuns(_ runs: [ProjectionRun], edited: NSRange, delta: Int) -> [ProjectionRun] {
        runs.compactMap { run in
            let r = run.utf16Range
            if NSMaxRange(r) <= edited.location { return run }
            if r.location >= NSMaxRange(edited) {
                return ProjectionRun(
                    nodeID: run.nodeID,
                    utf16Range: NSRange(location: r.location + delta, length: r.length),
                    styles: run.styles,
                    linkDestination: run.linkDestination,
                    isLiteralFallback: run.isLiteralFallback
                )
            }
            // Contained rewrite: expand/shrink.
            if r.location <= edited.location && NSMaxRange(r) >= NSMaxRange(edited) {
                let newLen = r.length + delta
                guard newLen >= 0 else { return nil }
                return ProjectionRun(
                    nodeID: run.nodeID,
                    utf16Range: NSRange(location: r.location, length: newLen),
                    styles: run.styles,
                    linkDestination: run.linkDestination,
                    isLiteralFallback: run.isLiteralFallback
                )
            }
            return nil
        }
    }

    private static func shiftAttachments(
        _ attachments: [ProjectionAttachment],
        editedProjection: NSRange,
        projectionDelta: Int,
        editedSource: NSRange,
        sourceDelta: Int
    ) -> [ProjectionAttachment] {
        attachments.compactMap { attachment in
            if attachment.utf16Location >= NSMaxRange(editedProjection) {
                return ProjectionAttachment(
                    nodeID: attachment.nodeID,
                    utf16Location: attachment.utf16Location + projectionDelta,
                    kind: attachment.kind,
                    sourceUTF16Range: attachment.sourceUTF16Range.map {
                        shiftSourceRange($0, edited: editedSource, delta: sourceDelta)
                    }
                )
            }
            if attachment.utf16Location >= editedProjection.location
                && attachment.utf16Location < NSMaxRange(editedProjection) {
                return nil
            }
            return attachment
        }
    }

    private static func shiftTables(
        _ tables: [ProjectionTable],
        editedProjection: NSRange,
        projectionDelta: Int,
        editedSource: NSRange,
        sourceDelta: Int
    ) -> [ProjectionTable] {
        tables.compactMap { table in
            if NSMaxRange(table.utf16Range) <= editedProjection.location { return table }
            if table.utf16Range.location >= NSMaxRange(editedProjection) {
                let cells = table.cells.map { cell in
                    ProjectionTableCell(
                        nodeID: cell.nodeID,
                        row: cell.row,
                        column: cell.column,
                        isHeader: cell.isHeader,
                        alignment: cell.alignment,
                        utf16Range: NSRange(
                            location: cell.utf16Range.location + projectionDelta,
                            length: cell.utf16Range.length
                        ),
                        sourceUTF16Range: cell.sourceUTF16Range.map {
                            shiftSourceRange($0, edited: editedSource, delta: sourceDelta)
                        }
                    )
                }
                return ProjectionTable(
                    nodeID: table.nodeID,
                    columnCount: table.columnCount,
                    alignments: table.alignments,
                    cells: cells,
                    utf16Range: NSRange(
                        location: table.utf16Range.location + projectionDelta,
                        length: table.utf16Range.length
                    )
                )
            }
            // Contained: adjust intersecting cells.
            if table.utf16Range.location <= editedProjection.location
                && NSMaxRange(table.utf16Range) >= NSMaxRange(editedProjection) {
                let cells = table.cells.compactMap { cell -> ProjectionTableCell? in
                    let r = cell.utf16Range
                    if NSMaxRange(r) <= editedProjection.location { return cell }
                    if r.location >= NSMaxRange(editedProjection) {
                        return ProjectionTableCell(
                            nodeID: cell.nodeID,
                            row: cell.row,
                            column: cell.column,
                            isHeader: cell.isHeader,
                            alignment: cell.alignment,
                            utf16Range: NSRange(location: r.location + projectionDelta, length: r.length),
                            sourceUTF16Range: cell.sourceUTF16Range.map {
                                shiftSourceRange($0, edited: editedSource, delta: sourceDelta)
                            }
                        )
                    }
                    if r.location <= editedProjection.location
                        && NSMaxRange(r) >= NSMaxRange(editedProjection) {
                        let newLen = r.length + projectionDelta
                        guard newLen >= 0 else { return nil }
                        return ProjectionTableCell(
                            nodeID: cell.nodeID,
                            row: cell.row,
                            column: cell.column,
                            isHeader: cell.isHeader,
                            alignment: cell.alignment,
                            utf16Range: NSRange(location: r.location, length: newLen),
                            sourceUTF16Range: cell.sourceUTF16Range.map {
                                NSRange(location: $0.location, length: $0.length + sourceDelta)
                            }
                        )
                    }
                    return nil
                }
                let newLen = table.utf16Range.length + projectionDelta
                guard newLen >= 0 else { return nil }
                return ProjectionTable(
                    nodeID: table.nodeID,
                    columnCount: table.columnCount,
                    alignments: table.alignments,
                    cells: cells,
                    utf16Range: NSRange(location: table.utf16Range.location, length: newLen)
                )
            }
            return nil
        }
    }

    private static func shiftListMarkers(
        _ markers: [ProjectionListMarker],
        edited: NSRange,
        delta: Int
    ) -> [ProjectionListMarker] {
        markers.compactMap { marker in
            let r = marker.utf16Range
            if NSMaxRange(r) <= edited.location { return marker }
            if r.location >= NSMaxRange(edited) {
                return ProjectionListMarker(
                    nodeID: marker.nodeID,
                    utf16Range: NSRange(location: r.location + delta, length: r.length),
                    text: marker.text,
                    nesting: marker.nesting,
                    kind: marker.kind
                )
            }
            return nil
        }
    }

    private static func shiftSourceRange(_ range: NSRange, edited: NSRange, delta: Int) -> NSRange {
        if range.location >= NSMaxRange(edited) {
            return NSRange(location: range.location + delta, length: range.length)
        }
        if range.location <= edited.location, NSMaxRange(range) >= NSMaxRange(edited) {
            return NSRange(location: range.location, length: range.length + delta)
        }
        return range
    }

}
