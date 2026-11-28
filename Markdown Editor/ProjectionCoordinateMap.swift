//
//  ProjectionCoordinateMap.swift
//  Markdown Editor
//

import Foundation

/// Maps between WYSIWYG projection selections and canonical source selections.
///
/// // REQ-056/087: affinity at boundaries; typed refusal — never clamp or proportion.
/// // REQ-084: synthetic endpoints follow `SyntheticInsertionPolicy`.
nonisolated struct ProjectionCoordinateMap: Sendable, Equatable {
    let segments: [ProjectionSegment]
    let projectionUTF16Count: Int
    let sourceUTF16Count: Int

    func sourceRange(
        forProjection selection: NSRange,
        affinity: SelectionAffinity = .downstream
    ) -> CoordinateMappingResult {
        guard selection.location >= 0,
              selection.length >= 0,
              NSMaxRange(selection) <= projectionUTF16Count else {
            return .refused(.outOfBounds)
        }

        if selection.length == 0 {
            return sourceInsertionPoint(at: selection.location, affinity: affinity)
        }

        return mapNonEmptySelection(selection, affinity: affinity)
    }

    func sourceRange(
        forProjection selection: ProjectionSelection
    ) -> CoordinateMappingResult {
        sourceRange(forProjection: selection.range.utf16, affinity: selection.affinity)
    }

    func projectionRange(
        forSource selection: NSRange,
        affinity: SelectionAffinity = .downstream
    ) -> CoordinateMappingResult {
        guard selection.location >= 0,
              selection.length >= 0,
              NSMaxRange(selection) <= sourceUTF16Count else {
            return .refused(.outOfBounds)
        }

        var projStart: Int?
        var projEnd: Int?

        for segment in segments {
            switch segment {
            case .source(let projection, let source, _, _),
                 .literalFallback(let projection, let source):
                let overlap = intersection(selection, source)
                guard overlap.length > 0 else { continue }
                if projection.length == source.length {
                    let local = overlap.location - source.location
                    let mappedStart = projection.location + local
                    let mappedEnd = mappedStart + overlap.length
                    projStart = min(projStart ?? mappedStart, mappedStart)
                    projEnd = max(projEnd ?? mappedEnd, mappedEnd)
                } else if overlap == source {
                    projStart = min(projStart ?? projection.location, projection.location)
                    projEnd = max(projEnd ?? NSMaxRange(projection), NSMaxRange(projection))
                } else {
                    return .refused(.ambiguous)
                }
            case .synthetic, .uneditable:
                continue
            }
        }

        guard let start = projStart, let end = projEnd, start <= end else {
            if selection.length == 0 {
                return projectionInsertionPoint(forSource: selection.location, affinity: affinity)
            }
            return .refused(.ambiguous)
        }
        return .exact(NSRange(location: start, length: end - start))
    }

    // MARK: - Non-empty selection

    /// Union source-backed overlaps with allowed synthetic endpoint anchors / interior bridges.
    private func mapNonEmptySelection(
        _ selection: NSRange,
        affinity: SelectionAffinity
    ) -> CoordinateMappingResult {
        var sourceStart: Int?
        var sourceEnd: Int?
        var covered = 0
        var overlappedSourceBacked = false
        let selEnd = NSMaxRange(selection)

        for segment in segments {
            let overlap = intersection(selection, segment.projectionRange)
            guard overlap.length > 0 else { continue }
            covered += overlap.length

            let touchesLeading = overlap.location == selection.location
            let touchesTrailing = NSMaxRange(overlap) == selEnd
            let isInterior = !touchesLeading && !touchesTrailing

            switch segment {
            case .source(_, let source, _, _), .literalFallback(_, let source):
                overlappedSourceBacked = true
                let local = overlap.location - segment.projectionRange.location
                let mappedStart = source.location + local
                let mappedEnd = mappedStart + overlap.length
                if segment.projectionRange.length == source.length {
                    sourceStart = min(sourceStart ?? mappedStart, mappedStart)
                    sourceEnd = max(sourceEnd ?? mappedEnd, mappedEnd)
                } else if overlap == segment.projectionRange {
                    sourceStart = min(sourceStart ?? source.location, source.location)
                    sourceEnd = max(sourceEnd ?? NSMaxRange(source), NSMaxRange(source))
                } else {
                    return .refused(.ambiguous)
                }

            case .synthetic(_, _, let insertion):
                switch insertion {
                case .refuse:
                    return .refused(.uneditableSynthetic)
                case .atSourceLocation(let loc):
                    // Endpoint anchors and interior bridges fold to the declared location.
                    if touchesLeading {
                        sourceStart = min(sourceStart ?? loc, loc)
                    }
                    if touchesTrailing {
                        sourceEnd = max(sourceEnd ?? loc, loc)
                    }
                    if isInterior {
                        // Strictly interior synthetic (e.g. paragraph break) bridges without
                        // expanding the source range beyond source-backed endpoints.
                        break
                    }
                case .atSourceBoundaries(let before, let after):
                    if touchesLeading {
                        // Leading endpoint: upstream affinity prefers the before boundary;
                        // otherwise fold to after so Select All / marker→text includes content.
                        let anchor = affinity == .upstream ? before : after
                        sourceStart = min(sourceStart ?? anchor, anchor)
                    }
                    if touchesTrailing {
                        let anchor = affinity == .upstream ? before : after
                        sourceEnd = max(sourceEnd ?? anchor, anchor)
                    }
                    if isInterior {
                        break
                    }
                }

            case .uneditable:
                return .refused(.unsupported)
            }
        }

        // Synthetic-only selections must not invent a source span (REQ-087).
        guard overlappedSourceBacked else {
            return .refused(.uneditableSynthetic)
        }

        guard covered == selection.length,
              let start = sourceStart,
              let end = sourceEnd,
              start <= end,
              end <= sourceUTF16Count else {
            return .refused(.ambiguous)
        }
        return .exact(NSRange(location: start, length: end - start))
    }

    // MARK: - Insertion points

    private func sourceInsertionPoint(at location: Int, affinity: SelectionAffinity) -> CoordinateMappingResult {
        guard location >= 0, location <= projectionUTF16Count else {
            return .refused(.outOfBounds)
        }
        guard !segments.isEmpty else {
            return location == 0
                ? .exact(NSRange(location: 0, length: 0))
                : .refused(.outOfBounds)
        }

        // Interior points are owned by the containing segment.
        for segment in segments {
            let range = segment.projectionRange
            if location > range.location && location < NSMaxRange(range) {
                switch segment {
                case .source(_, let source, _, _):
                    if range.length == source.length {
                        let local = location - range.location
                        return .exact(NSRange(location: source.location + local, length: 0))
                    }
                    return .refused(.ambiguous)
                case .literalFallback(_, let source):
                    if range.length == source.length {
                        let local = location - range.location
                        return .exact(NSRange(location: source.location + local, length: 0))
                    }
                    return .refused(.ambiguous)
                case .synthetic(_, _, let insertion):
                    switch insertion {
                    case .atSourceLocation(let loc):
                        return .exact(NSRange(location: loc, length: 0))
                    case .atSourceBoundaries(let before, let after):
                        let loc = affinity == .upstream ? before : after
                        return .exact(NSRange(location: loc, length: 0))
                    case .refuse:
                        return .refused(.uneditableSynthetic)
                    }
                case .uneditable:
                    return .refused(.unsupported)
                }
            }
        }

        // Boundary ownership follows affinity and the chosen segment's explicit policy.
        if affinity == .downstream,
           let after = segments.first(where: { $0.projectionRange.location == location }) {
            return sourceBoundary(of: after, edge: .before)
        }
        if affinity == .upstream,
           let before = segments.last(where: { NSMaxRange($0.projectionRange) == location }) {
            return sourceBoundary(of: before, edge: .after)
        }
        if let before = segments.last(where: { NSMaxRange($0.projectionRange) == location }) {
            return sourceBoundary(of: before, edge: .after)
        }
        if let after = segments.first(where: { $0.projectionRange.location == location }) {
            return sourceBoundary(of: after, edge: .before)
        }
        return .refused(.ambiguous)
    }

    private enum BoundaryEdge {
        case before
        case after
    }

    private func sourceBoundary(
        of segment: ProjectionSegment,
        edge: BoundaryEdge
    ) -> CoordinateMappingResult {
        switch segment {
        case .source(_, _, let before, let after):
            return .exact(NSRange(location: edge == .before ? before : after, length: 0))
        case .literalFallback(_, let source):
            let location = edge == .before ? source.location : NSMaxRange(source)
            return .exact(NSRange(location: location, length: 0))
        case .synthetic(_, _, let insertion):
            switch insertion {
            case .atSourceLocation(let location):
                return .exact(NSRange(location: location, length: 0))
            case .atSourceBoundaries(let before, let after):
                return .exact(
                    NSRange(location: edge == .before ? before : after, length: 0)
                )
            case .refuse:
                return .refused(.uneditableSynthetic)
            }
        case .uneditable:
            return .refused(.unsupported)
        }
    }

    /// // REQ-087; ARC-007; COR-30: affinity is honoured here, as architecture.md §4 states for
    /// // conversion in both directions. This previously ended in `_ = affinity` and returned the
    /// // first segment that happened to match in array order, so a caret sitting exactly between
    /// // two segments was resolved by iteration order rather than by the user's affinity.
    private func projectionInsertionPoint(forSource location: Int, affinity: SelectionAffinity) -> CoordinateMappingResult {
        // A boundary can be both the end of one segment and the start of the next. Collect both
        // readings, then let affinity choose: upstream keeps the caret with the preceding
        // segment, downstream with the following one.
        var trailingEdge: Int?   // this location is NSMaxRange of some segment's source
        var leadingEdge: Int?    // this location is the start of some segment's source
        var interior: Int?       // strictly inside a segment — unambiguous, wins outright

        for segment in segments {
            switch segment {
            case .source(let projection, let source, _, _),
                 .literalFallback(let projection, let source):
                if location > source.location, location < NSMaxRange(source),
                   projection.length == source.length {
                    interior = projection.location + (location - source.location)
                }
                if location == source.location, leadingEdge == nil {
                    leadingEdge = projection.location
                }
                if location == NSMaxRange(source) {
                    trailingEdge = NSMaxRange(projection)
                }
            case .synthetic(let projection, _, let insertion):
                switch insertion {
                case .atSourceLocation(let loc) where loc == location:
                    if leadingEdge == nil { leadingEdge = projection.location }
                case .atSourceBoundaries(let before, let after):
                    if before == location { trailingEdge = trailingEdge ?? projection.location }
                    if after == location, leadingEdge == nil { leadingEdge = NSMaxRange(projection) }
                default:
                    break
                }
            case .uneditable:
                continue
            }
        }

        if let interior {
            return .exact(NSRange(location: interior, length: 0))
        }
        let chosen = affinity == .upstream
            ? (trailingEdge ?? leadingEdge)
            : (leadingEdge ?? trailingEdge)
        guard let chosen else { return .refused(.ambiguous) }
        return .exact(NSRange(location: chosen, length: 0))
    }

    private func intersection(_ a: NSRange, _ b: NSRange) -> NSRange {
        let start = max(a.location, b.location)
        let end = min(NSMaxRange(a), NSMaxRange(b))
        if end <= start { return NSRange(location: start, length: 0) }
        return NSRange(location: start, length: end - start)
    }
}
