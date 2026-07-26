//
//  ProjectionCoordinateMap.swift
//  Markdown Editor
//

import Foundation

/// Maps between WYSIWYG projection selections and canonical source selections.
///
/// // REQ-056/087: affinity at boundaries; typed refusal — never clamp or proportion.
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

        var sourceStart: Int?
        var sourceEnd: Int?
        var covered = 0
        let selEnd = NSMaxRange(selection)

        // Refuse when either endpoint character lies in a synthetic segment. Bridging is only
        // for synthetics strictly between source-backed endpoints (e.g. paragraph breaks).
        if selection.length > 0 {
            if isSyntheticProjectionIndex(selection.location)
                || isSyntheticProjectionIndex(selEnd - 1) {
                return .refused(.uneditableSynthetic)
            }
        }

        for segment in segments {
            let overlap = intersection(selection, segment.projectionRange)
            guard overlap.length > 0 || (overlap.length == 0 && selection.length == 0) else { continue }
            if overlap.length == 0 { continue }
            covered += overlap.length

            switch segment {
            case .source(_, let source, _, _), .literalFallback(_, let source):
                let local = overlap.location - segment.projectionRange.location
                let mappedStart = source.location + local
                let mappedEnd = mappedStart + overlap.length
                // Only 1:1 when projection unit count equals source unit count for this segment.
                if segment.projectionRange.length == source.length {
                    sourceStart = min(sourceStart ?? mappedStart, mappedStart)
                    sourceEnd = max(sourceEnd ?? mappedEnd, mappedEnd)
                } else if overlap == segment.projectionRange {
                    // Whole-segment map when lengths differ (entities/escapes).
                    sourceStart = min(sourceStart ?? source.location, source.location)
                    sourceEnd = max(sourceEnd ?? NSMaxRange(source), NSMaxRange(source))
                } else {
                    return .refused(.ambiguous)
                }
            case .synthetic(_, _, let insertion):
                switch insertion {
                case .refuse:
                    return .refused(.uneditableSynthetic)
                case .atSourceLocation, .atSourceBoundaries:
                    // Interior bridge only — endpoints already validated as non-synthetic.
                    break
                }
            case .uneditable:
                return .refused(.unsupported)
            }
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

    // MARK: - Private

    private func isSyntheticProjectionIndex(_ index: Int) -> Bool {
        for segment in segments {
            let range = segment.projectionRange
            guard index >= range.location, index < NSMaxRange(range) else { continue }
            if case .synthetic = segment { return true }
            return false
        }
        return false
    }

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

private extension ProjectionSegment {
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
