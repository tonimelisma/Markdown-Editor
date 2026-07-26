//
//  ProjectionSelectionClassifier.swift
//  Markdown Editor
//

import Foundation

/// Full-range classification of a projection selection against one snapshot.
///
/// // REQ-080/087; ARC-007/009: classify the complete selection; refuse mixed/cross-cell/unprovable.
nonisolated enum ProjectionSelectionClass: Sendable, Equatable {
    case identityText(sourceRange: NSRange)
    case atomicText(kind: AtomicRepresentationKind, sourceRange: NSRange, decoded: String)
    case syntheticInsertion(policy: SyntheticInsertionPolicy)
    case tableCell(nodeID: MarkdownNodeID, sourceRange: NSRange, projectionBody: NSRange)
    case taskMarker(nodeID: MarkdownNodeID)
    case uneditable(ProjectionRefusal)
    case mixed
    case crossCell
    case ambiguous
}

nonisolated enum ProjectionSelectionClassifier {
    static func classify(
        selection: NSRange,
        affinity: SelectionAffinity,
        snapshot: PresentationSnapshot
    ) -> ProjectionSelectionClass {
        let renderedLen = (snapshot.renderedString as NSString).length
        guard selection.location >= 0, NSMaxRange(selection) <= renderedLen else {
            return .uneditable(.outOfBounds)
        }

        // Task attachment hit (zero/one-length at attachment).
        for attachment in snapshot.attachments {
            if case .task = attachment.kind,
               selection.length <= 1,
               selection.location == attachment.utf16Location
                || NSLocationInRange(attachment.utf16Location, selection) {
                return .taskMarker(nodeID: attachment.nodeID)
            }
        }

        // Table cell ownership for the complete selection.
        if let tableClass = classifyTable(selection: selection, affinity: affinity, snapshot: snapshot) {
            return tableClass
        }

        let intersected = snapshot.atoms.filter { atom in
            intersects(selection, atom.projectionRange, affinity: affinity)
        }

        guard !intersected.isEmpty else {
            // Empty caret between atoms — try insertion policy at boundary.
            if selection.length == 0 {
                return classifyCaret(at: selection.location, affinity: affinity, snapshot: snapshot)
            }
            return .ambiguous
        }

        // Single-atom cases.
        if intersected.count == 1 {
            return classifySingle(intersected[0], selection: selection, snapshot: snapshot)
        }

        // Multiple atoms: only contiguous identity atoms that map to one source range are allowed.
        var sourceRanges: [NSRange] = []
        for atom in intersected {
            switch atom {
            case .identity(let identity):
                guard let mapped = mapIdentitySelection(selection, atom: identity) else {
                    return .mixed
                }
                sourceRanges.append(mapped)
            case .atomic, .synthetic, .uneditable:
                return .mixed
            }
        }

        guard let merged = mergeContiguous(sourceRanges) else { return .mixed }
        return .identityText(sourceRange: merged)
    }

    // MARK: - Private

    private static func classifySingle(
        _ atom: ProjectionAtom,
        selection: NSRange,
        snapshot: PresentationSnapshot
    ) -> ProjectionSelectionClass {
        _ = snapshot
        switch atom {
        case .identity(let identity):
            guard let source = mapIdentitySelection(selection, atom: identity) else {
                return .ambiguous
            }
            return .identityText(sourceRange: source)
        case .atomic(let atomic):
            if selection.length == 0 {
                let loc = selection.location == atomic.projection.location
                    ? atomic.insertionBefore
                    : atomic.insertionAfter
                return .identityText(sourceRange: NSRange(location: loc, length: 0))
            }
            // Non-empty must cover the whole atomic unit.
            guard selection == atomic.projection else { return .uneditable(.unsupported) }
            return .atomicText(kind: atomic.kind, sourceRange: atomic.source, decoded: atomic.decodedText)
        case .synthetic(let synthetic):
            if selection.length == 0 {
                return .syntheticInsertion(policy: synthetic.insertion)
            }
            return .uneditable(.uneditableSynthetic)
        case .uneditable(let uneditable):
            return .uneditable(uneditable.reason)
        }
    }

    private static func classifyCaret(
        at location: Int,
        affinity: SelectionAffinity,
        snapshot: PresentationSnapshot
    ) -> ProjectionSelectionClass {
        // Prefer synthetic insertion policy when caret sits on a synthetic atom.
        for atom in snapshot.atoms {
            let r = atom.projectionRange
            if location == r.location || location == NSMaxRange(r) || (location > r.location && location < NSMaxRange(r)) {
                if case .synthetic(let synthetic) = atom {
                    return .syntheticInsertion(policy: synthetic.insertion)
                }
            }
        }
        switch snapshot.coordinateMap.sourceRange(
            forProjection: NSRange(location: location, length: 0),
            affinity: affinity
        ) {
        case .exact(let source):
            return .identityText(sourceRange: source)
        case .refused(let reason):
            return .uneditable(reason)
        }
    }

    private static func classifyTable(
        selection: NSRange,
        affinity: SelectionAffinity,
        snapshot: PresentationSnapshot
    ) -> ProjectionSelectionClass? {
        let cells = snapshot.tables.flatMap(\.cells)
        guard !cells.isEmpty else { return nil }

        let hitCells = cells.filter { cell in
            let body = projectionBody(for: cell, in: snapshot)
            if selection.length == 0 {
                return caretInCell(selection.location, body: body, cell: cell, affinity: affinity, cells: cells)
            }
            return NSIntersectionRange(body, selection).length > 0
                || NSIntersectionRange(cell.utf16Range, selection).length > 0
        }

        if hitCells.isEmpty { return nil }
        if Set(hitCells.map(\.nodeID)).count > 1 {
            return .crossCell
        }
        guard let cell = hitCells.first, let source = cell.sourceUTF16Range else {
            return .uneditable(.unsupported)
        }
        let body = projectionBody(for: cell, in: snapshot)
        // Selection must stay within the cell body (or its empty caret boundaries).
        if selection.length > 0 {
            let clipped = NSIntersectionRange(selection, body)
            if clipped != selection && !(selection.length > 0 && NSLocationInRange(selection.location, cell.utf16Range)) {
                // Allow selection exactly equal to cell range including trailing tab only when replacing whole cell via body.
                if selection != cell.utf16Range {
                    // Mixed table/text if selection extends outside cell.
                    if selection.location < cell.utf16Range.location
                        || NSMaxRange(selection) > NSMaxRange(cell.utf16Range) {
                        return .mixed
                    }
                }
            }
            _ = clipped
        }
        return .tableCell(nodeID: cell.nodeID, sourceRange: source, projectionBody: body)
    }

    private static func projectionBody(for cell: ProjectionTableCell, in snapshot: PresentationSnapshot) -> NSRange {
        var bodyLength = cell.utf16Range.length
        let rendered = snapshot.renderedString as NSString
        if bodyLength > 0,
           NSMaxRange(cell.utf16Range) <= rendered.length,
           rendered.character(at: NSMaxRange(cell.utf16Range) - 1) == 0x09 {
            bodyLength -= 1
        }
        return NSRange(location: cell.utf16Range.location, length: bodyLength)
    }

    private static func caretInCell(
        _ loc: Int,
        body: NSRange,
        cell: ProjectionTableCell,
        affinity: SelectionAffinity,
        cells: [ProjectionTableCell]
    ) -> Bool {
        if body.length == 0 { return loc == body.location }
        if loc >= body.location && loc < NSMaxRange(body) { return true }
        if loc == NSMaxRange(body) {
            if affinity == .upstream { return true }
            if let index = cells.firstIndex(where: { $0.nodeID == cell.nodeID }),
               index + 1 < cells.count,
               cells[index + 1].utf16Range.location == loc {
                return false
            }
            return true
        }
        return false
    }

    private static func intersects(_ selection: NSRange, _ range: NSRange, affinity: SelectionAffinity) -> Bool {
        if selection.length == 0 {
            let loc = selection.location
            if range.length == 0 { return loc == range.location }
            if loc > range.location && loc < NSMaxRange(range) { return true }
            if loc == range.location { return affinity == .downstream || range.length == 0 }
            if loc == NSMaxRange(range) { return affinity == .upstream }
            return false
        }
        return NSIntersectionRange(selection, range).length > 0
    }

    private static func mapIdentitySelection(_ selection: NSRange, atom: IdentityAtom) -> NSRange? {
        let proj = atom.projection
        if selection.length == 0 {
            if selection.location == proj.location { return NSRange(location: atom.insertionBefore, length: 0) }
            if selection.location == NSMaxRange(proj) { return NSRange(location: atom.insertionAfter, length: 0) }
            guard selection.location > proj.location, selection.location < NSMaxRange(proj) else { return nil }
            let offset = selection.location - proj.location
            guard offset <= atom.source.length else { return nil }
            return NSRange(location: atom.source.location + offset, length: 0)
        }
        let overlap = NSIntersectionRange(selection, proj)
        guard overlap.length > 0 else { return nil }
        let startOffset = overlap.location - proj.location
        guard startOffset >= 0, startOffset + overlap.length <= atom.source.length else { return nil }
        return NSRange(location: atom.source.location + startOffset, length: overlap.length)
    }

    private static func mergeContiguous(_ ranges: [NSRange]) -> NSRange? {
        guard var merged = ranges.first else { return nil }
        for range in ranges.dropFirst() {
            if range.location == NSMaxRange(merged) {
                merged = NSRange(location: merged.location, length: merged.length + range.length)
            } else if NSMaxRange(range) == merged.location {
                merged = NSRange(location: range.location, length: merged.length + range.length)
            } else if NSEqualRanges(range, merged) {
                continue
            } else {
                return nil
            }
        }
        return merged
    }
}
