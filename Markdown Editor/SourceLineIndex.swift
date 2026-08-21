//
//  SourceLineIndex.swift
//  Markdown Editor
//

import Foundation

/// Immutable UTF-16 line boundaries for one source snapshot.
///
/// // REQ-040/045; ARC-020: CRLF is one line terminator while all ranges remain UTF-16 exact.
nonisolated struct SourceLineIndex: Sendable, Equatable {
    let sourceUTF16Count: Int
    let lines: [NSRange]

    init(source: String) {
        let ns = source as NSString
        sourceUTF16Count = ns.length
        var result: [NSRange] = []
        var start = 0
        while start < ns.length {
            var end = start
            while end < ns.length {
                let character = ns.character(at: end)
                if character == 0x0A {
                    end += 1
                    break
                }
                if character == 0x0D {
                    end += 1
                    if end < ns.length, ns.character(at: end) == 0x0A { end += 1 }
                    break
                }
                end += 1
            }
            result.append(NSRange(location: start, length: end - start))
            start = end
        }
        if ns.length == 0 { result = [] }
        lines = result
    }

    /// Updates the cached topology without rescanning the document for the ordinary edit case.
    /// The fast path is intentionally conservative: it handles edits contained by one existing
    /// line whose suffix is unchanged, and falls back to a complete topology build for newline
    /// edits or any ambiguous replacement.
    static func updating(
        source: String,
        previousSource: String,
        previous: SourceLineIndex,
        editedRange: NSRange?
    ) -> SourceLineIndex {
        guard let editedRange,
              !previous.lines.isEmpty,
              !source.isEmpty,
              editedRange.location >= 0,
              NSMaxRange(editedRange) <= (source as NSString).length else {
            return SourceLineIndex(source: source)
        }

        let oldNSString = previousSource as NSString
        let newNSString = source as NSString

        let line = previous.lineContaining(editedRange.location)
        let oldRange = previous.lines[line]
        guard editedRange.location >= oldRange.location else { return SourceLineIndex(source: source) }
        let newRange = lineRange(in: newNSString, startingAt: oldRange.location)
        guard newRange.location == oldRange.location,
              oldNSString.substring(from: NSMaxRange(oldRange)) == newNSString.substring(from: NSMaxRange(newRange)) else {
            return SourceLineIndex(source: source)
        }

        let delta = newRange.length - oldRange.length
        var lines = Array(previous.lines.prefix(line))
        lines.append(newRange)
        lines.append(contentsOf: previous.lines.dropFirst(line + 1).map {
            NSRange(location: $0.location + delta, length: $0.length)
        })
        return SourceLineIndex(sourceUTF16Count: newNSString.length, lines: lines)
    }

    private init(sourceUTF16Count: Int, lines: [NSRange]) {
        self.sourceUTF16Count = sourceUTF16Count
        self.lines = lines
    }

    private static func lineRange(in source: NSString, startingAt start: Int) -> NSRange {
        guard start < source.length else { return NSRange(location: start, length: 0) }
        var end = start
        while end < source.length {
            let character = source.character(at: end)
            if character == 0x0A {
                end += 1
                break
            }
            if character == 0x0D {
                end += 1
                if end < source.length, source.character(at: end) == 0x0A { end += 1 }
                break
            }
            end += 1
        }
        return NSRange(location: start, length: end - start)
    }

    func lineContaining(_ location: Int) -> Int {
        guard !lines.isEmpty else { return 0 }
        let clamped = min(max(location, 0), sourceUTF16Count)
        var low = 0
        var high = lines.count
        while low < high {
            let middle = (low + high) / 2
            if NSMaxRange(lines[middle]) <= clamped {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return min(low, lines.count - 1)
    }

    func affectedLine(for editedRange: NSRange) -> Int {
        lineContaining(editedRange.location)
    }
}
