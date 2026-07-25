//
//  InsertionRangeTracker.swift
//  Markdown Editor
//

import Foundation

// REQ-072: track a planned insertion range across intervening edits; cancel on overlap.
nonisolated struct InsertionRangeTracker: Sendable {
    private(set) var range: NSRange
    private(set) var isCancelled = false

    init(range: NSRange) {
        self.range = range
    }

    /// Apply an edit that replaced `edited` with `delta` new UTF-16 length (replacement length − edited length).
    mutating func applyEdit(edited: NSRange, changeInLength delta: Int) {
        guard !isCancelled else { return }
        let editStart = edited.location
        let editEnd = NSMaxRange(edited)
        let trackStart = range.location
        let trackEnd = NSMaxRange(range)

        // Overlap if the edited region intersects the tracked range (including touching interior).
        if editEnd > trackStart && editStart < trackEnd {
            isCancelled = true
            return
        }
        // Edit entirely after the tracked range: no change.
        if editStart >= trackEnd {
            return
        }
        // Edit entirely before: shift.
        if editEnd <= trackStart {
            range.location = max(0, range.location + delta)
        }
    }
}
