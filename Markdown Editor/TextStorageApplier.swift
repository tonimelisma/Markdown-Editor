//
//  TextStorageApplier.swift
//  Markdown Editor
//

import AppKit

/// Sole mutation route for WYSIWYG attributed storage.
///
/// // REQ-109; ARC-019/ARC-Q16: full replacement is reachable only through the three explicitly
/// named routes below. An ordinary accepted edit can call `applyPatch` and nothing else.
@MainActor
final class TextStorageApplier {
    private(set) var attachmentNodes: [Int: MarkdownNodeID] = [:]

    func applyInitialPresentation(_ built: AttributedPresentation, to textView: NSTextView) {
        replaceEverything(with: built, in: textView)
    }

    /// Applies one bounded range edit. Returns false without touching storage when the applied
    /// text is not the snapshot the patch was built against.
    @discardableResult
    func applyPatch(
        _ patch: PresentationPatch,
        to textView: NSTextView,
        expectedCurrent: PresentationSnapshot
    ) -> Bool {
        guard let storage = textView.textStorage,
              storage.string == expectedCurrent.renderedString,
              patch.fromSnapshotID == expectedCurrent.id,
              patch.currentRange.location >= 0,
              NSMaxRange(patch.currentRange) <= storage.length else {
            return false
        }
        storage.beginEditing()
        storage.replaceCharacters(in: patch.currentRange, with: patch.replacement)
        storage.endEditing()
        attachmentNodes = splicedAttachmentNodes(for: patch)
        if let selection = patch.selectionAfter {
            textView.setSelectedRange(selection.range.utf16)
        }
        return true
    }

    /// Re-applies attributes without touching a single character. Used when a newer snapshot
    /// carries the same text — an authoritative reconciliation replacing a provisional snapshot —
    /// so refreshing it stays outside the full-replacement allowlist entirely.
    @discardableResult
    func applyAttributeRefresh(_ built: AttributedPresentation, to textView: NSTextView) -> Bool {
        guard let storage = textView.textStorage,
              storage.length == built.attributed.length,
              storage.string == built.attributed.string else { return false }
        let whole = NSRange(location: 0, length: built.attributed.length)
        storage.beginEditing()
        built.attributed.enumerateAttributes(in: whole) { attributes, range, _ in
            storage.setAttributes(attributes, range: range)
        }
        storage.endEditing()
        attachmentNodes = built.attachmentNodes
        return true
    }

    /// Rebuilds everything after an invariant violation. Architecturally exceptional: callers
    /// record a typed reason so a recovery can never pass for an ordinary edit.
    func applyRecoveryPresentation(_ built: AttributedPresentation, to textView: NSTextView) {
        replaceEverything(with: built, in: textView)
    }

    /// Rebuilds everything after an explicit typography/theme identity change.
    func applyTypographyChange(_ built: AttributedPresentation, to textView: NSTextView) {
        replaceEverything(with: built, in: textView)
    }

    private func replaceEverything(with built: AttributedPresentation, in textView: NSTextView) {
        textView.textStorage?.setAttributedString(built.attributed)
        attachmentNodes = built.attachmentNodes
    }

    /// Shifts surviving attachments by the patch's length delta and drops the ones inside the
    /// replaced span, so the lookup stays exact without a whole-document rebuild.
    private func splicedAttachmentNodes(for patch: PresentationPatch) -> [Int: MarkdownNodeID] {
        let replacedEnd = NSMaxRange(patch.currentRange)
        let delta = patch.replacement.length - patch.currentRange.length
        var spliced: [Int: MarkdownNodeID] = [:]
        for (location, node) in attachmentNodes {
            if location < patch.currentRange.location {
                spliced[location] = node
            } else if location >= replacedEnd {
                spliced[location + delta] = node
            }
        }
        for (location, node) in patch.attachmentNodes {
            spliced[location] = node
        }
        return spliced
    }
}
