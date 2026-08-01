//
//  TextStorageApplier.swift
//  Markdown Editor
//

import AppKit

/// Sole mutation route for WYSIWYG attributed storage.
@MainActor
final class TextStorageApplier {
    private(set) var attachmentNodes: [Int: MarkdownNodeID] = [:]

    func applyInitialPresentation(_ built: AttributedPresentation, to textView: NSTextView) {
        textView.textStorage?.setAttributedString(built.attributed)
        attachmentNodes = built.attachmentNodes
    }

    @discardableResult
    func applyPatch(
        _ patch: PresentationPatch,
        to textView: NSTextView,
        expectedCurrent: PresentationSnapshot
    ) -> Bool {
        guard let storage = textView.textStorage,
              storage.string == expectedCurrent.renderedString,
              patch.currentRange.location >= 0,
              NSMaxRange(patch.currentRange) <= storage.length else {
            return false
        }
        storage.beginEditing()
        storage.replaceCharacters(in: patch.currentRange, with: patch.replacement)
        storage.endEditing()
        attachmentNodes = patch.attachmentNodes
        textView.setSelectedRange(patch.selectionAfter.range.utf16)
        return true
    }

    func applyRecoveryPresentation(_ built: AttributedPresentation, to textView: NSTextView) {
        textView.textStorage?.setAttributedString(built.attributed)
        attachmentNodes = built.attachmentNodes
    }

    func applyTypographyChange(_ built: AttributedPresentation, to textView: NSTextView) {
        textView.textStorage?.setAttributedString(built.attributed)
        attachmentNodes = built.attachmentNodes
    }
}
