//
//  CompositionState.swift
//  Markdown Editor
//

import Foundation

/// Pure IME composition state for WYSIWYG.
///
/// // REQ-084: marked text stays transient until completion; stale refuses.
nonisolated struct CompositionState: Sendable, Equatable {
    var isComposing: Bool = false
    var markedRange: NSRange?
    var capturedSourceVersion: UInt64?
    var capturedSourceRange: NSRange?
    var capturedSnapshotID: PresentationSnapshot.ID?

    mutating func begin(
        sourceVersion: UInt64,
        sourceRange: NSRange,
        marked: NSRange,
        snapshotID: PresentationSnapshot.ID? = nil
    ) {
        isComposing = true
        capturedSourceVersion = sourceVersion
        capturedSourceRange = sourceRange
        markedRange = marked
        capturedSnapshotID = snapshotID
    }

    mutating func update(marked: NSRange) {
        markedRange = marked
    }

    mutating func cancel() {
        self = CompositionState()
    }

    /// Returns captured mutation coordinates when composition finishes successfully.
    mutating func complete() -> (version: UInt64, range: NSRange, snapshotID: PresentationSnapshot.ID?)? {
        defer { self = CompositionState() }
        guard isComposing,
              let version = capturedSourceVersion,
              let range = capturedSourceRange else {
            return nil
        }
        return (version, range, capturedSnapshotID)
    }

    /// Stale composition when document revision advanced during IME.
    func isStale(relativeTo currentVersion: UInt64) -> Bool {
        guard let captured = capturedSourceVersion else { return false }
        return captured != currentVersion
    }
}
