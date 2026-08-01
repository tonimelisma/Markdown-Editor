//
//  PresentationPatch.swift
//  Markdown Editor
//

import AppKit

/// A validated local attributed-storage change between two complete semantic snapshots.
///
/// // REQ-109; ARC-019/ARC-Q16: the patch carries identity and both coordinate domains so an
/// ordinary edit cannot silently apply against a different storage revision.
@MainActor
struct PresentationPatch {
    let fromSnapshotID: PresentationSnapshot.ID
    let toSnapshotID: PresentationSnapshot.ID
    let currentRange: NSRange
    let nextRange: NSRange
    let replacement: NSAttributedString
    let selectionAfter: ProjectionSelection
    let affectedBlockIDs: Set<MarkdownNodeID>
    let attachmentNodes: [Int: MarkdownNodeID]

    static func make(
        transition: PresentationTransition,
        current: PresentationSnapshot,
        builtNext: AttributedPresentation
    ) -> PresentationPatch? {
        guard transition.fromSnapshotID == current.id,
              transition.nextSnapshot.id == transition.selectionAfter.range.revision.snapshotID,
              transition.projectionReplacementRange.location >= 0,
              NSMaxRange(transition.projectionReplacementRange) <= (current.renderedString as NSString).length
        else { return nil }

        let replacementLength = (transition.projectionReplacement as NSString).length
        let nextRange = NSRange(
            location: transition.projectionReplacementRange.location,
            length: replacementLength
        )
        guard NSMaxRange(nextRange) <= builtNext.attributed.length else { return nil }
        let replacement = builtNext.attributed.attributedSubstring(from: nextRange)
        guard replacement.string == transition.projectionReplacement else { return nil }

        let affected = Set(
            current.blocks.filter { NSIntersectionRange($0.projectionRange, transition.projectionReplacementRange).length > 0 }
                .map(\.nodeID)
        ).union(
            transition.nextSnapshot.blocks.filter { NSIntersectionRange($0.projectionRange, nextRange).length > 0 }
                .map(\.nodeID)
        )
        return PresentationPatch(
            fromSnapshotID: current.id,
            toSnapshotID: transition.nextSnapshot.id,
            currentRange: transition.projectionReplacementRange,
            nextRange: nextRange,
            replacement: replacement,
            selectionAfter: transition.selectionAfter,
            affectedBlockIDs: affected,
            attachmentNodes: builtNext.attachmentNodes
        )
    }
}
