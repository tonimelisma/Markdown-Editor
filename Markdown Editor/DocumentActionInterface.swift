//
//  DocumentActionInterface.swift
//  Markdown Editor
//

import AppKit
import Foundation

/// Editor-neutral document surface for both editors and image placement.
///
/// // REQ-013/017/019: no controller discovers its document by walking from an NSView.
/// // REQ-087: source-only selection values — no raw projection ranges.
protocol DocumentActionInterface: AnyObject {
    @MainActor func sourceSnapshot() -> SourceSnapshot

    /// Canonical image references from the latest pinned parse result. Consumers must not
    /// reparse raw Markdown during a move/save notification.
    @MainActor var canonicalAssetReferences: CanonicalAssetReferences { get }
    @MainActor func updateCanonicalAssetReferences(_ references: CanonicalAssetReferences)

    /// Placement-range tracking owned by the document interface, not a text view.
    @MainActor func beginPlacementTracking(range: SourceRange) -> Int
    @MainActor func endPlacementTracking(_ generation: Int)
    @MainActor func trackedPlacement(for generation: Int) -> InsertionRangeTracker?
    @MainActor func noteTrackedEdit(edited: NSRange, changeInLength: Int)

    /// Content-validated mutation entry (REQ-016). Sole commit path.
    @MainActor @discardableResult
    func commitSourceMutation(_ mutation: SourceMutation) -> SourceEditResult

    /// Publish a source-domain selection restoration event to the attached editor session.
    @MainActor func requestSelectionRestoration(_ selection: SourceSelection)

    /// Operation-scoped Save (REQ-017). Does not walk the view hierarchy.
    @MainActor func saveDocument() async -> DocumentSaveOutcome

    @MainActor var documentUndoManager: UndoManager? { get }

    /// Deterministic undo-checkpoint observer teardown (REQ-015).
    @MainActor func detachUndoCheckpointObserver()

    /// Close an open typing undo group (selection / mode / discrete boundaries).
    @MainActor func closeTypingUndoGroup()
}

extension DocumentActionInterface {
    @MainActor var canonicalAssetReferences: CanonicalAssetReferences {
        CanonicalAssetReferences(values: [])
    }

    @MainActor func updateCanonicalAssetReferences(_ references: CanonicalAssetReferences) {}
}
