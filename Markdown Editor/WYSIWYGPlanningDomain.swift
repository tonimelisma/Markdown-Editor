//
//  WYSIWYGPlanningDomain.swift
//  Markdown Editor
//

import Foundation
import AppKit

/// WYSIWYG-mode planning domain — extracted from SemanticEditEngine so the engine is a router.
///
/// // REQ-057/058/078-080/087/113; ARC-005/007/009: WYSIWYG planning, no new logic.
enum WYSIWYGPlanningDomain {
    static func applyWYSIWYG(
        command: SemanticCommand,
        selection: ProjectionSelection,
        snapshot: SourceSnapshot,
        presentation: PresentationSnapshot,
        tree: MarkdownTree?,
        grouping: MutationGrouping
    ) -> SemanticEditResult {
        guard presentation.sourceRevision.value == snapshot.sourceVersion,
              selection.range.revision.snapshotID == presentation.id else {
            return .refused(.staleVersion)
        }
        let projection = presentation.asProjectionModel
        let selectionRange = selection.range.utf16
        let classification = ProjectionSelectionClassifier.classify(
            selection: selectionRange,
            affinity: selection.affinity,
            snapshot: presentation
        )

        switch command {
        case .toggleTask(let nodeID):
            guard case .taskMarker(let classifiedNodeID) = classification,
                  classifiedNodeID == nodeID else {
                return .refused(.ambiguousSelection)
            }
            // History selection is the exact source marker span (set inside toggleTaskMarker).
            return SemanticEditEngine.toggleTaskMarker(
                snapshot: snapshot,
                tree: tree,
                nodeID: nodeID,
                selectionBefore: SourceSelection(
                    utf16: NSRange(location: 0, length: 0),
                    affinity: selection.affinity
                )
            )

        case .replaceTableCell(let nodeID, let text):
            guard case .tableCell(let classifiedNodeID, let cellSource, _) = classification,
                  classifiedNodeID == nodeID else {
                return .refused(.ambiguousSelection)
            }
            let before = SourceSelection(utf16: cellSource, affinity: selection.affinity)
            return TableCellEditPlanner.replace(
                snapshot: snapshot,
                tree: tree,
                nodeID: nodeID,
                text: text,
                grouping: grouping,
                selectionBefore: before
            )

        case .insertImageMarkdown(let markdown):
            guard let sourceRange = SemanticEditEngine.sourceRange(for: classification, affinity: selection.affinity)
            else { return SemanticEditEngine.refusal(for: classification) }
            return SemanticEditEngine.commit(
                snapshot,
                range: sourceRange,
                replacement: markdown,
                action: "Insert Image",
                grouping: .discrete,
                selectionBefore: SourceSelection(utf16: sourceRange, affinity: selection.affinity)
            )

        case .insertText(let text):
            switch classification {
            case .tableCell(let nodeID, _, _):
                // Rebuild cell content from the projected edit intent.
                return applyTableCellTyping(
                    text: text,
                    nodeID: nodeID,
                    selection: selection,
                    snapshot: snapshot,
                    projection: projection,
                    tree: tree,
                    grouping: grouping,
                    deletingBackward: false
                )
            case .uneditable:
                return .refused(.unsupportedCommand)
            case .taskMarker(let nodeID):
                if text.isEmpty {
                    return .refused(.unsupportedCommand)
                }
                return SemanticEditEngine.toggleTaskMarker(
                    snapshot: snapshot,
                    tree: tree,
                    nodeID: nodeID,
                    selectionBefore: SourceSelection(
                        utf16: NSRange(location: 0, length: 0),
                        affinity: selection.affinity
                    )
                )
            case .ambiguous:
                return .refused(.ambiguousSelection)
            case .mixed:
                return .refused(.ambiguousSelection)
            case .crossCell:
                return .refused(.ambiguousSelection)
            case .identityText, .atomicText, .syntheticInsertion:
                break
            }
            guard let sourceRange = SemanticEditEngine.sourceRange(for: classification, affinity: selection.affinity)
            else { return SemanticEditEngine.refusal(for: classification) }
            return SemanticEditEngine.commit(
                snapshot,
                range: sourceRange,
                replacement: text,
                action: "Typing",
                grouping: grouping,
                selectionBefore: SourceSelection(utf16: sourceRange, affinity: selection.affinity)
            )

        case .deleteBackward:
            if case .tableCell(let nodeID, _, _) = classification {
                return applyTableCellTyping(
                    text: "",
                    nodeID: nodeID,
                    selection: selection,
                    snapshot: snapshot,
                    projection: projection,
                    tree: tree,
                    grouping: grouping,
                    deletingBackward: true
                )
            }
            guard let sourceRange = SemanticEditEngine.sourceRange(for: classification, affinity: selection.affinity)
            else { return SemanticEditEngine.refusal(for: classification) }
            if sourceRange.length > 0 {
                return SemanticEditEngine.commit(
                    snapshot,
                    range: sourceRange,
                    replacement: "",
                    action: "Delete",
                    grouping: grouping,
                    selectionBefore: SourceSelection(utf16: sourceRange, affinity: selection.affinity)
                )
            }
            guard sourceRange.location > 0 else { return .refused(.invalidRange) }
            return SemanticEditEngine.commit(
                snapshot,
                range: NSRange(location: sourceRange.location - 1, length: 1),
                replacement: "",
                action: "Delete",
                grouping: grouping,
                selectionBefore: SourceSelection(utf16: sourceRange, affinity: selection.affinity)
            )

        case .toggleBold, .toggleItalic, .toggleStrikethrough, .toggleInlineCode,
             .setHeading, .setParagraph, .toggleOrderedList, .toggleUnorderedList,
             .toggleTaskList, .toggleBlockQuote, .toggleCodeBlock, .setLink:
            // REQ-113/087; ARC-009; PR #32 review: a **block** rewrite reshapes the whole line,
            // so it may act only on a selection proven to be that line's own identity text. A
            // caret on a synthetic paragraph break classifies as `.syntheticInsertion` and folds
            // to a declared source location, which would make the planner silently rewrite the
            // *preceding* line. Before COR-25/COR-26 that mutation was planned and then rescued
            // by an unmappable post-edit selection refusing the whole edit; giving every planner
            // a projectable caret removed that accident, so the refusal is now stated where it
            // belongs instead of emerging from a mapping failure.
            //
            // Inline commands are unaffected: they wrap the selected span rather than reshaping
            // a line, so an atomic or synthetic endpoint stays legitimate for them.
            if command.reshapesWholeLine {
                // COR-40: total block identification — no exact-inverse gate for reshapesWholeLine.
                // Table stays exact via classifier above.
                if case .tableCell = classification {
                    guard case .identityText = classification else {
                        return SemanticEditEngine.refusal(for: classification)
                    }
                } else {
                    let selRange = selection.range.utf16
                    // Cross-block selection (range spanning >1 block) must still refuse — only collapsed caret is total.
                    if selRange.length > 0 {
                        let intersected = presentation.blocks.filter {
                            NSIntersectionRange($0.projectionRange, selRange).length > 0
                        }.filter {
                            switch $0.kind {
                            case .table, .tableRow, .tableCell: return false
                            default: return true
                            }
                        }
                        if intersected.count > 1 { return .refused(.ambiguousSelection) }
                    }
                    guard let enclosing = presentation.enclosingBlock(at: selRange.location) else {
                        return .refused(.ambiguousSelection) // caret in no block — impossible when caret ∈ renderedString
                    }
                    guard let sourceRange = enclosing.sourceRange else {
                        return .refused(.ambiguousSelection) // image/thematicBreak have no rewritable source line
                    }
                    let sourceSelection = SourceSelection(utf16: sourceRange, affinity: selection.affinity)
                    return SourcePlanningDomain.applySource(
                        command: command,
                        selection: sourceSelection,
                        snapshot: snapshot,
                        grouping: grouping
                    )
                }
            }
            guard let sourceRange = SemanticEditEngine.sourceRange(for: classification, affinity: selection.affinity)
            else { return SemanticEditEngine.refusal(for: classification) }
            let sourceSelection = SourceSelection(utf16: sourceRange, affinity: selection.affinity)
            return SourcePlanningDomain.applySource(
                command: command,
                selection: sourceSelection,
                snapshot: snapshot,
                grouping: grouping
            )
        }
    }

