//
//  ExternalChangeDomain.swift
//  Markdown Editor
//

import Foundation

/// What happened to the document's file outside this application.
///
/// // REQ-145–149; ARC-027.
nonisolated enum ExternalFileEvent: String, Sendable, Equatable, CaseIterable {
    /// The file's contents were replaced by another process.
    case contentsChanged
    /// The file was removed.
    case deleted
    /// The file was renamed or moved to another directory.
    case moved
}

/// Whether the in-memory document differs from what was last written.
nonisolated enum LocalEditState: String, Sendable, Equatable, CaseIterable {
    case clean
    case dirty
}

/// What the application does about an external change. A closed set: there is deliberately no
/// "ignore" and no "overwrite".
nonisolated enum ExternalChangeOutcome: String, Sendable, Equatable, CaseIterable {
    /// Adopt the file's contents, preserving each editor's caret by source offset.
    case reloadPreservingSelection
    /// Keep the in-memory content. The buffer and the file now disagree, and the disagreement is
    /// recorded rather than resolved by guessing.
    case retainLocalEditsAsConflicted
    /// Keep the buffer. The file is gone; the content is not.
    case retainContentAfterDeletion
    /// Follow the file to its new location, so relative asset references resolve against the new
    /// parent directory.
    case followMove
}

/// Classifies an external file event against the document's local state.
///
/// Pure and filesystem-free by construction, so the matrix below is decided without I/O and the
/// document remains the only component that touches the filesystem (ARC-027).
///
/// // The product ranks *trustworthy files* first and *visible, deterministic refusal* above
/// // *guessed mutation*. Every cell below is therefore chosen so that neither side of a
/// // disagreement is discarded: an external write never silently destroys unsaved work, and
/// // unsaved work never silently destroys an external write.
/// // REQ-145–149.
nonisolated enum ExternalChangeDomain {

    static func outcome(for event: ExternalFileEvent, local: LocalEditState) -> ExternalChangeOutcome {
        switch (event, local) {
        // Nothing to lose in memory, so the file wins and the reader keeps their place. This is
        // the `git checkout` case, and it is the reason the caret is preserved rather than reset:
        // losing your position in a long document on every branch switch is its own defect.
        case (.contentsChanged, .clean):
            return .reloadPreservingSelection

        // Both sides carry work. Adopting the file discards the user's edits; keeping the buffer
        // and writing it back discards the other tool's. Neither is acceptable without being
        // asked, so the buffer is kept and the conflict is made visible.
        case (.contentsChanged, .dirty):
            return .retainLocalEditsAsConflicted

        // Losing an open buffer because another process unlinked the file is the worst outcome
        // available; the content is retained whether or not it was edited.
        case (.deleted, _):
            return .retainContentAfterDeletion

        // A move changes where `assets/…` resolves, and nothing about the content.
        case (.moved, _):
            return .followMove
        }
    }

    /// Whether a file-presenter notification represents a change this application did not make.
    ///
    /// // AppKit delivers `presentedItemDidChange()` for writes the application performs itself —
    /// // autosave, an ordinary save, the initial open — as well as for foreign ones. Acting on
    /// // every notification makes the app revert its own document moments after opening it,
    /// // which is exactly what the process smoke run caught when this check was missing.
    /// //
    /// // Contents rather than modification date: a date can move without the bytes changing
    /// // (`touch`, a metadata write, a restore from backup), and reloading a document whose text
    /// // is identical would still discard the caret and the undo stack for nothing.
    static func isForeignContentChange(onDisk: String?, buffer: String) -> Bool {
        guard let onDisk else { return false }
        return onDisk != buffer
    }

    /// Where a caret should land after the document's text is replaced from disk.
    ///
    /// // Clamped rather than refused: a reload is not an edit, the user did not ask for it, and
    /// // a caret that survives approximately is better than one that resets to zero. Preserving
    /// // it exactly is impossible in general — the bytes it pointed at may be gone.
    static func preservedSelection(
        previous: NSRange,
        inNewLength newLength: Int
    ) -> NSRange {
        guard newLength > 0 else { return NSRange(location: 0, length: 0) }
        let location = min(max(previous.location, 0), newLength)
        let length = min(max(previous.length, 0), newLength - location)
        return NSRange(location: location, length: length)
    }
}
