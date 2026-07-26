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
}
