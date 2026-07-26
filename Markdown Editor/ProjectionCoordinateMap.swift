//
//  ProjectionCoordinateMap.swift
//  Markdown Editor
//

import Foundation

/// Maps between WYSIWYG projection selections and canonical source selections.
///
/// // REQ-056/087: affinity at boundaries; typed refusal — never clamp or proportion.
/// // REQ-084: synthetic endpoints follow `SyntheticInsertionPolicy` (COR-08).
nonisolated struct ProjectionCoordinateMap: Sendable {
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
        sourceRange(forProjection: selection.nsRange, affinity: selection.affinity)
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

    // MARK: - Non-empty selection (COR-08 synthetic endpoint policy)

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

        // Synthetic-only selections must not invent a source span (COR-08 / REQ-087).
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
        if location == projectionUTF16Count {
            if let last = segments.last {
                return .exact(NSRange(location: last.insertionAfter, length: 0))
            }
            return .exact(NSRange(location: 0, length: 0))
        }

        for segment in segments {
            let range = segment.projectionRange
            if location == range.location {
                if affinity == .upstream, let before = segmentBefore(segment) {
                    return .exact(NSRange(location: before.insertionAfter, length: 0))
                }
                return .exact(NSRange(location: segment.insertionBefore, length: 0))
            }
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
            if location == NSMaxRange(range) {
                return .exact(NSRange(location: segment.insertionAfter, length: 0))
            }
        }
        return .refused(.ambiguous)
    }

    private func projectionInsertionPoint(forSource location: Int, affinity: SelectionAffinity) -> CoordinateMappingResult {
        for segment in segments {
            switch segment {
            case .source(let projection, let source, _, _):
                if location == source.location {
                    return .exact(NSRange(location: projection.location, length: 0))
                }
                if location > source.location && location < NSMaxRange(source),
                   projection.length == source.length {
                    let local = location - source.location
                    return .exact(NSRange(location: projection.location + local, length: 0))
                }
                if location == NSMaxRange(source) {
                    return .exact(NSRange(location: NSMaxRange(projection), length: 0))
                }
            case .literalFallback(let projection, let source):
                if location == source.location {
                    return .exact(NSRange(location: projection.location, length: 0))
                }
                if location > source.location && location < NSMaxRange(source),
                   projection.length == source.length {
                    let local = location - source.location
                    return .exact(NSRange(location: projection.location + local, length: 0))
                }
                if location == NSMaxRange(source) {
                    return .exact(NSRange(location: NSMaxRange(projection), length: 0))
                }
            case .synthetic(let projection, _, let insertion):
                switch insertion {
                case .atSourceLocation(let loc) where loc == location:
                    return .exact(NSRange(location: projection.location, length: 0))
                case .atSourceBoundaries(let before, let after):
                    if before == location {
                        return .exact(NSRange(location: projection.location, length: 0))
                    }
                    if after == location {
                        return .exact(NSRange(location: NSMaxRange(projection), length: 0))
                    }
                default:
                    break
                }
            case .uneditable:
                continue
            }
        }
        _ = affinity
        return .refused(.ambiguous)
    }

    private func segmentBefore(_ segment: ProjectionSegment) -> ProjectionSegment? {
        let loc = segment.projectionRange.location
        return segments.last { NSMaxRange($0.projectionRange) == loc }
    }

    private func intersection(_ a: NSRange, _ b: NSRange) -> NSRange {
        let start = max(a.location, b.location)
        let end = min(NSMaxRange(a), NSMaxRange(b))
        if end <= start { return NSRange(location: start, length: 0) }
        return NSRange(location: start, length: end - start)
    }
}

extension ProjectionSegment {
    var projectionRange: NSRange {
        switch self {
        case .source(let projection, _, _, _),
             .synthetic(let projection, _, _),
             .literalFallback(let projection, _),
             .uneditable(let projection, _):
            return projection
        }
    }

    var insertionBefore: Int {
        switch self {
        case .source(_, _, let before, _): return before
        case .literalFallback(_, let source): return source.location
        case .synthetic(_, _, let insertion):
            switch insertion {
            case .atSourceLocation(let loc): return loc
            case .atSourceBoundaries(let before, _): return before
            case .refuse: return 0
            }
        case .uneditable: return 0
        }
    }

    var insertionAfter: Int {
        switch self {
        case .source(_, _, _, let after): return after
        case .literalFallback(_, let source): return NSMaxRange(source)
        case .synthetic(_, _, let insertion):
            switch insertion {
            case .atSourceLocation(let loc): return loc
            case .atSourceBoundaries(_, let after): return after
            case .refuse: return 0
            }
        case .uneditable: return 0
        }
    }
}
