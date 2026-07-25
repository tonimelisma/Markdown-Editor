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
        if !context.coordinator.isNativeEditInFlight {
            context.coordinator.applyProjectionIfNeeded(force: false)
        }
        if let pending = document.pendingSelection, session.mode == .wysiwyg {
            let length = textView.string.utf16.count
            let loc = min(pending.location, length)
            let len = min(pending.length, max(0, length - loc))
            textView.setSelectedRange(NSRange(location: loc, length: len))
            document.pendingSelection = nil
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var document: MarkdownDocument
        var session: EditorSession
        let placementController: ImagePlacementController
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
            if textView.hasMarkedText() { return }

            isProgrammaticUpdate = true
            let built = RichTextBuilder.build(
                model: projection,
                theme: MarkdownTheme(),
                images: session.resolvedImages,
                openURL: session.openURL
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
            guard let replacement = replacementString else { return true }

            let selection = SemanticSelection(
                mode: .wysiwyg,
                utf16Range: affectedCharRange,
                sourceVersion: document.sourceVersion
            )
            let command: SemanticCommand = replacement.isEmpty ? .deleteBackward : .insertText(replacement)
            // For delete with selection, insertText("") is clearer:
            let result: SemanticEditResult
            if replacement.isEmpty && affectedCharRange.length > 0 {
                result = session.perform(.insertText(""), selection: selection)
            } else if replacement.isEmpty {
                result = session.perform(.deleteBackward, selection: selection)
            } else {
                result = session.perform(.insertText(replacement), selection: selection)
            }
            _ = command
            switch result {
            case .transaction:
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
            session.wysiwygViewState = state
            document.reportActiveSelection(range)
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

    override var undoManager: UndoManager? {
        documentActions?.documentUndoManager ?? super.undoManager
    }

    override func paste(_ sender: Any?) {
        let classification = ImagePasteboardClassifier.classifyPasteboard(.general)
        switch classification {
        case .images(let claims):
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
                _ = session?.perform(.insertText(plain), selection: selection)
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        // Task checkbox hit-testing: if click lands on a task attachment, toggle.
        let point = convert(event.locationInWindow, from: nil)
        if let layoutManager, let textContainer,
           let session,
           let projection = session.projection {
            let index = layoutManager.characterIndex(for: point, in: textContainer, fractionOfDistanceBetweenInsertionPoints: nil)
            if let attachment = projection.attachments.first(where: { $0.utf16Location == index }),
               case .task = attachment.kind {
                let selection = SemanticSelection(
                    mode: .wysiwyg,
                    utf16Range: NSRange(location: index, length: 1),
                    sourceVersion: session.acceptedSourceVersion
                )
                _ = session.perform(.toggleTask(nodeID: attachment.nodeID), selection: selection)
                return
            }
        }
        super.mouseDown(with: event)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pb = sender.draggingPasteboard
        let url = documentActions?.sourceSnapshot().fileURL
        if let receivers = pb.readObjects(forClasses: [NSFilePromiseReceiver.self], options: nil) as? [NSFilePromiseReceiver],
           !receivers.isEmpty {
            placementController?.handleFilePromises(receivers, documentURL: url)
            return true
        }
        let classification = ImagePasteboardClassifier.classifyDragInfo(sender)
        switch classification {
        case .images(let claims):
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
