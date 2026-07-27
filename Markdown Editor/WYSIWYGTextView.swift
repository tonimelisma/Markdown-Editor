//
//  WYSIWYGTextView.swift
//  Markdown Editor
//

import AppKit
import SwiftUI

/// TextKit 1 WYSIWYG adapter — delimiter-free rich storage; edits become source transactions.
///
/// Namespace for the WYSIWYG coordinator. `EditorHostView` owns the persistent text views
/// (REQ-052/086), so this type carries no `NSViewRepresentable` conformance.
///
/// // REQ-052/054–059/078–084/086: rich projection host; tasks/links; plain paste; accessibility.
enum WYSIWYGTextView {
    /// Pure IME gate used by the text view — marked text stays transient until commit.
    ///
    /// // REQ-084: composition commits once; stale refuses.
    @MainActor
    final class WYSIWYGInputCoordinator {
        var composition = CompositionState()
        /// When true, `shouldChangeTextIn` allows native marked-text updates without source mutation.
        var allowingMarkedText = false
        /// When true, final composition insert applies to storage without a second source commit.
        var committingComposition = false

        func beginMarkedText(
            sourceVersion: UInt64,
            sourceRange: NSRange,
            marked: NSRange,
            snapshotID: PresentationSnapshot.ID? = nil
        ) {
            if composition.isComposing {
                composition.update(marked: marked)
            } else {
                composition.begin(
                    sourceVersion: sourceVersion,
                    sourceRange: sourceRange,
                    marked: marked,
                    snapshotID: snapshotID
                )
            }
        }

        func cancel() {
            composition.cancel()
            allowingMarkedText = false
            committingComposition = false
        }

        /// Returns false when composition is stale relative to the document.
        func prepareCommit(currentVersion: UInt64) -> Bool {
            if composition.isStale(relativeTo: currentVersion) {
                composition.cancel()
                return false
            }
            return true
        }