    /// Apply a native table-cell edit through `TableCellEditPlanner` using source cell bytes.
    ///
    /// Edits the canonical cell source (preserving escapes like `\|`) by mapping the projection
    /// selection into the cell's source span rather than rebuilding from rendered text.
    static func applyTableCellTyping(
        text: String,
        nodeID: MarkdownNodeID,
        selection: ProjectionSelection,
        snapshot: SourceSnapshot,
        projection: MarkdownProjectionModel,
        tree: MarkdownTree?,
        grouping: MutationGrouping,
        deletingBackward: Bool
    ) -> SemanticEditResult {
        guard let cell = projection.tables.flatMap(\.cells).first(where: { $0.nodeID == nodeID }),
              let cellSource = cell.sourceUTF16Range else {
            return .refused(.mappingFailure)
        }
        let ns = snapshot.text as NSString
        let cellText = ns.substring(with: cellSource) as NSString

        // Require the selection to be wholly within the projected cell body.
        let cellProj = cell.utf16Range
        var bodyLength = cellProj.length
        let rendered = projection.renderedString as NSString
        if bodyLength > 0,
           NSMaxRange(cellProj) <= rendered.length,
           rendered.character(at: NSMaxRange(cellProj) - 1) == 0x09 {
            bodyLength -= 1
        }
        let bodyProj = NSRange(location: cellProj.location, length: bodyLength)
        var editedProjection = selection.range.utf16
        if editedProjection == cellProj {
            editedProjection = bodyProj
        }
        guard editedProjection.location >= bodyProj.location,
              NSMaxRange(editedProjection) <= NSMaxRange(bodyProj) else {
            return .refused(.mappingFailure)
        }
        if deletingBackward, editedProjection.length == 0 {
            guard editedProjection.location > bodyProj.location else {
                return .refused(.unsupportedCommand)
            }
            editedProjection = rendered.rangeOfComposedCharacterSequence(
                at: editedProjection.location - 1
            )
        }

        let encodedText: String
        if text.isEmpty {
            encodedText = ""
        } else {
            switch MarkdownLiteralEncoder.encode(
                LiteralEncodeContext(
                    intendedVisibleText: text,
                    precedingSourceCharacter: nil,
                    followingSourceCharacter: nil,
                    atLineStart: false,
                    container: .tableCell,
                    dialect: .formalGFM
                )
            ) {
            case .encoded(let spelling):
                encodedText = spelling
            case .refused:
                return .refused(.ambiguousSelection)
            }
        }

        // Full projected-body selection → replace the entire source cell (matches select-all-in-cell).
        if editedProjection == bodyProj {
            return TableCellEditPlanner.replaceExactCell(
                snapshot: snapshot,
                tree: tree,
                sourceRange: cellSource,
                text: encodedText,
                grouping: grouping,
                selectionBefore: SourceSelection(utf16: cellSource, affinity: selection.affinity)
            )
        }

        // Preferred path: exact coordinate-map into the cell source span.
        if let mapped = SemanticEditEngine.mapProjectionSelectionToSource(
            editedProjection,
            affinity: selection.affinity,
            projection: projection
        ),
           mapped.location >= cellSource.location,
           NSMaxRange(mapped) <= NSMaxRange(cellSource) {
            let local = NSRange(
                location: mapped.location - cellSource.location,
                length: mapped.length
            )
            guard local.location >= 0, NSMaxRange(local) <= cellText.length else {
                return .refused(.mappingFailure)
            }
            let newCellText = cellText.replacingCharacters(in: local, with: encodedText)
            return TableCellEditPlanner.replaceExactCell(
                snapshot: snapshot,
                tree: tree,
                sourceRange: cellSource,
                text: newCellText,
                grouping: grouping,
                selectionBefore: SourceSelection(utf16: mapped, affinity: selection.affinity)
            )
        }

        // Escape-aware fallback: projection may be shorter than source (`a\|b` → `a|b`).
        let localProj = NSRange(
            location: editedProjection.location - bodyProj.location,
            length: editedProjection.length
        )
        guard let localSource = mapProjectedCellRangeToSource(
            projected: localProj,
            sourceCell: cellText as String
        ) else {
            return .refused(.mappingFailure)
        }
        let newCellText = cellText.replacingCharacters(in: localSource, with: encodedText)
        let absolute = NSRange(
            location: cellSource.location + localSource.location,
            length: localSource.length
        )
        return TableCellEditPlanner.replaceExactCell(
            snapshot: snapshot,
            tree: tree,
            sourceRange: cellSource,
            text: newCellText,
            grouping: grouping,
            selectionBefore: SourceSelection(utf16: absolute, affinity: selection.affinity)
        )
    }

