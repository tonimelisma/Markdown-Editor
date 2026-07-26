//
//  SourceCoordinateMap.swift
//  Markdown Editor
//

import Foundation

/// Exact UTF-8 / UTF-16 / String.Index conversions for one source revision.
///
/// // REQ-054/055/087: wraps `MarkdownSourceIndex`; never clamps.
nonisolated struct SourceCoordinateMap: Sendable {
    let index: MarkdownSourceIndex

    var source: String { index.source }
    var sourceVersion: UInt64 { index.sourceVersion }

    init(source: String, sourceVersion: UInt64) {
        self.index = MarkdownSourceIndex(source: source, sourceVersion: sourceVersion)
    }

    init(index: MarkdownSourceIndex) {
        self.index = index
    }

    /// Inclusive cmark `SourcePosition` → exclusive UTF-16 `NSRange`.
    func utf16Range(for position: SourcePosition) -> Result<NSRange, SourceMappingFailure> {
        index.utf16Range(for: position)
    }

    func substring(position: SourcePosition) -> Result<String, SourceMappingFailure> {
        index.substring(position: position)
    }

    func substring(utf16 range: NSRange) -> Result<String, SourceMappingFailure> {
        index.substring(utf16: range)
    }
}
