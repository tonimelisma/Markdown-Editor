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
