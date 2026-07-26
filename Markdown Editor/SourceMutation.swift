//
//  SourceMutation.swift
//  Markdown Editor
//

import Foundation

/// How a mutation participates in undo grouping.
///
/// // REQ-016: typing coalesces; toolbar/task/image actions remain discrete.
nonisolated enum MutationGrouping: Sendable, Equatable {
    /// Adjacent typing commits share one open undo group until a discrete action closes it.
    case typing
    /// One undo step per commit (toolbar, task, image, paste, programmatic).
    case discrete
}

/// Content-validated canonical source mutation.
///
/// // REQ-016: revision + range + expected content must match before commit.
nonisolated struct SourceMutation: Sendable, Equatable {
    let id: UUID
    let expectedRevision: UInt64
    let range: NSRange
    let expectedText: String
    let replacement: String
    let selectionBefore: SourceSelection
    let selectionAfter: SourceSelection
    let actionName: String
    let grouping: MutationGrouping

    init(
        id: UUID = UUID(),
        expectedRevision: UInt64,
        range: NSRange,
        expectedText: String,
        replacement: String,
        selectionBefore: SourceSelection,
        selectionAfter: SourceSelection,
        actionName: String,
        grouping: MutationGrouping
    ) {
        self.id = id
        self.expectedRevision = expectedRevision
        self.range = range
        self.expectedText = expectedText
        self.replacement = replacement
        self.selectionBefore = selectionBefore
        self.selectionAfter = selectionAfter
        self.actionName = actionName
        self.grouping = grouping
    }

    /// Builds a mutation from an exact source range and replacement.
    static func exact(
        snapshot: SourceSnapshot,
        range: NSRange,
        replacement: String,
        selectionBefore: SourceSelection,
        selectionAfter: SourceSelection? = nil,
        actionName: String,
        grouping: MutationGrouping
    ) -> SourceMutation? {
        let ns = snapshot.text as NSString
        guard range.location >= 0, range.length >= 0, NSMaxRange(range) <= ns.length else {
            return nil
        }
        let expectedText = ns.substring(with: range)
        let after = selectionAfter ?? SourceSelection(
            utf16: NSRange(location: range.location + (replacement as NSString).length, length: 0),
            affinity: selectionBefore.affinity
        )
        return SourceMutation(
            expectedRevision: snapshot.sourceVersion,
            range: range,
            expectedText: expectedText,
            replacement: replacement,
            selectionBefore: selectionBefore,
            selectionAfter: after,
            actionName: actionName,
            grouping: grouping
        )
    }
}
