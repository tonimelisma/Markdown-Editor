//
//  WYSIWYGTextView.swift
//  Markdown Editor
//

import AppKit
import SwiftUI

/// TextKit 1 WYSIWYG adapter — delimiter-free rich storage; edits become source transactions.
///
/// // REQ-052/054–059/078–084/086: rich projection host; tasks/links; plain paste; accessibility.
struct WYSIWYGTextView: NSViewRepresentable {
    @ObservedObject var document: MarkdownDocument
    @ObservedObject var session: EditorSession
    var placementController: ImagePlacementController

    func makeCoordinator() -> Coordinator {
        Coordinator(document: document, session: session, placementController: placementController)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = MarkdownWYSIWYGTextView(usingTextLayoutManager: false)
        textView.delegate = context.coordinator
        textView.inputCoordinator = context.coordinator.input
        textView.session = session
        textView.documentActions = document
        textView.placementController = placementController
        textView.isRichText = true
        textView.allowsUndo = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.setAccessibilityLabel("Markdown WYSIWYG")
        // REQ-079: allow link clicks — all URLs open via injected opener (no scheme allowlist).
        textView.isEditable = true
        textView.isSelectable = true

        var dragTypes: [NSPasteboard.PasteboardType] = [.fileURL, .png, .tiff]
        dragTypes.append(contentsOf: FilePromiseBridge.readableDraggedTypes)
        textView.registerForDraggedTypes(dragTypes)

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.scrollView = scroll
        context.coordinator.applyProjectionIfNeeded(force: true)
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.document = document
        context.coordinator.session = session
        guard let textView = nsView.documentView as? MarkdownWYSIWYGTextView else { return }
        textView.session = session
        textView.documentActions = document
        textView.placementController = placementController
        textView.inputCoordinator = context.coordinator.input
        if !context.coordinator.isNativeEditInFlight {
            context.coordinator.applyProjectionIfNeeded(force: false)
        }
        if let pending = document.pendingSelection, session.mode == .wysiwyg {
            let length = textView.string.utf16.count
            let loc = min(pending.nsRange.location, length)
            let len = min(pending.nsRange.length, max(0, length - loc))
            textView.setSelectedRange(NSRange(location: loc, length: len))
            document.pendingSelection = nil
        }
    }

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

