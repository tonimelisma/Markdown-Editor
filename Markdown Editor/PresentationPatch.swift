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
    /// Selection to restore after applying. `nil` when the caller has no selection that belongs
    /// to the next snapshot — a reconciliation replacing a snapshot the user is not editing.
    let selectionAfter: ProjectionSelection?
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
        let declaredNextRange = NSRange(
            location: transition.projectionReplacementRange.location,
            length: (transition.projectionReplacement as NSString).length
        )
        guard transition.fromSnapshotID == current.id,
              next.id == transition.selectionAfter.range.revision.snapshotID,
              transition.projectionReplacementRange.location >= 0,
              NSMaxRange(transition.projectionReplacementRange) <= currentText.length,
              declaredNextRange.location >= 0,
              NSMaxRange(declaredNextRange) <= nextText.length,
              nextText.substring(with: declaredNextRange) == transition.projectionReplacement
        else { return nil }
        // The declared range is not trusted as the patch scope for authoritative transitions. A
        // local identity transition carries an exact change proof, so rescanning the complete
        // rendered string would violate the bounded callback contract.
        let knownChange: (current: NSRange, next: NSRange)? = transition.proof == .localIdentity
            ? (
                current: transition.projectionReplacementRange,
                next: NSRange(
                    location: transition.projectionReplacementRange.location,
                    length: (transition.projectionReplacement as NSString).length
                )
            )
            : nil
        return between(
            current: current,
            next: next,
            selectionAfter: transition.selectionAfter,
            buildScope: buildScope,
            knownChange: knownChange
        )
    }

    /// Builds a patch from the actual difference between two complete snapshots. Returns nil when
    /// the texts are identical (nothing to replace — the caller refreshes attributes instead) or
    /// when the difference cannot be proven local.
    static func between(
        current: PresentationSnapshot,
        next: PresentationSnapshot,
        selectionAfter: ProjectionSelection?,
        buildScope: (MarkdownProjectionModel, NSRange) -> AttributedPresentationBuilder.Scoped,
        knownChange: (current: NSRange, next: NSRange)? = nil
    ) -> PresentationPatch? {
        let currentText = current.renderedString as NSString
        let nextText = next.renderedString as NSString
        let changed: (current: NSRange, next: NSRange)? = knownChange ?? changedSpan(
            from: currentText,
            to: nextText
        ).map { (current: $0.0, next: $0.1) }
        guard let (rawCurrent, rawNext) = changed else {
            return nil
        }

        let currentModel = current.asProjectionModel
        let nextModel = next.asProjectionModel
        let isBoundedLocalChange = knownChange != nil
        let currentRange: NSRange
        let nextRange: NSRange
        if isBoundedLocalChange {
            // The local proof covers exactly the changed projection span. Rebuilding the
            // containing paragraph here would be a needless TextKit invalidation and would make
            // the callback cost scale with unrelated text. The authoritative path below retains
            // whole-block expansion because its diff must re-establish semantic block styling.
            currentRange = rawCurrent
            nextRange = rawNext
        } else {
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
            currentRange = NSRange(location: start, length: NSMaxRange(rawCurrent) + tail - start)
            nextRange = NSRange(location: start, length: NSMaxRange(rawNext) + tail - start)
        }
        guard NSMaxRange(currentRange) <= currentText.length,
              NSMaxRange(nextRange) <= nextText.length
        else { return nil }

        if !isBoundedLocalChange {
            // Expanding past the literal replacement is only sound if the extra text is
            // identical in both snapshots. Proving it here is what lets the applier treat an
            // authoritative block patch as a local edit.
            let prefixLength = rawCurrent.location - currentRange.location
            let tail = NSMaxRange(currentRange) - NSMaxRange(rawCurrent)
            guard currentText.substring(with: NSRange(location: currentRange.location, length: prefixLength))
                    == nextText.substring(with: NSRange(location: nextRange.location, length: prefixLength)),
                  currentText.substring(with: NSRange(location: NSMaxRange(rawCurrent), length: tail))
                    == nextText.substring(with: NSRange(location: NSMaxRange(rawNext), length: tail))
            else { return nil }
        }

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
            selectionAfter: selectionAfter,
            affectedBlockIDs: affected,
            attachmentNodes: scoped.attachmentNodes,
            expansion: currentRange == rawCurrent ? nil : .containingBlocks
        )
    }

    /// Returns the smallest whole-block scope whose presentation semantics differ while the
    /// rendered characters remain identical. This is the attribute-only counterpart to
    /// `between`: it never builds or rewrites an unrelated part of the document.
    static func attributeRefreshScope(
        current: PresentationSnapshot,
        next: PresentationSnapshot,
        imageRefreshLocations: Set<Int> = []
    ) -> NSRange? {
        guard current.renderedString == next.renderedString else { return nil }

        var changedRanges: [NSRange] = []
        collectDifferences(
            current.runs,
            next.runs,
            range: \.utf16Range,
            equivalent: { lhs, rhs in
                lhs.utf16Range == rhs.utf16Range &&
                    lhs.styles == rhs.styles &&
                    lhs.linkDestination == rhs.linkDestination &&
                    lhs.isLiteralFallback == rhs.isLiteralFallback
            },
            into: &changedRanges
        )
        collectDifferences(
            current.blocks,
            next.blocks,
            range: \.projectionRange,
            equivalent: { lhs, rhs in
                lhs.projectionRange == rhs.projectionRange && lhs.kind == rhs.kind
            },
            into: &changedRanges
        )
        collectDifferences(
            current.attachments,
            next.attachments,
            range: { NSRange(location: $0.utf16Location, length: 1) },
            equivalent: ==,
            into: &changedRanges
        )
        collectDifferences(
            current.tables,
            next.tables,
            range: \.utf16Range,
            equivalent: tablePresentationIsEquivalent,
            into: &changedRanges
        )
        collectDifferences(
            current.listMarkers,
            next.listMarkers,
            range: \.utf16Range,
            equivalent: { lhs, rhs in
                lhs.utf16Range == rhs.utf16Range &&
                    lhs.text == rhs.text &&
                    lhs.nesting == rhs.nesting &&
                    lhs.kind == rhs.kind
            },
            into: &changedRanges
        )
        changedRanges.append(contentsOf: imageRefreshLocations.map {
            NSRange(location: $0, length: 1)
        })

        guard let first = changedRanges.map(\.location).min(),
              let last = changedRanges.map(NSMaxRange).max()
        else {
            return NSRange(location: 0, length: 0)
        }
        return AttributedPresentationBuilder.blockScope(
            for: NSRange(location: first, length: last - first),
            in: next.asProjectionModel
        )
    }

    /// Source positions and parser identities are not table presentation. Hidden source changes
    /// before an unchanged table must not expand a local attribute refresh across the document.
    private static func tablePresentationIsEquivalent(
        _ lhs: ProjectionTable,
        _ rhs: ProjectionTable
    ) -> Bool {
        lhs.columnCount == rhs.columnCount
            && lhs.alignments == rhs.alignments
            && lhs.utf16Range == rhs.utf16Range
            && lhs.cells.count == rhs.cells.count
            && zip(lhs.cells, rhs.cells).allSatisfy { left, right in
                left.row == right.row
                    && left.column == right.column
                    && left.isHeader == right.isHeader
                    && left.alignment == right.alignment
                    && left.utf16Range == right.utf16Range
            }
    }

    /// Compares two ordered, non-overlapping element arrays by projection position rather than
    /// by array index. Both arrays are sorted by their ranges, so an element inserted or removed
    /// near the start must not shift every later element onto a different counterpart: an element
    /// whose range has no equal-range, equivalent counterpart in the other snapshot is changed,
    /// and every element with a matching counterpart is unchanged regardless of how many elements
    /// precede it. This is what keeps an attribute refresh bounded to the touched semantic blocks:
    /// one run split by a formatting command must not cascade into an untouched trailing paragraph.
    private static func collectDifferences<Element>(
        _ current: [Element],
        _ next: [Element],
        range: (Element) -> NSRange,
        equivalent: (Element, Element) -> Bool,
        into changedRanges: inout [NSRange]
    ) {
        var i = 0
        var j = 0
        while i < current.count || j < next.count {
            if i >= current.count {
                changedRanges.append(range(next[j]))
                j += 1
                continue
            }
            if j >= next.count {
                changedRanges.append(range(current[i]))
                i += 1
                continue
            }
            let currentRange = range(current[i])
            let nextRange = range(next[j])
            if currentRange == nextRange {
                if equivalent(current[i], next[j]) {
                    i += 1
                    j += 1
                } else {
                    changedRanges.append(currentRange)
                    changedRanges.append(nextRange)
                    i += 1
                    j += 1
                }
            } else if currentRange.location < nextRange.location
                        || (currentRange.location == nextRange.location
                            && currentRange.length < nextRange.length) {
                // The current element occupies a span the next snapshot has no equal-range
                // counterpart for (it may have been split, grown, or moved past).
                changedRanges.append(currentRange)
                i += 1
            } else {
                changedRanges.append(nextRange)
                j += 1
            }
        }
    }

    /// The minimal differing span between two rendered strings: common prefix, common suffix, and
    /// whatever is left in the middle. Boundaries are pulled back to composed-character
    /// boundaries so a patch can never split a grapheme.
    static func changedSpan(from current: NSString, to next: NSString) -> (NSRange, NSRange)? {
        let limit = min(current.length, next.length)
        var prefix = 0
        while prefix < limit, current.character(at: prefix) == next.character(at: prefix) {
            prefix += 1
        }
        if prefix == current.length, current.length == next.length { return nil }

        var suffix = 0
        while suffix < (limit - prefix),
              current.character(at: current.length - 1 - suffix)
                == next.character(at: next.length - 1 - suffix) {
            suffix += 1
        }

        if prefix < current.length {
            let composed = current.rangeOfComposedCharacterSequence(at: prefix)
            prefix = min(prefix, composed.location)
        }
        let currentEnd = current.length - suffix
        if currentEnd > prefix, currentEnd < current.length {
            let prior = current.rangeOfComposedCharacterSequence(at: currentEnd - 1)
            if NSMaxRange(prior) > currentEnd {
                suffix = current.length - max(prefix, NSMaxRange(prior))
            }
        }
        suffix = max(0, min(suffix, limit - prefix))

        return (
            NSRange(location: prefix, length: current.length - suffix - prefix),
            NSRange(location: prefix, length: next.length - suffix - prefix)
        )
    }
}
