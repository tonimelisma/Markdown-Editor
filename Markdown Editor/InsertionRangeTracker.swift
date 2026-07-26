//
//  InsertionRangeTracker.swift
//  Markdown Editor
//

import Foundation

// REQ-072: track a planned insertion range across intervening edits; cancel on overlap.
// Explicit source-range boundary policy for asynchronous image placement.
nonisolated struct InsertionRangeTracker: Sendable {
    private(set) var range: NSRange
    private(set) var isCancelled = false

    init(range: NSRange) {
        let loc = max(0, range.location)
        let len = max(0, range.length)
        self.range = NSRange(location: loc, length: len)
    }

    /// Apply an edit that replaced `edited` with content whose UTF-16 length delta is `delta`
    /// (replacementLength − edited.length).
    mutating func applyEdit(edited: NSRange, changeInLength delta: Int) {
        guard !isCancelled else { return }
        let editStart = max(0, edited.location)
        let editLength = max(0, edited.length)
        let editEnd = editStart + editLength
        let trackStart = range.location
        let trackEnd = range.location + range.length
        let isZeroLengthTrack = range.length == 0

        // Insertion (zero-length edit) exactly at a zero-length caret → cancel.
        if isZeroLengthTrack && editLength == 0 && editStart == trackStart {
            isCancelled = true
            return
        }

        // Insertion at the start of a non-empty tracked range → cancel.
        if !isZeroLengthTrack && editLength == 0 && editStart == trackStart {
            isCancelled = true
            return
        }

        // Insertion strictly inside a non-empty range → cancel.
        if !isZeroLengthTrack && editLength == 0 && editStart > trackStart && editStart < trackEnd {
            isCancelled = true
            return
        }

        // Replacement/deletion with non-empty intersection → cancel.
        // Intervals [editStart, editEnd) and [trackStart, trackEnd) intersect.
        if editLength > 0 {
            let intersects: Bool
            if isZeroLengthTrack {
                // Zero-length track: intersects if edit covers the caret point.
                intersects = editStart < trackEnd && editEnd > trackStart
                    || (editStart <= trackStart && editEnd > trackStart)
            } else {
                intersects = editStart < trackEnd && editEnd > trackStart
            }
            if intersects {
                isCancelled = true
                return
            }
        }

        // Edit entirely after tracked range (including insertion at non-empty end): no change.
        if editStart >= trackEnd {
            return
        }

        // Edit entirely before: shift.
        if editEnd <= trackStart {
            let newLoc = range.location + delta
            range.location = max(0, newLoc)
            return
        }

        // Any remaining ambiguous case cancels.
        isCancelled = true
    }
}
