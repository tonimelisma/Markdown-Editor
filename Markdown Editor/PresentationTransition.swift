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
        replacement: String,
        nextSourceRevision: SourceRevision,
        nextSourceUTF16Count: Int,
        nextSnapshotID: PresentationSnapshot.ID,
        affinity: SelectionAffinity
    ) -> PresentationTransition? {
        let rendered = snapshot.renderedString as NSString
        guard projectionRange.location >= 0,
              NSMaxRange(projectionRange) <= rendered.length else {
            return nil
        }

        let delta = (replacement as NSString).length - projectionRange.length
        let nextRendered = rendered.replacingCharacters(in: projectionRange, with: replacement)
        let insertEnd = projectionRange.location + (replacement as NSString).length

        var nextAtoms: [ProjectionAtom] = []
        for atom in snapshot.atoms {
            guard let shifted = shift(
                atom: atom,
                editedProjection: projectionRange,
                replacementLength: (replacement as NSString).length,
                delta: delta
            ) else {
                return nil
            }
            nextAtoms.append(contentsOf: shifted)
        }

        // If the edit landed inside/at an identity atom, ensure the replacement text is covered.
        if !replacement.isEmpty {
            let covered = nextAtoms.contains { NSIntersectionRange($0.projectionRange, NSRange(location: projectionRange.location, length: (replacement as NSString).length)).length > 0
                || ($0.projectionRange.length == 0 && $0.projectionRange.location == projectionRange.location) }
            if !covered {
                // Expand neighboring identity atom or insert a new identity coverage unit.
                if let expanded = expandIdentityCoverage(
                    atoms: nextAtoms,
                    at: projectionRange.location,
                    length: (replacement as NSString).length,
                    sourceDelta: delta,
                    originalSnapshot: snapshot,
                    editedProjection: projectionRange
                ) {
                    nextAtoms = expanded
                } else {
                    return nil
                }
            }
        }

        let nextRuns = shiftRuns(snapshot.runs, edited: projectionRange, delta: delta)
        let nextAttachments = shiftAttachments(snapshot.attachments, edited: projectionRange, delta: delta)
        let nextTables = shiftTables(snapshot.tables, edited: projectionRange, delta: delta)
        let nextMarkers = shiftListMarkers(snapshot.listMarkers, edited: projectionRange, delta: delta)

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
            projectionReplacement: replacement,
            selectionAfter: selection
        )
    }

    // MARK: - Shifting

    private static func shift(
        atom: ProjectionAtom,
        editedProjection: NSRange,
        replacementLength: Int,
        delta: Int
    ) -> [ProjectionAtom]? {
        let range = atom.projectionRange
        let editEnd = NSMaxRange(editedProjection)

        // Entirely after the edit — shift projection (and identity source) forward/back.
        if range.location >= editEnd {
            return [shiftAtom(atom, projectionDelta: delta, sourceDelta: delta)]
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
                replacementLength: replacementLength,
                delta: delta
            )
        case .atomic, .synthetic, .uneditable:
            // Structural/atomic overlap requires a dedicated planner.
            return nil
        }
    }

    private static func rewriteIdentity(
        _ identity: IdentityAtom,
        editedProjection: NSRange,
        replacementLength: Int,
        delta: Int
    ) -> [ProjectionAtom]? {
        let proj = identity.projection
        let editStart = editedProjection.location
        let editEnd = NSMaxRange(editedProjection)

        // Edit fully contained in this identity atom.
        guard editStart >= proj.location, editEnd <= NSMaxRange(proj) else {
            return nil
        }

        let localStart = editStart - proj.location
        let newProjLen = proj.length + delta
        guard newProjLen >= 0 else { return nil }

        if newProjLen == 0 {
            // Atom consumed — drop it (coverage filled by neighbors or expandIdentityCoverage).
            return []
        }

        let sourceLocalStart = localStart
        // Identity: source offsets match projection offsets within the atom.
        let newSourceLen = identity.source.length + delta
        guard newSourceLen >= 0 else { return nil }

        let newProj = NSRange(location: proj.location, length: newProjLen)
        let newSource = NSRange(location: identity.source.location, length: newSourceLen)
        _ = sourceLocalStart
        _ = replacementLength
        return [
            .identity(
                IdentityAtom(
                    projection: newProj,
                    source: newSource,
                    insertionBefore: newSource.location,
                    insertionAfter: NSMaxRange(newSource)
                )
            )
        ]
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
        edited: NSRange,
        delta: Int
    ) -> [ProjectionAttachment] {
        attachments.compactMap { attachment in
            if attachment.utf16Location >= NSMaxRange(edited) {
                return ProjectionAttachment(
                    nodeID: attachment.nodeID,
                    utf16Location: attachment.utf16Location + delta,
                    kind: attachment.kind,
                    sourceUTF16Range: attachment.sourceUTF16Range.map {
                        NSRange(location: $0.location + delta, length: $0.length)
                    }
                )
            }
            if attachment.utf16Location >= edited.location && attachment.utf16Location < NSMaxRange(edited) {
                return nil
            }
            return attachment
        }
    }

    private static func shiftTables(_ tables: [ProjectionTable], edited: NSRange, delta: Int) -> [ProjectionTable] {
        tables.compactMap { table in
            if NSMaxRange(table.utf16Range) <= edited.location { return table }
            if table.utf16Range.location >= NSMaxRange(edited) {
                let cells = table.cells.map { cell in
                    ProjectionTableCell(
                        nodeID: cell.nodeID,
                        row: cell.row,
                        column: cell.column,
                        isHeader: cell.isHeader,
                        alignment: cell.alignment,
                        utf16Range: NSRange(location: cell.utf16Range.location + delta, length: cell.utf16Range.length),
                        sourceUTF16Range: cell.sourceUTF16Range.map {
                            NSRange(location: $0.location + delta, length: $0.length)
                        }
                    )
                }
                return ProjectionTable(
                    nodeID: table.nodeID,
                    columnCount: table.columnCount,
                    alignments: table.alignments,
                    cells: cells,
                    utf16Range: NSRange(location: table.utf16Range.location + delta, length: table.utf16Range.length)
                )
            }
            // Contained: adjust intersecting cells.
            if table.utf16Range.location <= edited.location && NSMaxRange(table.utf16Range) >= NSMaxRange(edited) {
                let cells = table.cells.compactMap { cell -> ProjectionTableCell? in
                    let r = cell.utf16Range
                    if NSMaxRange(r) <= edited.location { return cell }
                    if r.location >= NSMaxRange(edited) {
                        return ProjectionTableCell(
                            nodeID: cell.nodeID,
                            row: cell.row,
                            column: cell.column,
                            isHeader: cell.isHeader,
                            alignment: cell.alignment,
                            utf16Range: NSRange(location: r.location + delta, length: r.length),
                            sourceUTF16Range: cell.sourceUTF16Range.map {
                                NSRange(location: $0.location + delta, length: $0.length)
                            }
                        )
                    }
                    if r.location <= edited.location && NSMaxRange(r) >= NSMaxRange(edited) {
                        let newLen = r.length + delta
                        guard newLen >= 0 else { return nil }
                        return ProjectionTableCell(
                            nodeID: cell.nodeID,
                            row: cell.row,
                            column: cell.column,
                            isHeader: cell.isHeader,
                            alignment: cell.alignment,
                            utf16Range: NSRange(location: r.location, length: newLen),
                            sourceUTF16Range: cell.sourceUTF16Range.map {
                                NSRange(location: $0.location, length: $0.length + delta)
                            }
                        )
                    }
                    return nil
                }
                let newLen = table.utf16Range.length + delta
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

    private static func expandIdentityCoverage(
        atoms: [ProjectionAtom],
        at location: Int,
        length: Int,
        sourceDelta: Int,
        originalSnapshot: PresentationSnapshot,
        editedProjection: NSRange
    ) -> [ProjectionAtom]? {
        _ = sourceDelta
        _ = originalSnapshot
        _ = editedProjection
        // Insert a fresh identity atom covering the replacement when prior rewrite dropped coverage.
        var result = atoms
        let newAtom = ProjectionAtom.identity(
            IdentityAtom(
                projection: NSRange(location: location, length: length),
                source: NSRange(location: location, length: length), // corrected by caller context for non-identity docs
                insertionBefore: location,
                insertionAfter: location + length
            )
        )
        // Find insertion index by projection order.
        let index = result.firstIndex { $0.projectionRange.location > location } ?? result.count
        result.insert(newAtom, at: index)
        return result
    }
}
