//
//  ProjectionOracle.swift
//  Markdown Editor
//

import Foundation

/// Invariant checks for a compiled projection.
///
/// // REQ-054–056/087/089: numeric failures only — never logs source text.
nonisolated enum ProjectionOracle {
    struct Failure: Error, Sendable, Equatable {
        let code: String
        let detail: String
    }

    static func validate(
        model: MarkdownProjectionModel,
        sourceUTF16Count: Int
    ) -> Result<Void, Failure> {
        let renderedCount = (model.renderedString as NSString).length
        var covered = Array(repeating: 0, count: max(renderedCount, 0))

        for segment in model.segments {
            let range: NSRange
            switch segment {
            case .source(let projection, let source, _, _):
                range = projection
                guard source.location >= 0, NSMaxRange(source) <= sourceUTF16Count else {
                    return .failure(Failure(code: "source_oob", detail: "loc=\(source.location) len=\(source.length)"))
                }
                guard source.length >= 0 else {
                    return .failure(Failure(code: "source_neg", detail: "len=\(source.length)"))
                }
            case .literalFallback(let projection, let source):
                range = projection
                guard source.location >= 0, NSMaxRange(source) <= sourceUTF16Count else {
                    return .failure(Failure(code: "fallback_oob", detail: "loc=\(source.location)"))
                }
            case .synthetic(let projection, _, _):
                range = projection
            case .uneditable(let projection, _):
                range = projection
            }
            guard range.location >= 0, NSMaxRange(range) <= renderedCount else {
                return .failure(Failure(code: "proj_oob", detail: "loc=\(range.location) len=\(range.length)"))
            }
            for i in 0..<range.length {
                let idx = range.location + i
                covered[idx] += 1
                if covered[idx] > 1 {
                    return .failure(Failure(code: "overlap", detail: "idx=\(idx)"))
                }
            }
        }

        if let gap = covered.firstIndex(where: { $0 == 0 }), renderedCount > 0 {
            return .failure(Failure(code: "gap", detail: "idx=\(gap)"))
        }

        // Round-trip a few caret positions.
        let map = model.coordinateMap
        for loc in [0, renderedCount / 2, max(renderedCount - 1, 0), renderedCount] where loc <= renderedCount {
            switch map.sourceRange(forProjection: NSRange(location: loc, length: 0)) {
            case .exact(let sourceCaret):
                switch map.projectionRange(forSource: sourceCaret) {
                case .exact, .refused:
                    break
                }
            case .refused:
                break
            }
        }
        return .success(())
    }
}