    static func tablePresentationEdit(
        command: SemanticCommand,
        selection: NSRange,
        body: NSRange,
        rendered: String
    ) -> (replacement: String, selectionLocation: Int)? {
        guard selection.location >= body.location,
              NSMaxRange(selection) <= NSMaxRange(body) else {
            return nil
        }
        let ns = rendered as NSString
        let currentBody = ns.substring(with: body) as NSString
        var local = NSRange(location: selection.location - body.location, length: selection.length)
        let replacement: String
        switch command {
        case .insertText(let text):
            replacement = text
        case .deleteBackward:
            replacement = ""
            if local.length == 0 {
                guard local.location > 0 else { return nil }
                local = currentBody.rangeOfComposedCharacterSequence(at: local.location - 1)
            }
        case .replaceTableCell(_, let text):
            local = NSRange(location: 0, length: currentBody.length)
            replacement = text
        default:
            return nil
        }
        let nextBody = currentBody.replacingCharacters(in: local, with: replacement)
        return (
            replacement: nextBody,
            selectionLocation: body.location + local.location + (replacement as NSString).length
        )
    }

    nonisolated enum LiteralCandidateProof: Sendable {
        case preservesPresentation(built: PresentationSnapshot)
        case changesPresentation(built: PresentationSnapshot)
        case unbuildable
    }

