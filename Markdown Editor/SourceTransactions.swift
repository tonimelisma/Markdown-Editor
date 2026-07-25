//
//  SourceTransactions.swift
//  Markdown Editor
//

import Foundation

/// Immutable view of document source for adapters and background work.
///
/// // REQ-013/018: Sendable snapshot — no live document reference crosses actors.
nonisolated struct SourceSnapshot: Sendable, Equatable {
    let text: String
    let sourceVersion: UInt64
    let locationGeneration: UInt64
    let fileURL: URL?
}

/// Exact UTF-16 replacement against an expected source version.
///
/// // REQ-016: adapters submit versioned exact-range edits.
nonisolated struct SourceEdit: Sendable, Equatable {
    let expectedVersion: UInt64
    let range: NSRange
    let replacement: String
    let actionName: String
}

/// Why a source edit was refused without mutation.
nonisolated enum SourceEditRefusal: Error, Sendable, Equatable {
    case staleVersion
    case invalidRange
    case conflict
}

/// UTF-16 selection to apply after a committed edit.
nonisolated struct SourceSelection: Sendable, Equatable {
    let range: NSRange
}

nonisolated enum SourceEditResult: Sendable, Equatable {
    case committed(SourceSelection)
    case refused(SourceEditRefusal)
}