        func beginMarkedText(sourceVersion: UInt64, sourceRange: NSRange, marked: NSRange) {
            if composition.isComposing {
                composition.update(marked: marked)
            } else {
                composition.begin(sourceVersion: sourceVersion, sourceRange: sourceRange, marked: marked)
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

        func complete() -> (version: UInt64, range: NSRange)? {
            composition.complete()
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var document: MarkdownDocument
        var session: EditorSession
        let placementController: ImagePlacementController
        let input = WYSIWYGInputCoordinator()
        weak var textView: MarkdownWYSIWYGTextView?
        weak var scrollView: NSScrollView?
        var isProgrammaticUpdate = false
        var isNativeEditInFlight = false
        private var appliedVersion: UInt64 = .max

        init(document: MarkdownDocument, session: EditorSession, placementController: ImagePlacementController) {
            self.document = document
            self.session = session
            self.placementController = placementController
        }

        func applyProjectionIfNeeded(force: Bool) {
            guard let textView, let projection = session.projection else { return }
            guard force || projection.sourceVersion != appliedVersion else { return }
            // Never replace storage during marked text.
            if textView.hasMarkedText() || input.composition.isComposing { return }

            isProgrammaticUpdate = true
            let built = RichTextBuilder.build(
                model: projection,
                theme: MarkdownTheme(),
                images: session.resolvedImages,
                openURL: session.openURL,
                onTaskPress: { [weak self] nodeID in
                    self?.performTaskToggle(nodeID: nodeID)
                }
            )
            let selected = textView.selectedRange()
            textView.textStorage?.setAttributedString(built.attributed)
            appliedVersion = projection.sourceVersion

            // Restore logical selection when possible.
            let length = built.attributed.length
            let loc = min(selected.location, length)
            let len = min(selected.length, max(0, length - loc))
            textView.setSelectedRange(NSRange(location: loc, length: len))
            isProgrammaticUpdate = false
        }

        func textView(
            _ textView: NSTextView,
            shouldChangeTextIn affectedCharRange: NSRange,
            replacementString: String?
        ) -> Bool {
            guard !isProgrammaticUpdate else { return true }
            // Attribute-only changes (nil replacement) stay native.
            guard let replacement = replacementString else { return true }

            // REQ-084: marked-text / IME updates stay transient until composition completes.
            if input.committingComposition || input.allowingMarkedText || textView.hasMarkedText() || input.composition.isComposing {
                return true
            }

            let selection = SemanticSelection(
                mode: .wysiwyg,
                utf16Range: affectedCharRange,
                sourceVersion: document.sourceVersion
            )
            let result: SemanticEditResult
            if replacement.isEmpty && affectedCharRange.length > 0 {
                result = session.perform(.insertText(""), selection: selection)
            } else if replacement.isEmpty {
                result = session.perform(.deleteBackward, selection: selection)
            } else {
                result = session.perform(.insertText(replacement), selection: selection)
            }
            switch result {
            case .mutation:
                isNativeEditInFlight = true
                // Allow optimistic native mutation; projection refresh replaces storage when ready.
                return true
            case .refused:
                return false
            }
        }

        func textDidChange(_ notification: Notification) {
            isNativeEditInFlight = false
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView else { return }
            let range = textView.selectedRange()
            var state = session.wysiwygViewState
            state.selection = range
            state.affinity = textView.selectionAffinity == .upstream ? .upstream : .downstream
            session.wysiwygViewState = state
            // Close typing groups on caret moves; skip selection churn from in-flight typing.
            if !isNativeEditInFlight {
                document.closeTypingUndoGroup()
            }
            // COR-08 D2: never store projection coordinates as document source selection.
            // Image intent resolves through EditorSelectionIntent + coordinate map.
        }

        func performTaskToggle(nodeID: MarkdownNodeID) {
            guard let attachment = session.projection?.attachments.first(where: { $0.nodeID == nodeID }) else {
                return
            }
            let selection = SemanticSelection(
                mode: .wysiwyg,
                utf16Range: NSRange(location: attachment.utf16Location, length: 1),
                sourceVersion: session.acceptedSourceVersion
            )
            _ = session.perform(.toggleTask(nodeID: nodeID), selection: selection)
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
            marked: NSRange(location: sourceRange.location, length: markedLength)
        )
        inputCoordinator?.allowingMarkedText = true
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
        inputCoordinator?.allowingMarkedText = false
        (documentActions as? MarkdownDocument)?.trace?.record(.compositionBegan(sourceVersion: version))
    }

    override func unmarkText() {
        // Some IMEs finish composition via unmarkText rather than insertText. Commit the
        // marked characters to source before clearing composition state; empty marked text
        // (Escape / cancel) still cancels without a source write.
        if let input = inputCoordinator, input.committingComposition {
            super.unmarkText()
            return
        }
        if let input = inputCoordinator, input.composition.isComposing || hasMarkedText() {
            let marked = markedRange()
            let text: String
            if marked.location != NSNotFound, let storage = textStorage {
                let safeLoc = min(max(0, marked.location), storage.length)
                let safeLen = min(max(0, marked.length), max(0, storage.length - safeLoc))
                text = (storage.string as NSString).substring(with: NSRange(location: safeLoc, length: safeLen))
            } else {
                text = ""
            }
            if text.isEmpty {
                input.cancel()
                super.unmarkText()
                (documentActions as? MarkdownDocument)?.trace?.record(.compositionCancelled)
                return
            }
            let currentVersion = documentActions?.sourceSnapshot().sourceVersion ?? 0
            guard input.prepareCommit(currentVersion: currentVersion),
                  let captured = input.complete() else {
                input.cancel()
                super.unmarkText()
                (documentActions as? MarkdownDocument)?.trace?.record(.compositionCancelled)
                return
            }
            let selection = SemanticSelection(
                mode: .wysiwyg,
                utf16Range: captured.range,
                sourceVersion: captured.version
            )
            let result = session?.perform(.insertText(text), selection: selection)
            (documentActions as? MarkdownDocument)?.trace?.record(
                .compositionCommitted(sourceVersion: captured.version, replacementLength: (text as NSString).length)
            )
            switch result {
            case .mutation:
                input.committingComposition = true
                input.allowingMarkedText = true
                super.unmarkText()
                input.allowingMarkedText = false
                input.committingComposition = false
            case .refused, .none:
                input.cancel()
                super.unmarkText()
                (documentActions as? MarkdownDocument)?.trace?.record(.compositionCancelled)
            }
            return
        }
        inputCoordinator?.cancel()
        super.unmarkText()
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

        let selection = SemanticSelection(
            mode: .wysiwyg,
            utf16Range: captured.range,
            sourceVersion: captured.version
        )
        let result = session?.perform(.insertText(text), selection: selection)
        (documentActions as? MarkdownDocument)?.trace?.record(
            .compositionCommitted(sourceVersion: captured.version, replacementLength: (text as NSString).length)
        )
        switch result {
        case .mutation:
            // Apply final composition text directly — avoid nested NSTextView insertText/undo.
            input.committingComposition = true
            input.allowingMarkedText = true
            let marked = markedRange()
            let applyRange: NSRange
            if marked.location != NSNotFound {
                applyRange = marked
            } else {
                applyRange = captured.range
            }
            if let storage = textStorage {
                let safeLoc = min(max(0, applyRange.location), storage.length)
                let safeLen = min(max(0, applyRange.length), max(0, storage.length - safeLoc))
                storage.replaceCharacters(in: NSRange(location: safeLoc, length: safeLen), with: text)
                let caret = safeLoc + (text as NSString).length
                setSelectedRange(NSRange(location: min(caret, storage.length), length: 0))
            }
            if hasMarkedText() {
                super.unmarkText()
            }
            input.allowingMarkedText = false
            input.committingComposition = false
        case .refused, .none:
            input.cancel()
            unmarkText()
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
              let projection = session.projection,
              let attachment = projection.attachments.first(where: { $0.utf16Location == index }),
              case .task = attachment.kind else {
            return false
        }
        let selection = SemanticSelection(
            mode: .wysiwyg,
            utf16Range: NSRange(location: index, length: 1),
            sourceVersion: session.acceptedSourceVersion
        )
        let result = session.perform(.toggleTask(nodeID: attachment.nodeID), selection: selection)
        if case .mutation = result { return true }
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

    /// COR-08 D2: resolve the live WYSIWYG selection to source before COR-02 starts.
    private func resolveAndReportImageIntent() -> Bool {
        guard let actions = documentActions,
              let session,
              let projection = session.projection else {
            return false
        }
        let snapshot = actions.sourceSnapshot()
        let intent = EditorSelectionIntent(
            domain: .wysiwyg,
            sourceVersion: snapshot.sourceVersion,
            range: selectedRange(),
            affinity: selectionAffinity == .upstream ? .upstream : .downstream
        )
        switch intent.resolvedSourceRange(snapshot: snapshot, projection: projection) {
        case .exact(let sourceRange):
            actions.reportSourceSelection(
                SourceSelection(utf16: sourceRange, affinity: intent.affinity)
            )
            return true
        case .refused:
            return false
        }
    }

    override func paste(_ sender: Any?) {
        let classification = ImagePasteboardClassifier.classifyPasteboard(.general)
        switch classification {
        case .images(let claims):
            guard resolveAndReportImageIntent() else {
                placementController?.alert = .error("Could not resolve image insertion point.")
                return
            }
            placementController?.handleImageAction(
                claims: claims,
                documentURL: documentActions?.sourceSnapshot().fileURL
            )
        case .fallthroughToNativeText, .unsupported:
            if case .unsupported = classification {
                placementController?.alert = .error("Unsupported or corrupt image.")
                return
            }
            // REQ-059: always paste plain text even when RTF/HTML are available.
            if let plain = PastePolicy.plainText(from: .general) {
                let range = selectedRange()
                let selection = SemanticSelection(
                    mode: .wysiwyg,
                    utf16Range: range,
                    sourceVersion: documentActions?.sourceSnapshot().sourceVersion ?? 0
                )
                // Paste must not coalesce into an open typing undo group (REQ-016).
                _ = session?.perform(.insertText(plain), selection: selection, grouping: .discrete)
            }
        }
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pb = sender.draggingPasteboard
        let url = documentActions?.sourceSnapshot().fileURL
        if let receivers = pb.readObjects(forClasses: [NSFilePromiseReceiver.self], options: nil) as? [NSFilePromiseReceiver],
           !receivers.isEmpty {
            guard resolveAndReportImageIntent() else { return false }
            placementController?.handleFilePromises(receivers, documentURL: url)
            return true
        }
        let classification = ImagePasteboardClassifier.classifyDragInfo(sender)
        switch classification {
        case .images(let claims):
            guard resolveAndReportImageIntent() else { return false }
            placementController?.handleImageAction(claims: claims, documentURL: url)
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