    /// Reparse the completed source context and return the built snapshot with the proof.
    /// Discarding it forced the caller to build the same immutable source again.
    static func literalCandidateProof(
        mutation: SourceMutation,
        snapshot: SourceSnapshot,
        presentation: PresentationSnapshot,
        projectionRange: NSRange,
        visibleReplacement: String,
        nextSnapshotID: PresentationSnapshot.ID,
        intent: IntentContext? = nil
    ) -> LiteralCandidateProof {
        let source = snapshot.text as NSString
        guard mutation.range.location >= 0, NSMaxRange(mutation.range) <= source.length else {
            return .unbuildable
        }
        let candidate = source.replacingCharacters(in: mutation.range, with: mutation.replacement)
        let expected = (presentation.renderedString as NSString).replacingCharacters(
            in: projectionRange,
            with: visibleReplacement
        )
        guard let built = AuthoritativePresentationBuilder.build(
            source: candidate,
            sourceRevision: mutation.expectedRevision &+ 1,
            snapshotID: nextSnapshotID,
            locationGeneration: presentation.locationGeneration,
            intent: intent
        ) else {
            return .unbuildable
        }
        // Equal visible strings are insufficient: a list marker, entity, or other
        // control run can emerge without changing the plain text. Compare semantic
        // structure while deliberately ignoring node IDs, shifted ranges, and atom
        // fragmentation, which are representation details of a fresh parse.
        let preserves = built.renderedString == expected
            && sameRunSemantics(built.runs, presentation.runs)
            && sameAttachmentSemantics(built.attachments, presentation.attachments)
            && sameTableSemantics(built.tables, presentation.tables)
            && sameListSemantics(built.listMarkers, presentation.listMarkers)
        return preserves ? .preservesPresentation(built: built) : .changesPresentation(built: built)
    }

    static func sameRunSemantics(_ lhs: [ProjectionRun], _ rhs: [ProjectionRun]) -> Bool {
        lhs.count == rhs.count && zip(lhs, rhs).allSatisfy {
            $0.styles == $1.styles
                && $0.linkDestination == $1.linkDestination
                && $0.isLiteralFallback == $1.isLiteralFallback
        }
    }

    static func sameAttachmentSemantics(
        _ lhs: [ProjectionAttachment],
        _ rhs: [ProjectionAttachment]
    ) -> Bool {
        lhs.count == rhs.count && zip(lhs, rhs).allSatisfy {
            switch ($0.kind, $1.kind) {
            case (.task(let a, _), .task(let b, _)): return a == b
            case (.image(let a, _), .image(let b, _)): return a == b
            case (.thematicBreak, .thematicBreak): return true
            default: return false
            }
        }
    }

    static func sameTableSemantics(_ lhs: [ProjectionTable], _ rhs: [ProjectionTable]) -> Bool {
        lhs.count == rhs.count && zip(lhs, rhs).allSatisfy {
            $0.columnCount == $1.columnCount
                && $0.alignments == $1.alignments
                && $0.cells.count == $1.cells.count
        }
    }

