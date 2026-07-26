//
//  HistoryPatch.swift
//  Markdown Editor
//

import Foundation

/// Dynamic undo/redo unit: content-validated, revision-free.
///
/// // REQ-011/016: validates affected content before apply; inverse from what committed;
/// // never stores an expected historical document revision.
nonisolated struct HistoryPatch: Sendable, Equatable {
    /// UTF-16 range of `after` in the document immediately after the forward mutation.
    let range: NSRange
    /// Source text that was replaced by the forward mutation.
    let before: String
    /// Source text written by the forward mutation (must match current range content to undo).
    let after: String
    let selectionBefore: SourceSelection
    let selectionAfter: SourceSelection
    let actionName: String

    /// Builds the patch that reverses this one (undo ↔ redo).
    func inverse() -> HistoryPatch {
        let restoredLength = (before as NSString).length
        return HistoryPatch(
            range: NSRange(location: range.location, length: restoredLength),
            before: after,
            after: before,
            selectionBefore: selectionAfter,
            selectionAfter: selectionBefore,
            actionName: actionName
        )
    }

    /// Creates a forward history patch from a mutation that just committed.
    static func fromCommitted(_ mutation: SourceMutation) -> HistoryPatch {
        let afterLength = (mutation.replacement as NSString).length
        return HistoryPatch(
            range: NSRange(location: mutation.range.location, length: afterLength),
            before: mutation.expectedText,
            after: mutation.replacement,
            selectionBefore: mutation.selectionBefore,
            selectionAfter: mutation.selectionAfter,
            actionName: mutation.actionName
        )
    }

    /// Returns whether `documentText` currently holds `after` at `range`.
    func matchesCurrentContent(in documentText: String) -> Bool {
        let ns = documentText as NSString
        guard range.location >= 0,
              range.length >= 0,
              NSMaxRange(range) <= ns.length else {
            return false
        }
        return ns.substring(with: range) == after
    }
}
