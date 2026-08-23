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
final class TextStorageApplier: NSObject, NSTextStorageDelegate {
    private(set) var attachmentNodes: [Int: MarkdownNodeID] = [:]
    private weak var trackedStorage: NSTextStorage?
    private var internalMutationDepth = 0
    private var storageWasMutatedExternally = false
    private var hasKnownStorage = false

    /// NSTextStorage's delegate turns storage drift into a generation flag. The ordinary native
    /// callback can therefore validate its applied snapshot without rescanning every character.
    func isKnownCurrent(_ textView: NSTextView, expected: PresentationSnapshot) -> Bool {
        guard let storage = textView.textStorage else { return false }
        track(storage)
        return hasKnownStorage
            && !storageWasMutatedExternally
            && storage.length == (expected.renderedString as NSString).length
    }

    /// Composition commits are the one bounded route where AppKit has already edited the
    /// storage before the coordinator receives the commit callback. In that route the delegate
    /// drift flag is expected, so prove the complete expected string once and then resume the
    /// O(1) generation check used by ordinary accepted edits.
    private func isExpectedAfterExternalComposition(
        _ textView: NSTextView,
        expected: PresentationSnapshot
    ) -> Bool {
        guard let storage = textView.textStorage,
              storage.length == (expected.renderedString as NSString).length else { return false }
        if !storageWasMutatedExternally {
            return hasKnownStorage
        }
        guard storage.string == expected.renderedString else { return false }
        storageWasMutatedExternally = false
        hasKnownStorage = true
        return true
    }

    func textStorage(
        _ textStorage: NSTextStorage,
        didProcessEditing editedMask: NSTextStorageEditActions,
        range editedRange: NSRange,
        changeInLength delta: Int
    ) {
        if internalMutationDepth == 0 {
            storageWasMutatedExternally = true
        }
    }

    func applyInitialPresentation(_ built: AttributedPresentation, to textView: NSTextView, intent: IntentContext? = nil) {
        if let intent { intent.recorder.add(intent) { $0.storageFullReplacements += 1 } }
        guard let storage = textView.textStorage else { return }
        track(storage)
        withInternalMutation { replaceEverything(with: built, in: textView) }
        hasKnownStorage = true
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
              isKnownCurrent(textView, expected: expectedCurrent),
              patch.fromSnapshotID == expectedCurrent.id,
              patch.currentRange.location >= 0,
              NSMaxRange(patch.currentRange) <= storage.length else {
            return false
        }
        withInternalMutation {
            storage.beginEditing()
            storage.replaceCharacters(in: patch.currentRange, with: patch.replacement)
            storage.endEditing()
        }
        hasKnownStorage = true
        attachmentNodes = splicedAttachmentNodes(for: patch)
        if let selection = patch.selectionAfter {
            textView.setSelectedRange(selection.range.utf16)
        }
        return true
    }

    /// Re-applies attributes for one changed semantic scope without touching any character. Used
    /// when a newer snapshot carries the same text, so a local formatting change does not turn
    /// into a document-wide main-actor layout invalidation.
    @discardableResult
    func applyAttributeRefresh(
        _ scoped: AttributedPresentationBuilder.Scoped,
        to textView: NSTextView,
        expectedCurrent: PresentationSnapshot
    ) -> Bool {
        guard let storage = textView.textStorage,
              isKnownCurrent(textView, expected: expectedCurrent),
              scoped.range.location >= 0,
              NSMaxRange(scoped.range) <= storage.length,
              scoped.attributed.length == scoped.range.length else { return false }
        withInternalMutation {
            storage.beginEditing()
            scoped.attributed.enumerateAttributes(in: NSRange(location: 0, length: scoped.attributed.length)) {
                attributes, localRange, _ in
                storage.setAttributes(
                    attributes,
                    range: NSRange(
                        location: scoped.range.location + localRange.location,
                        length: localRange.length
                    )
                )
            }
            storage.endEditing()
        }
        hasKnownStorage = true
        attachmentNodes = refreshedAttachmentNodes(scope: scoped.range, next: scoped.attachmentNodes)
        return true
    }

    /// Completes a native marked-text commit whose characters are already in TextKit storage.
    /// AppKit owns that character replacement, so applying the ordinary patch would correctly
    /// reject the old snapshot's text. This path still proves the committed snapshot and applies
    /// only the patch's bounded attributed scope; it never replaces characters or rebuilds the
    /// document.
    @discardableResult
    func applyAlreadyAppliedPatch(
        _ patch: PresentationPatch,
        to textView: NSTextView,
        expectedNext: PresentationSnapshot
    ) -> Bool {
        guard let storage = textView.textStorage,
              isExpectedAfterExternalComposition(textView, expected: expectedNext),
              patch.nextRange.location >= 0,
              NSMaxRange(patch.nextRange) <= storage.length,
              patch.replacement.string == (expectedNext.renderedString as NSString)
                .substring(with: patch.nextRange) else {
            return false
        }
        withInternalMutation {
            storage.beginEditing()
            patch.replacement.enumerateAttributes(
                in: NSRange(location: 0, length: patch.replacement.length)
            ) { attributes, localRange, _ in
                storage.setAttributes(
                    attributes,
                    range: NSRange(
                        location: patch.nextRange.location + localRange.location,
                        length: localRange.length
                    )
                )
            }
            storage.endEditing()
        }
        hasKnownStorage = true
        attachmentNodes = splicedAttachmentNodes(for: patch)
        if let selection = patch.selectionAfter {
            textView.setSelectedRange(selection.range.utf16)
        }
        return true
    }

    /// Rebuilds everything after an invariant violation. Architecturally exceptional: callers
    /// record a typed reason so a recovery can never pass for an ordinary edit.
    func applyRecoveryPresentation(_ built: AttributedPresentation, to textView: NSTextView, intent: IntentContext? = nil) {
        if let intent { intent.recorder.add(intent) { $0.storageFullReplacements += 1 } }
        guard let storage = textView.textStorage else { return }
        track(storage)
        withInternalMutation { replaceEverything(with: built, in: textView) }
        hasKnownStorage = true
    }

    private func track(_ storage: NSTextStorage) {
        if trackedStorage !== storage {
            trackedStorage = storage
            storage.delegate = self
            storageWasMutatedExternally = false
            hasKnownStorage = false
        } else if storage.delegate !== self {
            storage.delegate = self
        }
    }

    private func withInternalMutation(_ body: () -> Void) {
        internalMutationDepth += 1
        defer { internalMutationDepth -= 1 }
        body()
        storageWasMutatedExternally = false
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

    private func refreshedAttachmentNodes(
        scope: NSRange,
        next: [Int: MarkdownNodeID]
    ) -> [Int: MarkdownNodeID] {
        var refreshed = attachmentNodes.filter { location, _ in
            location < scope.location || location >= NSMaxRange(scope)
        }
        for (location, node) in next {
            refreshed[location] = node
        }
        return refreshed
    }
}