    static func sameListSemantics(
        _ lhs: [ProjectionListMarker],
        _ rhs: [ProjectionListMarker]
    ) -> Bool {
        lhs.count == rhs.count && zip(lhs, rhs).allSatisfy {
            $0.displayedText == $1.displayedText
                && $0.sourceText == $1.sourceText
                && $0.nesting == $1.nesting
                && $0.kind == $1.kind
        }
    }

    /// If syntax emerged from earlier literal keystrokes, protect the closest source
    /// punctuation that caused it and validate the completed context again.
    static func contextualLiteralMutation(
        original: SourceMutation,
        encodedInsertion: String,
        snapshot: SourceSnapshot,
        presentation: PresentationSnapshot,
        projectionRange: NSRange,
        visibleReplacement: String,
        nextSnapshotID: PresentationSnapshot.ID,
        intent: IntentContext? = nil
    ) -> (mutation: SourceMutation, built: PresentationSnapshot)? {
        guard original.range.length == 0 else { return nil }
        let source = snapshot.text as NSString
        let line = source.lineRange(for: NSRange(location: original.range.location, length: 0))
        let lowerBound = max(line.location, original.range.location - 128)
        guard original.range.location > lowerBound else { return nil }

        for location in stride(from: original.range.location - 1, through: lowerBound, by: -1) {
            let scalar = source.character(at: location)
            let protection: String
            if scalar == 0x26 { // & — backslash escaping does not suppress entities.
                protection = "&amp;"
            } else if isASCIIPunctuation(scalar) {
                protection = "\\" + source.substring(with: NSRange(location: location, length: 1))
            } else {
                continue
            }
            let between = source.substring(
                with: NSRange(
                    location: location + 1,
                    length: original.range.location - location - 1
                )
            )
            guard let candidate = SourceMutation.exact(
                snapshot: snapshot,
                range: NSRange(location: location, length: original.range.location - location),
                replacement: protection + between + encodedInsertion,
                selectionBefore: original.selectionBefore,
                actionName: original.actionName,
                grouping: original.grouping
            ) else {
                continue
            }
            switch literalCandidateProof(
                mutation: candidate,
                snapshot: snapshot,
                presentation: presentation,
                projectionRange: projectionRange,
                visibleReplacement: visibleReplacement,
                nextSnapshotID: nextSnapshotID,
                intent: intent
            ) {
            case .preservesPresentation(let built), .changesPresentation(let built):
                return (candidate, built)
            case .unbuildable:
                continue
            }
        }
        return nil
    }

    static func isASCIIPunctuation(_ scalar: unichar) -> Bool {
        guard scalar < 128, let unicode = UnicodeScalar(scalar) else { return false }
        return CharacterSet.punctuationCharacters.contains(unicode)
            || scalar == 0x2A || scalar == 0x2B || scalar == 0x2D
    }

    /// Map a range in the projected (unescaped) cell body into the raw source cell body.
    ///
    /// Walks source escapes (`\|`, `\\`) so a caret after projected `a` in `a|b` lands after
    /// source `a` in `a\|b`, preserving the escape when the edit is applied.
    static func mapProjectedCellRangeToSource(
        projected: NSRange,
        sourceCell: String
    ) -> NSRange? {
        let source = sourceCell as NSString
        var sourceIndex = 0
        var projectedIndex = 0
        var startSource: Int?
        let targetStart = projected.location
        let targetEnd = NSMaxRange(projected)

        func advance() -> Bool {
            guard sourceIndex < source.length else { return false }
            let c = source.character(at: sourceIndex)
            if c == 0x5C, sourceIndex + 1 < source.length { // backslash escape
                sourceIndex += 2
            } else {
                sourceIndex += 1
            }
            projectedIndex += 1
            return true
        }

        while projectedIndex < targetStart {
            guard advance() else { return nil }
        }
        startSource = sourceIndex
        if projected.length == 0 {
            return NSRange(location: sourceIndex, length: 0)
        }
        while projectedIndex < targetEnd {
            guard advance() else { return nil }
        }
        guard let start = startSource else { return nil }
        return NSRange(location: start, length: sourceIndex - start)
    }

    // MARK: - Helpers


}
