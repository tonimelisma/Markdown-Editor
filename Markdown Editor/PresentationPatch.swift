//
//  PresentationPatch.swift
//  Markdown Editor
//

import AppKit

/// Why a patch covers more than the characters the edit literally replaced.
nonisolated enum PresentationPatchExpansion: Sendable, Equatable {
    /// The replacement fell inside semantic blocks whose attributes are rebuilt as a unit.
    case containingBlocks
}

/// A validated local attributed-storage change between two complete semantic snapshots.
///
/// // REQ-109; ARC-019/ARC-Q16: the patch carries identity and both coordinate domains so an
/// ordinary edit cannot silently apply against a different storage revision, and it is built
/// from the touched semantic block scope only — never from a rebuild of the whole document.
@MainActor
struct PresentationPatch {
    let fromSnapshotID: PresentationSnapshot.ID
    let toSnapshotID: PresentationSnapshot.ID
    /// Range replaced in the currently applied storage.
    let currentRange: NSRange
    /// The same span in the next snapshot's coordinates.
    let nextRange: NSRange
    let replacement: NSAttributedString
    let selectionAfter: ProjectionSelection
    let affectedBlockIDs: Set<MarkdownNodeID>
    /// Attachments inside `nextRange`, in next-snapshot coordinates. The applier splices these
    /// into its lookup rather than replacing it, because the patch knows only its own scope.
    let attachmentNodes: [Int: MarkdownNodeID]
    let expansion: PresentationPatchExpansion?

    /// Builds the patch, asking `buildScope` for attributed content covering only the semantic
    /// blocks the edit touches. Returns nil rather than guessing: a refused patch is a refused
    /// edit, never a silent whole-document replacement.
    static func make(
        transition: PresentationTransition,
        current: PresentationSnapshot,
        buildScope: (MarkdownProjectionModel, NSRange) -> AttributedPresentationBuilder.Scoped
    ) -> PresentationPatch? {
        let next = transition.nextSnapshot
        let currentText = current.renderedString as NSString
        let nextText = next.renderedString as NSString
        guard transition.fromSnapshotID == current.id,
              next.id == transition.selectionAfter.range.revision.snapshotID,
              transition.projectionReplacementRange.location >= 0,
              NSMaxRange(transition.projectionReplacementRange) <= currentText.length
        else { return nil }

        let rawCurrent = transition.projectionReplacementRange
        let rawNext = NSRange(
            location: rawCurrent.location,
            length: (transition.projectionReplacement as NSString).length
        )
        guard NSMaxRange(rawNext) <= nextText.length,
              nextText.substring(with: rawNext) == transition.projectionReplacement
        else { return nil }

        let currentModel = current.asProjectionModel
        let nextModel = next.asProjectionModel
        let scopeCurrent = AttributedPresentationBuilder.blockScope(for: rawCurrent, in: currentModel)
        let scopeNext = AttributedPresentationBuilder.blockScope(for: rawNext, in: nextModel)

        let start = min(scopeCurrent.location, scopeNext.location)
        let tail = min(
            max(
                NSMaxRange(scopeCurrent) - NSMaxRange(rawCurrent),
                NSMaxRange(scopeNext) - NSMaxRange(rawNext)
            ),
            min(currentText.length - NSMaxRange(rawCurrent), nextText.length - NSMaxRange(rawNext))
        )
        guard start >= 0, start <= rawCurrent.location, tail >= 0 else { return nil }
        let currentRange = NSRange(location: start, length: NSMaxRange(rawCurrent) + tail - start)
        let nextRange = NSRange(location: start, length: NSMaxRange(rawNext) + tail - start)
        guard NSMaxRange(currentRange) <= currentText.length,
              NSMaxRange(nextRange) <= nextText.length
        else { return nil }

        // Expanding past the literal replacement is only sound if the extra text is identical in
        // both snapshots. Proving it here is what lets the applier treat this as a local edit.
        let prefixLength = rawCurrent.location - start
        guard currentText.substring(with: NSRange(location: start, length: prefixLength))
                == nextText.substring(with: NSRange(location: start, length: prefixLength)),
              currentText.substring(with: NSRange(location: NSMaxRange(rawCurrent), length: tail))
                == nextText.substring(with: NSRange(location: NSMaxRange(rawNext), length: tail))
        else { return nil }

        let scoped = buildScope(nextModel, nextRange)
        guard scoped.range == nextRange,
              scoped.attributed.string == nextText.substring(with: nextRange)
        else { return nil }

        let affected = Set(
            currentModel.blocks
                .filter { NSIntersectionRange($0.projectionRange, currentRange).length > 0 }
                .map(\.nodeID)
        ).union(
            nextModel.blocks
                .filter { NSIntersectionRange($0.projectionRange, nextRange).length > 0 }
                .map(\.nodeID)
        )

        return PresentationPatch(
            fromSnapshotID: current.id,
            toSnapshotID: next.id,
            currentRange: currentRange,
            nextRange: nextRange,
            replacement: scoped.attributed,
            selectionAfter: transition.selectionAfter,
            affectedBlockIDs: affected,
            attachmentNodes: scoped.attachmentNodes,
            expansion: currentRange == rawCurrent ? nil : .containingBlocks
        )
    }
}
