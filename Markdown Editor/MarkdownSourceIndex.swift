//
//  MarkdownSourceIndex.swift
//  Markdown Editor
//

import Foundation

/// Typed failure when a source boundary cannot be mapped exactly.
///
/// // REQ-055/087: invalid boundaries produce typed failures — never clamp or guess.
nonisolated enum SourceMappingFailure: Error, Sendable, Equatable {
    case unknownPosition
    case outOfBoundsLine(Int)
    case outOfBoundsColumn(line: Int, column: Int)
    case invalidUTF8Boundary
    case invalidUTF16Range
    case projectionOutOfBounds
}

/// Absolute UTF-8 byte range within source (end exclusive).
nonisolated struct UTF8Range: Sendable, Equatable {
    let start: Int
    let end: Int

    var length: Int { end - start }
    var isEmpty: Bool { start == end }
}

/// Maps cmark UTF-8 line/byte columns ↔ Swift String.Index ↔ UTF-16 NSRange ↔ projection.
///
/// // REQ-054/055/085/087: built once per source version; all conversions bounds-checked.
nonisolated struct MarkdownSourceIndex: Sendable {
    let source: String
    let sourceVersion: UInt64

    /// UTF-8 byte offset of the first byte of each 1-based line (index 0 unused).
    private let lineStartUTF8: [Int]
    private let utf8Count: Int
    private let utf16Count: Int

    init(source: String, sourceVersion: UInt64) {
        self.source = source
        self.sourceVersion = sourceVersion
        self.utf16Count = (source as NSString).length

        let utf8 = Array(source.utf8)
        self.utf8Count = utf8.count

        var starts: [Int] = [0, 0] // 1-based: line 1 starts at 0
        var i = 0
        while i < utf8.count {
            if utf8[i] == 0x0A { // LF
                starts.append(i + 1)
                i += 1
            } else if utf8[i] == 0x0D { // CR
                if i + 1 < utf8.count && utf8[i + 1] == 0x0A {
                    starts.append(i + 2)
                    i += 2
                } else {
                    starts.append(i + 1)
                    i += 1
                }
            } else {
                i += 1
            }
        }
        self.lineStartUTF8 = starts
    }

    var lineCount: Int { max(lineStartUTF8.count - 1, 1) }

    // MARK: - Position → absolute UTF-8

    /// Convert a one-based line/column (UTF-8 byte column) to an absolute UTF-8 offset.
    func utf8Offset(line: Int, column: Int) -> Result<Int, SourceMappingFailure> {
        guard line > 0 else { return .failure(.outOfBoundsLine(line)) }
        guard line < lineStartUTF8.count || (line == lineStartUTF8.count && column == 1 && utf8Count == 0) else {
            // Allow end-of-document: line == lastLine && column past last content handled below.
            if line >= lineStartUTF8.count {
                // Virtual EOF line after final newline is represented as last start + empty.
                if line == lineStartUTF8.count && column == 1 {
                    return .success(utf8Count)
                }
                return .failure(.outOfBoundsLine(line))
            }
            return .failure(.outOfBoundsLine(line))
        }

        let lineStart = lineStartUTF8[line]
        let lineEnd: Int
        if line + 1 < lineStartUTF8.count {
            lineEnd = lineStartUTF8[line + 1]
        } else {
            lineEnd = utf8Count
        }
        // cmark columns are 1-based UTF-8 byte offsets into the line (including the first byte).
        // A node whose content ends exactly at a line boundary — a loose list item followed by a
        // blank line, for example — is reported with end_line = the next line and end_column = 0.
        // That means "the end of the previous line's content", which is this line's first byte.
        if column == 0 {
            guard lineStart <= lineEnd, lineStart <= utf8Count else {
                return .failure(.outOfBoundsColumn(line: line, column: column))
            }
            return .success(lineStart)
        }
        guard column >= 1 else { return .failure(.outOfBoundsColumn(line: line, column: column)) }
        let offset = lineStart + (column - 1)
        // End positions may point one past the last byte of the span (exclusive-ish);
        // allow offset == lineEnd when referring to the exclusive end.
        guard offset <= lineEnd, offset <= utf8Count else {
            return .failure(.outOfBoundsColumn(line: line, column: column))
        }
        return .success(offset)
    }

    func utf8Range(for position: SourcePosition) -> Result<UTF8Range, SourceMappingFailure> {
        guard position.isKnown else { return .failure(.unknownPosition) }
        let start = utf8Offset(line: position.startLine, column: position.startColumn)
        let end = utf8Offset(line: position.endLine, column: position.endColumn)
        switch (start, end) {
        case (.success(let s), .success(let e)):
            // cmark end columns are inclusive of the last byte.
            // Equal start/end column means a one-column (one UTF-8 byte) span when
            // that byte exists — not an empty range. Truly empty nodes usually lack
            // known positions (handled above) or sit at EOF.
            if position.startLine == position.endLine && position.startColumn == position.endColumn {
                if s < utf8Count {
                    return .success(UTF8Range(start: s, end: min(s + 1, utf8Count)))
                }
                return .success(UTF8Range(start: s, end: s))
            }
            guard s <= e else { return .failure(.invalidUTF8Boundary) }
            let exclusiveEnd = min(e + 1, utf8Count)
            guard s <= exclusiveEnd else { return .failure(.invalidUTF8Boundary) }
            return .success(UTF8Range(start: s, end: exclusiveEnd))
        case (.failure(let err), _):
            return .failure(err)
        case (_, .failure(let err)):
            return .failure(err)
        }
    }

    // MARK: - UTF-8 ↔ String.Index / UTF-16

    func stringIndex(utf8Offset: Int) -> Result<String.Index, SourceMappingFailure> {
        guard utf8Offset >= 0, utf8Offset <= utf8Count else {
            return .failure(.invalidUTF8Boundary)
        }
        // Use UTF8View indexing for exact byte boundaries.
        let utf8View = source.utf8
        guard let utf8Index = utf8View.index(utf8View.startIndex, offsetBy: utf8Offset, limitedBy: utf8View.endIndex) else {
            return .failure(.invalidUTF8Boundary)
        }
        // Must land on a Character boundary (Scalar/Character).
        guard let stringIndex = utf8Index.samePosition(in: source) else {
            return .failure(.invalidUTF8Boundary)
        }
        return .success(stringIndex)
    }

    func utf16Range(for utf8: UTF8Range) -> Result<NSRange, SourceMappingFailure> {
        switch (stringIndex(utf8Offset: utf8.start), stringIndex(utf8Offset: utf8.end)) {
        case (.success(let start), .success(let end)):
            let lower = source.utf16.distance(from: source.utf16.startIndex, to: start.samePosition(in: source.utf16)!)
            let upper = source.utf16.distance(from: source.utf16.startIndex, to: end.samePosition(in: source.utf16)!)
            let range = NSRange(location: lower, length: upper - lower)
            guard range.location >= 0, NSMaxRange(range) <= utf16Count else {
                return .failure(.invalidUTF16Range)
            }
            return .success(range)
        case (.failure(let err), _):
            return .failure(err)
        case (_, .failure(let err)):
            return .failure(err)
        }
    }

    func utf16Range(for position: SourcePosition) -> Result<NSRange, SourceMappingFailure> {
        switch utf8Range(for: position) {
        case .success(let utf8):
            return utf16Range(for: utf8)
        case .failure(let err):
            return .failure(err)
        }
    }

    func substring(utf8: UTF8Range) -> Result<String, SourceMappingFailure> {
        switch (stringIndex(utf8Offset: utf8.start), stringIndex(utf8Offset: utf8.end)) {
        case (.success(let start), .success(let end)):
            return .success(String(source[start..<end]))
        case (.failure(let err), _):
            return .failure(err)
        case (_, .failure(let err)):
            return .failure(err)
        }
    }

    func substring(position: SourcePosition) -> Result<String, SourceMappingFailure> {
        switch utf8Range(for: position) {
        case .success(let utf8):
            return substring(utf8: utf8)
        case .failure(let err):
            return .failure(err)
        }
    }

    /// Slice corresponding to an exact UTF-16 NSRange.
    func substring(utf16 range: NSRange) -> Result<String, SourceMappingFailure> {
        guard range.location >= 0, range.length >= 0, NSMaxRange(range) <= utf16Count else {
            return .failure(.invalidUTF16Range)
        }
        return .success((source as NSString).substring(with: range))
    }
}