        func complete() -> (version: UInt64, range: NSRange, snapshotID: PresentationSnapshot.ID?)? {
            composition.complete()
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var document: MarkdownDocument
        var session: EditorSession
        let placementController: ImagePlacementController
        let input = WYSIWYGInputCoordinator()
        weak var textView: MarkdownWYSIWYGTextView? {
            didSet { textView?.adapterCoordinator = self }
        }
        weak var scrollView: NSScrollView?
        private var appliedSnapshotID: PresentationSnapshot.ID?

        init(document: MarkdownDocument, session: EditorSession, placementController: ImagePlacementController) {
            self.document = document
            self.session = session
            self.placementController = placementController
        }

        func applyProjectionIfNeeded(force: Bool) {
            guard let textView else { return }
            guard let presentation = session.presentation else {
                textView.isEditable = false
                return
            }
            let editable: Bool
            if case .editable(let id) = session.wysiwygModeState.availability, id == presentation.id {
                editable = true
            } else {
                editable = false
            }
            textView.isEditable = editable
            guard editable else { return }
            guard force || appliedSnapshotID != presentation.id else { return }
            // Never replace storage during marked text.
            if textView.hasMarkedText() || input.composition.isComposing { return }

            session.updateOrigin.with(.programmaticPresentation) {
                let built = RichTextBuilder.build(
                    model: presentation.asProjectionModel,
                    theme: MarkdownTheme(),
                    images: session.resolvedImages,
                    openURL: session.openURL,
                    onTaskPress: { [weak self] nodeID in
                        self?.performTaskToggle(nodeID: nodeID)
                    }
                )
                textView.textStorage?.setAttributedString(built.attributed)
                appliedSnapshotID = presentation.id

                if let selection = session.wysiwygModeState.selection,
                   selection.range.revision.snapshotID == presentation.id {
                    let range = selection.range.utf16
                    precondition(
                        range.location >= 0 && NSMaxRange(range) <= built.attributed.length,
                        "Current typed selection is outside its presentation snapshot"
                    )
                    textView.setSelectedRange(range)
                }
            }
        }

        func hasAppliedSnapshot(_ id: PresentationSnapshot.ID) -> Bool {
            appliedSnapshotID == id
        }

        func textView(
            _ textView: NSTextView,
            shouldChangeTextIn affectedCharRange: NSRange,
            replacementString: String?
        ) -> Bool {
            if session.updateOrigin.current != .nativeUserInput { return true }
            // Attribute-only changes (nil replacement) stay native.
            guard let replacement = replacementString else { return true }

            // REQ-084: marked-text / IME updates stay transient until composition completes.
            if input.committingComposition || input.allowingMarkedText || textView.hasMarkedText() || input.composition.isComposing {
                return true
            }

            guard let presentation = session.presentation,
                  case .editable(let id) = session.wysiwygModeState.availability,
                  id == presentation.id,
                  appliedSnapshotID == presentation.id,
                  textView.string == presentation.renderedString,
                  affectedCharRange.location >= 0,
                  NSMaxRange(affectedCharRange) <= (presentation.renderedString as NSString).length
            else {
                applyProjectionIfNeeded(force: true)
                return false
            }

            let projectionSelection = ProjectionSelection(
                utf16: affectedCharRange,
                revision: presentation.projectionRevision,
                affinity: textView.selectionAffinity == .upstream ? .upstream : .downstream
            )
            let command: SemanticCommand
            if replacement.isEmpty && affectedCharRange.length > 0 {
                command = .insertText("")
            } else if replacement.isEmpty {
                command = .deleteBackward
            } else {
                command = .insertText(replacement)
            }
            let outcome = session.perform(
                command,
                selection: .projection(projectionSelection),
                expectedSourceRevision: SourceRevision(value: document.sourceVersion)
            )
            switch outcome {
            case .accepted(let edit):
                // REQ-091; ARC-005: apply the accepted presentation transition programmatically
                // and refuse TextKit's optimistic second mutation.
                applyAcceptedEdit(edit, in: textView)
                return false
            case .refused:
                return false
            }
        }

        func applyAcceptedEdit(_ edit: AcceptedEdit, in textView: NSTextView) {
            guard let transition = edit.presentationTransition else {
                preconditionFailure("Accepted WYSIWYG edit must carry a presentation transition")
            }
            session.updateOrigin.with(.programmaticPresentation) {
                applyAcceptedTransition(transition, in: textView)
                appliedSnapshotID = transition.nextSnapshot.id
            }
        }

        private func applyAcceptedTransition(_ transition: PresentationTransition, in textView: NSTextView) {
            guard let storage = textView.textStorage else { return }
            let range = transition.projectionReplacementRange
            precondition(
                range.location >= 0 && NSMaxRange(range) <= storage.length,
                "Validated presentation transition no longer matches applied TextKit storage"
            )

            if range == NSRange(location: 0, length: storage.length),
               transition.projectionReplacement == transition.nextSnapshot.renderedString {
                let built = RichTextBuilder.build(
                    model: transition.nextSnapshot.asProjectionModel,
                    theme: MarkdownTheme(),
                    images: session.resolvedImages,
                    openURL: session.openURL,
                    onTaskPress: { [weak self] nodeID in
                        self?.performTaskToggle(nodeID: nodeID)
                    }
                )
                storage.setAttributedString(built.attributed)
            } else {
                storage.replaceCharacters(in: range, with: transition.projectionReplacement)
                // Re-apply styles for the affected snapshot when possible via full rebuild for safety.
                let built = RichTextBuilder.build(
                    model: transition.nextSnapshot.asProjectionModel,
                    theme: MarkdownTheme(),
                    images: session.resolvedImages,
                    openURL: session.openURL,
                    onTaskPress: { [weak self] nodeID in
                        self?.performTaskToggle(nodeID: nodeID)
                    }
                )
                storage.setAttributedString(built.attributed)
            }
            textView.setSelectedRange(transition.selectionAfter.range.utf16)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView else { return }
            // REQ-094; ARC-013/015: a programmatic set is restoring a value the session already
            // holds. Writing it back turns restoration into a state change and, when the set
            // happens during reconciliation, into a self-feeding update loop.
            guard session.updateOrigin.current == .nativeUserInput else { return }
            let range = textView.selectedRange()
            if let presentation = session.presentation,
               case .editable(let id) = session.wysiwygModeState.availability,
               id == presentation.id,
               appliedSnapshotID == presentation.id,
               textView.string == presentation.renderedString,
               range.location >= 0,
               NSMaxRange(range) <= (presentation.renderedString as NSString).length {
                session.updateWYSIWYGModeState { state in
                    state.selection = ProjectionSelection(
                        utf16: range,
                        revision: presentation.projectionRevision,
                        affinity: textView.selectionAffinity == .upstream ? .upstream : .downstream
                    )
                }
            }
            // Close typing groups on real native caret moves.
            document.closeTypingUndoGroup()
        }

        func performTaskToggle(nodeID: MarkdownNodeID) {
            guard let presentation = session.presentation,
                  let attachment = presentation.attachments.first(where: { $0.nodeID == nodeID }) else {
                return
            }
            let selection = ProjectionSelection(
                utf16: NSRange(location: attachment.utf16Location, length: 1),
                revision: presentation.projectionRevision
            )
            _ = session.perform(
                .toggleTask(nodeID: nodeID),
                selection: .projection(selection),
                expectedSourceRevision: presentation.sourceRevision
            )
            applyProjectionIfNeeded(force: true)
        }

        // REQ-079: open any URL via injected opener — do not restrict schemes.
        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            let url: URL?
            if let u = link as? URL {
                url = u
            } else if let s = link as? String {
                url = URL(string: s)
            } else {
                url = nil
            }
            guard let url else { return false }
            session.openURL(url)
            return true
        }
    }
}

