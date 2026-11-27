//
//  EmptyParagraphLayout.swift
//  Markdown Editor
//

import Foundation

/// Where the empty paragraphs between top-level blocks are, and where typing in each writes.
///
/// An empty paragraph is a pair of extra blank lines in the source. WYSIWYG had no way to show
/// one, so Return could not start a new paragraph (agent-drive tour 45957180019). The projection
/// compiler shows each as a line break, and Backspace's planner reads the same layout to know
/// when the caret stands in one.
///
/// Counting, with `blank` the blank lines in a gap: between two blocks `blank / 2`, since one blank
/// line only separates them; before the first block or after the last `(blank + 1) / 2`; in a
/// document with no block at all `blank / 2`, since its first line is the caret's own. Return
/// writes two line breaks, which adds exactly one.
///
/// Each slot's insertion point is chosen so that typing in it writes exactly one new paragraph:
/// the start of its middle blank line, or the end of the file. In a document with no block, a
/// slot is the line between two insertion points, the one before it and the one after it.
nonisolated enum EmptyParagraphLayout {
    nonisolated struct Slot: Equatable, Sendable {
        /// Where a caret before the slot's line break writes.
        let before: Int
        /// Where a caret after it writes; equal to `before` except in a document with no block.
        let after: Int
    }

    /// The slots in the gap after the block ending at `previousEnd` (nil before the first) and
    /// before the block starting at `nextStart` (nil after the last).
    static func slots(in source: NSString, previousEnd: Int?, nextStart: Int?) -> [Slot] {
        let from = min(max(previousEnd ?? 0, 0), source.length)
        let to = min(max(nextStart ?? source.length, from), source.length)
        var newlines: [Int] = []
        // A block's source range may or may not include the line break that ends it; the gap's
        // first line break is that one either way.
        if let previousEnd, previousEnd > 0, previousEnd <= source.length, source.character(at: previousEnd - 1) == 0x0A {
            newlines.append(previousEnd - 1)
        }
        for index in from..<to where source.character(at: index) == 0x0A { newlines.append(index) }

        // Where blank line `i` of the gap starts. After a block, its first line break ends that
        // block's last line, so blank line i follows line break i; before the first block,
        // blank line 0 starts the file and blank line i follows line break i - 1.
        let blank: Int
        let blankLineStart: (Int) -> Int
        if previousEnd == nil {
            blank = newlines.count
            blankLineStart = { $0 == 0 ? from : newlines[$0 - 1] + 1 }
        } else {
            blank = max(0, newlines.count - 1)
            blankLineStart = { newlines[$0] + 1 }
        }

        if previousEnd == nil, nextStart == nil {
            let count = blank / 2
            return (0..<count).map { j in
                let before = blankLineStart(2 * j)
                let after = 2 * j + 2 < blank ? blankLineStart(2 * j + 2) : to
                return Slot(before: before, after: after)
            }
        }
        let count = (previousEnd != nil && nextStart != nil) ? blank / 2 : (blank + 1) / 2
        return (0..<count).map { j in
            let line = previousEnd == nil ? 2 * j : 2 * j + 1
            let location = line < blank ? min(blankLineStart(line), to) : to
            return Slot(before: location, after: location)
        }
    }
}
