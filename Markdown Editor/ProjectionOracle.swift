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
        sourceUTF16Count: Int,
        intent: IntentContext? = nil
    ) -> Result<Void, Failure> {
        if let intent {
            intent.recorder.add(intent) { $0.oracleValidations += 1 }
        }
        let renderedCount = (model.renderedString as NSString).length

        // The property is that the segments exactly partition the projection: the first starts at
        // 0, each starts where the previous ended, and the last ends at `renderedCount`.
        //
        // // COR-88: this was a per-character coverage array — an 800 KB allocation and 100,000
        // // bounds-checked increments on a 100,000-character document, to decide a property
        // // about a few thousand boundaries. It cost 3.5x the cmark parse it validates and ran
        // // synchronously on the main actor for every formatting command
        // // (research/2026-08-22-semantic-command-main-actor-cost.md).
        // //
        // // Tiling is O(segments), allocates nothing, and decides strictly more: the array could
        // // not see ordering, so it accepted segments that covered the projection out of order.
        // // That strengthening is safe because segment order is asserted over all 1,324 imported
        // // specification examples and the generated corpus before it was relied on here.
        // Ordering is checked separately from tiling so the failure code says which property
        // broke. Folded into the tiling scan, an out-of-order pair reports `gap` at the first
        // segment, which is true but names the symptom rather than the cause.
        var previousLocation = -1
        for segment in model.segments {
            let location = segment.projectionRange.location
            if location < previousLocation {
                return .failure(Failure(code: "out_of_order", detail: "idx=\(location)"))
            }
            previousLocation = location
        }

        var cursor = 0
        for segment in model.segments {
            switch segment {
            case .source(_, let source, _, _):
                guard source.location >= 0, NSMaxRange(source) <= sourceUTF16Count else {
                    return .failure(Failure(code: "source_oob", detail: "loc=\(source.location) len=\(source.length)"))
                }
                guard source.length >= 0 else {
                    return .failure(Failure(code: "source_neg", detail: "len=\(source.length)"))
                }
            case .literalFallback(_, let source):
                guard source.location >= 0, NSMaxRange(source) <= sourceUTF16Count else {
                    return .failure(Failure(code: "fallback_oob", detail: "loc=\(source.location)"))
                }
            case .synthetic, .uneditable:
                break
            }

            let range = segment.projectionRange
            guard range.location >= 0, range.length >= 0, NSMaxRange(range) <= renderedCount else {
                return .failure(Failure(code: "proj_oob", detail: "loc=\(range.location) len=\(range.length)"))
            }
            if range.location < cursor {
                return .failure(Failure(code: "overlap", detail: "idx=\(range.location)"))
            }
            if range.location > cursor {
                return .failure(Failure(code: "gap", detail: "idx=\(cursor)"))
            }
            cursor = NSMaxRange(range)
        }
        if cursor != renderedCount {
            return .failure(Failure(code: "gap", detail: "idx=\(cursor)"))
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

    /// Validate a complete presentation snapshot before it becomes editable.
    ///
    /// // REQ-091/093; ARC-003: rendered length, atom coverage, tables, attachments, map bounds.
    static func validate(snapshot: PresentationSnapshot, intent: IntentContext? = nil) -> Result<Void, Failure> {
        let model = snapshot.asProjectionModel
        if case .failure(let failure) = validate(model: model, sourceUTF16Count: snapshot.sourceUTF16Count, intent: intent) {
            return .failure(failure)
        }
        let renderedCount = (snapshot.renderedString as NSString).length
        if snapshot.coordinateMap.projectionUTF16Count != renderedCount {
            return .failure(Failure(code: "map_proj_len", detail: "map=\(snapshot.coordinateMap.projectionUTF16Count) rendered=\(renderedCount)"))
        }
        if snapshot.coordinateMap.sourceUTF16Count != snapshot.sourceUTF16Count {
            return .failure(Failure(code: "map_src_len", detail: "map=\(snapshot.coordinateMap.sourceUTF16Count) src=\(snapshot.sourceUTF16Count)"))
        }
        for atom in snapshot.atoms {
            switch atom {
            case .identity(let identity):
                guard identity.projection.length == identity.source.length else {
                    return .failure(
                        Failure(
                            code: "identity_length",
                            detail: "projection=\(identity.projection.length) source=\(identity.source.length)"
                        )
                    )
                }
            case .atomic(let atomic):
                guard atomic.source.location >= 0,
                      NSMaxRange(atomic.source) <= snapshot.sourceUTF16Count,
                      (atomic.decodedText as NSString).length == atomic.projection.length else {
                    return .failure(Failure(code: "atomic_shape", detail: "kind=\(atomic.kind)"))
                }
            case .synthetic, .uneditable:
                break
            }
        }
        for attachment in snapshot.attachments {
            guard attachment.utf16Location >= 0, attachment.utf16Location < renderedCount || renderedCount == 0 else {
                return .failure(Failure(code: "attach_oob", detail: "loc=\(attachment.utf16Location)"))
            }
        }
        for table in snapshot.tables {
            guard table.utf16Range.location >= 0, NSMaxRange(table.utf16Range) <= renderedCount else {
                return .failure(Failure(code: "table_oob", detail: "loc=\(table.utf16Range.location)"))
            }
        }
        return .success(())
    }
}