@MainActor
final class MarkdownWYSIWYGTextView: NSTextView {
    weak var session: EditorSession?
    weak var documentActions: DocumentActionInterface?
    weak var placementController: ImagePlacementController?
    weak var inputCoordinator: WYSIWYGTextView.WYSIWYGInputCoordinator?
    weak var adapterCoordinator: WYSIWYGTextView.Coordinator?

    override var undoManager: UndoManager? {
        documentActions?.documentUndoManager ?? super.undoManager
    }

    // MARK: - IME / marked text (REQ-084)

    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        let version = documentActions?.sourceSnapshot().sourceVersion ?? 0
        let sourceRange = replacementRange.location == NSNotFound ? self.selectedRange() : replacementRange
        let markedLength: Int
        if let attributed = string as? NSAttributedString {
            markedLength = attributed.length
        } else if let text = string as? String {
            markedLength = (text as NSString).length
        } else {
            markedLength = 0
        }
        inputCoordinator?.beginMarkedText(
            sourceVersion: version,
            sourceRange: sourceRange,
            marked: NSRange(location: sourceRange.location, length: markedLength),
            snapshotID: session?.presentation?.id
        )
        inputCoordinator?.allowingMarkedText = true
        if let session {
            session.updateOrigin.with(.composition) {
                super.setMarkedText(
                    string,
                    selectedRange: selectedRange,
                    replacementRange: replacementRange
                )
            }
        } else {
            super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
        }
        inputCoordinator?.allowingMarkedText = false
        (documentActions as? MarkdownDocument)?.trace?.record(.compositionBegan(sourceVersion: version))
    }

    override func unmarkText() {
        // Some IMEs finish composition via unmarkText rather than insertText. Commit the
        // marked characters to source before clearing composition state; empty marked text
        // (Escape / cancel) still cancels without a source write.
        if let input = inputCoordinator, input.committingComposition {
            performNativeUnmark()
            return
        }
        if let input = inputCoordinator, input.composition.isComposing || hasMarkedText() {
            let marked = markedRange()
            let text: String
            if marked.location != NSNotFound, let storage = textStorage {
                guard marked.location >= 0, NSMaxRange(marked) <= storage.length else {
                    input.cancel()
                    performNativeUnmark()
                    (documentActions as? MarkdownDocument)?.trace?.record(.compositionCancelled)
                    return
                }
                text = (storage.string as NSString).substring(with: marked)
            } else {
                text = ""
            }
            if text.isEmpty {
                input.cancel()
                performNativeUnmark()
                (documentActions as? MarkdownDocument)?.trace?.record(.compositionCancelled)
                return
            }
            let currentVersion = documentActions?.sourceSnapshot().sourceVersion ?? 0
            guard input.prepareCommit(currentVersion: currentVersion),
                  let captured = input.complete() else {
                input.cancel()
                performNativeUnmark()
                (documentActions as? MarkdownDocument)?.trace?.record(.compositionCancelled)
                return
            }
            guard let session,
                  let presentation = session.presentation,
                  let capturedSnapshotID = captured.snapshotID,
                  presentation.id == capturedSnapshotID,
                  adapterCoordinator?.hasAppliedSnapshot(capturedSnapshotID) == true else {
                input.cancel()
                performNativeUnmark()
                (documentActions as? MarkdownDocument)?.trace?.record(.compositionCancelled)
                return
            }
            let selection = ProjectionSelection(
                utf16: captured.range,
                revision: presentation.projectionRevision
            )
            let result = session.perform(
                .insertText(text),
                selection: .projection(selection),
                expectedSourceRevision: SourceRevision(value: captured.version)
            )
            (documentActions as? MarkdownDocument)?.trace?.record(
                .compositionCommitted(sourceVersion: captured.version, replacementLength: (text as NSString).length)
            )
            switch result {
            case .accepted:
                input.committingComposition = true
                input.allowingMarkedText = true
                performNativeUnmark()
                input.allowingMarkedText = false
                input.committingComposition = false
                adapterCoordinator?.applyProjectionIfNeeded(force: true)
            case .refused:
                input.cancel()
                performNativeUnmark()
                (documentActions as? MarkdownDocument)?.trace?.record(.compositionCancelled)
            }
            return
        }
        inputCoordinator?.cancel()
        performNativeUnmark()
        (documentActions as? MarkdownDocument)?.trace?.record(.compositionCancelled)
    }

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        let text: String
        if let attributed = insertString as? NSAttributedString {
            text = attributed.string
        } else if let string = insertString as? String {
            text = string
        } else {
            super.insertText(insertString, replacementRange: replacementRange)
            return
        }

        // Space on a task checkbox toggles rather than inserting.
        if text == " ", toggleTaskAtSelection() {
            return
        }

        guard let input = inputCoordinator, input.composition.isComposing || hasMarkedText() else {
            super.insertText(insertString, replacementRange: replacementRange)
            return
        }

        let currentVersion = documentActions?.sourceSnapshot().sourceVersion ?? 0
        guard input.prepareCommit(currentVersion: currentVersion) else {
            input.cancel()
            unmarkText()
            (documentActions as? MarkdownDocument)?.trace?.record(.compositionRefusedStale)
            return
        }
        guard let captured = input.complete() else {
            input.cancel()
            return
        }

        guard let session,
              let presentation = session.presentation,
              let capturedSnapshotID = captured.snapshotID,
              presentation.id == capturedSnapshotID,
              adapterCoordinator?.hasAppliedSnapshot(capturedSnapshotID) == true else {
            input.cancel()
            return
        }
        let selection = ProjectionSelection(
            utf16: captured.range,
            revision: presentation.projectionRevision
        )
        let result = session.perform(
            .insertText(text),
            selection: .projection(selection),
            expectedSourceRevision: SourceRevision(value: captured.version)
        )
        (documentActions as? MarkdownDocument)?.trace?.record(
            .compositionCommitted(sourceVersion: captured.version, replacementLength: (text as NSString).length)
        )
        switch result {
        case .accepted:
            input.committingComposition = true
            input.allowingMarkedText = true
            if hasMarkedText() {
                performNativeUnmark()
            }
            input.allowingMarkedText = false
            input.committingComposition = false
            adapterCoordinator?.applyProjectionIfNeeded(force: true)
        case .refused:
            input.cancel()
            unmarkText()
        }
    }

    private func performNativeUnmark() {
        if let session {
            session.updateOrigin.with(.composition) {
                super.unmarkText()
            }
        } else {
            super.unmarkText()
        }
    }

    // MARK: - Task checkbox: mouse, Space, Return, accessibility (REQ-078/032/084)

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let index = characterIndexForAttachment(at: point), toggleTask(atUTF16: index) {
            return
        }
        super.mouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        // Return / keypad Enter on a task checkbox.
        if event.keyCode == 36 || event.keyCode == 76 {
            if toggleTaskAtSelection() { return }
        }
        super.keyDown(with: event)
    }

    override func doCommand(by selector: Selector) {
        if selector == #selector(insertNewline(_:))
            || selector == #selector(insertNewlineIgnoringFieldEditor(_:)) {
            if toggleTaskAtSelection() { return }
        }
        super.doCommand(by: selector)
    }

    override func accessibilityPerformPress() -> Bool {
        if toggleTaskAtSelection() { return true }
        return super.accessibilityPerformPress()
    }

    @discardableResult
    func toggleTaskAtSelection() -> Bool {
        let range = selectedRange()
        guard range.length <= 1 else { return false }
        return toggleTask(atUTF16: range.location)
    }

    @discardableResult
    func toggleTask(atUTF16 index: Int) -> Bool {
        guard let session,
              let presentation = session.presentation,
              let attachment = presentation.attachments.first(where: { $0.utf16Location == index }),
              case .task = attachment.kind else {
            return false
        }
        let selection = ProjectionSelection(
            utf16: NSRange(location: index, length: 1),
            revision: presentation.projectionRevision
        )
        let result = session.perform(
            .toggleTask(nodeID: attachment.nodeID),
            selection: .projection(selection),
            expectedSourceRevision: presentation.sourceRevision
        )
        if case .accepted = result { return true }
        return false
    }

    private func characterIndexForAttachment(at point: NSPoint) -> Int? {
        guard let layoutManager, let textContainer else { return nil }
        return layoutManager.characterIndex(
            for: point,
            in: textContainer,
            fractionOfDistanceBetweenInsertionPoints: nil
        )
    }

    // MARK: - Paste / drag

    /// Resolve the live WYSIWYG selection to an immutable source-domain placement intent.
    ///
    /// // REQ-060; ARC-012: capture before asynchronous paste/drop work.
    private func imagePlacementTarget() -> ImagePlacementTarget? {
        guard let actions = documentActions,
              let session,
              let presentation = session.presentation,
              case .editable(let id) = session.wysiwygModeState.availability,
              id == presentation.id else {
            return nil
        }
        let snapshot = actions.sourceSnapshot()
        guard presentation.sourceRevision.value == snapshot.sourceVersion else { return nil }
        switch presentation.coordinateMap.sourceRange(
            forProjection: selectedRange(),
            affinity: selectionAffinity == .upstream ? .upstream : .downstream
        ) {
        case .exact(let sourceRange):
            return ImagePlacementTarget(
                sourceSelection: SourceSelection(
                    utf16: sourceRange,
                    affinity: selectionAffinity == .upstream ? .upstream : .downstream
                ),
                sourceRevision: SourceRevision(value: snapshot.sourceVersion),
                locationGeneration: snapshot.locationGeneration,
                operationID: UUID()
            )
        case .refused:
            return nil
        }
    }

    override func paste(_ sender: Any?) {
        let classification = ImagePasteboardClassifier.classifyPasteboard(.general)
        switch classification {
        case .images(let claims):
            guard let target = imagePlacementTarget() else {
                placementController?.alert = .error("Could not resolve image insertion point.")
                return
            }
            placementController?.handleImageAction(
                intent: ImagePlacementIntent(target: target, claims: claims),
                documentURL: documentActions?.sourceSnapshot().fileURL
            )
        case .fallthroughToNativeText, .unsupported:
            if case .unsupported = classification {
                placementController?.alert = .error("Unsupported or corrupt image.")
                return
            }
            // REQ-059: always paste plain text even when RTF/HTML are available.
            if let plain = PastePolicy.plainText(from: .general) {
                _ = pastePlainText(plain)
            }
        }
    }

    /// Apply plain-text paste as the same atomic source/presentation transaction as typing.
    ///
    /// Exposed to integration tests so paste behavior is verified without UI automation.
    @discardableResult
    func pastePlainText(_ plain: String) -> Bool {
        guard let session,
              let presentation = session.presentation,
              let adapterCoordinator,
              let snapshot = documentActions?.sourceSnapshot(),
              presentation.sourceRevision.value == snapshot.sourceVersion else {
            return false
        }
        let selection = ProjectionSelection(
            utf16: selectedRange(),
            revision: presentation.projectionRevision,
            affinity: selectionAffinity == .upstream ? .upstream : .downstream
        )
        // Paste must not coalesce into an open typing undo group (REQ-016).
        let outcome = session.perform(
            .insertText(plain),
            selection: .projection(selection),
            expectedSourceRevision: SourceRevision(value: snapshot.sourceVersion),
            grouping: .discrete
        )
        guard case .accepted(let edit) = outcome else { return false }
        adapterCoordinator.applyAcceptedEdit(edit, in: self)
        return true
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pb = sender.draggingPasteboard
        let url = documentActions?.sourceSnapshot().fileURL
        if let receivers = pb.readObjects(forClasses: [NSFilePromiseReceiver.self], options: nil) as? [NSFilePromiseReceiver],
           !receivers.isEmpty {
            guard let target = imagePlacementTarget() else { return false }
            placementController?.handleFilePromises(receivers, target: target, documentURL: url)
            return true
        }
        let classification = ImagePasteboardClassifier.classifyDragInfo(sender)
        switch classification {
        case .images(let claims):
            guard let target = imagePlacementTarget() else { return false }
            placementController?.handleImageAction(
                intent: ImagePlacementIntent(target: target, claims: claims),
                documentURL: url
            )
            return true
        case .fallthroughToNativeText, .unsupported:
            if case .unsupported = classification {
                placementController?.alert = .error("Unsupported or corrupt image.")
                return true
            }
            return super.performDragOperation(sender)
        }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let pb = sender.draggingPasteboard
        if let receivers = pb.readObjects(forClasses: [NSFilePromiseReceiver.self], options: nil) as? [NSFilePromiseReceiver],
           !receivers.isEmpty {
            return .copy
        }
        if case .images = ImagePasteboardClassifier.classifyDragInfo(sender) {
            return .copy
        }
        return super.draggingEntered(sender)
    }
}
