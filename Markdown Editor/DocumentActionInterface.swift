//
//  DocumentActionInterface.swift
//  Markdown Editor
//

import AppKit
import Foundation

/// Editor-neutral document surface for Source, future WYSIWYG, and COR-02.
///
/// // REQ-013/017/019: no controller discovers its document by walking from an NSView.
/// Methods are main-actor isolated individually so `NSDocument` subclasses are not forced
/// entirely onto the main actor (needed for nonisolated I/O overrides).
protocol DocumentActionInterface: AnyObject {
    @MainActor func sourceSnapshot() -> SourceSnapshot

    /// Last known source selection (reported by the active editor adapter).
    @MainActor var activeSelection: NSRange { get }
    @MainActor func reportActiveSelection(_ range: NSRange)

    /// Placement-range tracking owned by the document interface, not a text view.
    @MainActor func beginPlacementTracking(range: NSRange) -> Int
    @MainActor func endPlacementTracking(_ generation: Int)
    @MainActor func trackedPlacement(for generation: Int) -> InsertionRangeTracker?
    @MainActor func noteTrackedEdit(edited: NSRange, changeInLength: Int)

    @MainActor @discardableResult
    func commitSourceEdit(_ edit: SourceEdit) -> SourceEditResult

    /// Content-validated mutation entry (REQ-016). Prefer this for new call sites.
    @MainActor @discardableResult
    func commitSourceMutation(_ mutation: SourceMutation) -> SourceEditResult

    /// Preferred selection after a programmatic commit (e.g. image insert).
    @MainActor var pendingSelection: NSRange? { get set }

    /// Operation-scoped Save (REQ-017). Does not walk the view hierarchy.
    @MainActor func saveDocument() async -> Bool

    @MainActor var documentUndoManager: UndoManager? { get }
}
