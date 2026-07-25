//
//  MarkdownTextView.swift
//  Markdown Editor
//

import SwiftUI
import AppKit

// REQ-010/011/012/040/046/060–077: live-styled source editor with paste/drop image placement.
// REQ-016: reports exact SourceEdit transactions; document owns undo.
struct MarkdownTextView: NSViewRepresentable {
    @ObservedObject var document: MarkdownDocument
    var placementController: ImagePlacementController
    var session: EditorSession?

    func makeCoordinator() -> Coordinator {
        Coordinator(document: document, placementController: placementController, session: session)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = MarkdownSourceTextView(usingTextLayoutManager: false)
        textView.delegate = context.coordinator
        textView.placementController = placementController
        textView.documentActions = document
        textView.isRichText = false
        // Document owns undo; text view routes UndoManager to the document (REQ-011/016).
        textView.allowsUndo = false
        textView.font = context.coordinator.theme.baseFont
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.usesFindBar = true                         // REQ-046
        textView.isIncrementalSearchingEnabled = true
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.string = document.text
        // REQ-060: register all file-promise drag types AppKit may deliver.
        var dragTypes: [NSPasteboard.PasteboardType] = [.fileURL, .png, .tiff]
        dragTypes.append(contentsOf: FilePromiseBridge.readableDraggedTypes)
        textView.registerForDraggedTypes(dragTypes)
        textView.setAccessibilityLabel("Markdown source")

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.documentView = textView

        context.coordinator.session = session
        context.coordinator.textView = textView
        placementController.attach(actions: document)
        placementController.updateDocumentURL(document.fileURL)
        context.coordinator.highlight()
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? MarkdownSourceTextView else { return }
        context.coordinator.document = document
        context.coordinator.session = session
        textView.placementController = placementController
        textView.documentActions = document
        textView.documentURL = document.fileURL
        placementController.attach(actions: document)
        placementController.updateDocumentURL(document.fileURL)

        if context.coordinator.isNativeEditInFlight {
            // Native keystroke owns storage application until textDidChange clears the gate.
            if let pending = document.pendingSelection {
                textView.setSelectedRange(pending)
                document.pendingSelection = nil
                document.reportActiveSelection(pending)
            }
            return
        }

        if textView.string != document.text {
            context.coordinator.isProgrammaticUpdate = true
            let selected = textView.selectedRange()
            textView.string = document.text
            if let pending = document.pendingSelection {
                textView.setSelectedRange(pending)
                document.pendingSelection = nil
                document.reportActiveSelection(pending)
            } else {
                let length = (document.text as NSString).length
                let loc = min(selected.location, length)
                let maxLen = length - loc
                let len = min(selected.length, maxLen)
                textView.setSelectedRange(NSRange(location: loc, length: len))
            }
            context.coordinator.isProgrammaticUpdate = false
            context.coordinator.highlight()
        } else if let pending = document.pendingSelection {
            textView.setSelectedRange(pending)
            document.pendingSelection = nil
            document.reportActiveSelection(pending)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var document: MarkdownDocument
        var session: EditorSession?
        let theme = MarkdownTheme()
        let placementController: ImagePlacementController
        private let highlighter = MarkdownHighlighter()
        weak var textView: MarkdownSourceTextView?
        var isProgrammaticUpdate = false
        /// Gates SwiftUI string sync while a native keystroke commit is in flight (REQ-016).
        var isNativeEditInFlight = false
        private var version = 0
        private var task: Task<Void, Never>?

        init(document: MarkdownDocument, placementController: ImagePlacementController, session: EditorSession?) {
            self.document = document
            self.placementController = placementController
            self.session = session
        }

        func textView(
            _ textView: NSTextView,
            shouldChangeTextIn affectedCharRange: NSRange,
            replacementString: String?
        ) -> Bool {
            guard !isProgrammaticUpdate else { return true }
            // Attribute-only or marked-text updates may omit a replacement string.
            guard let replacement = replacementString else { return true }
            let edit = SourceEdit(
                expectedVersion: document.sourceVersion,
                range: affectedCharRange,
                replacement: replacement,
                actionName: "Typing"
            )
            switch document.commitSourceEdit(edit) {
            case .committed(let selection):
                document.reportActiveSelection(selection.range)
                // Prevent updateNSView from rewriting storage before the text view applies
                // the same replacement (PLAN-0008 recursive-writeback risk).
                isNativeEditInFlight = true
                return true
            case .refused:
                return false
            }
        }

        func textDidChange(_ notification: Notification) {
            guard !isProgrammaticUpdate, let textView else { return }
            isNativeEditInFlight = false
            // Canonical source already updated in shouldChangeTextIn via transaction.
            document.reportActiveSelection(textView.selectedRange())
            highlight(debounced: true)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView else { return }
            let range = textView.selectedRange()
            document.reportActiveSelection(range)
            if var session {
                var state = session.sourceViewState
                state.selection = range
                session.sourceViewState = state
            }
        }

        // REQ-045: debounce + off-main highlight; no document-size styling suspension.
        func highlight(debounced: Bool = false) {
            guard let textView else { return }
            version &+= 1
            let expectedVersion = version
            let snapshot = textView.string
            task?.cancel()

            task = Task { [weak self] in
                if debounced {
                    try? await Task.sleep(for: .milliseconds(120))
                    if Task.isCancelled { return }
                }
                guard let self else { return }
                let tokens: [Token]
                do {
                    tokens = try await self.highlighter.tokens(for: snapshot)
                } catch {
                    return
                }
                if Task.isCancelled { return }
                self.apply(tokens, expectedVersion: expectedVersion, expectedText: snapshot)
            }
        }

        // REQ-040/041/043/047–051: style via NSTextStorage attributes — display only.
        private func apply(_ tokens: [Token], expectedVersion: Int, expectedText: String) {
            guard expectedVersion == version,
                  let textView, textView.string == expectedText,
                  let storage = textView.textStorage else { return }
            let full = NSRange(location: 0, length: storage.length)
            storage.beginEditing()
            storage.setAttributes(theme.baseAttributes, range: full)
            for token in tokens where NSMaxRange(token.range) <= full.length {
                storage.addAttributes(theme.attributes(for: token.style), range: token.range)
            }
            storage.endEditing()
        }
    }
}

// REQ-060/064: narrow AppKit adapter — intercept image paste/drop; otherwise native.
@MainActor
final class MarkdownSourceTextView: NSTextView {
    weak var placementController: ImagePlacementController?
    weak var documentActions: DocumentActionInterface?
    var documentURL: URL?

    /// Prefer the document-owned undo manager so Edit ▸ Undo reaches source transactions.
    override var undoManager: UndoManager? {
        documentActions?.documentUndoManager ?? super.undoManager
    }

    // REQ-060/064: one undoable replacement via document transaction; select empty description.
    func insertImageMarkdown(_ markdown: String, at range: NSRange, selectEmptyDescription: Bool) {
        guard let actions = documentActions else { return }
        let snapshot = actions.sourceSnapshot()
        let safe = NSIntersectionRange(range, NSRange(location: 0, length: (snapshot.text as NSString).length))
        let edit = SourceEdit(
            expectedVersion: snapshot.sourceVersion,
            range: safe,
            replacement: markdown,
            actionName: "Insert Image"
        )
        switch actions.commitSourceEdit(edit) {
        case .committed:
            if selectEmptyDescription {
                let descStart = safe.location + 2
                let pending = NSRange(location: descStart, length: 0)
                actions.pendingSelection = pending
                actions.reportActiveSelection(pending)
            } else {
                let end = safe.location + (markdown as NSString).length
                let pending = NSRange(location: end, length: 0)
                actions.pendingSelection = pending
                actions.reportActiveSelection(pending)
            }
        case .refused:
            break
        }
    }

    override func paste(_ sender: Any?) {
        let classification = ImagePasteboardClassifier.classifyPasteboard(.general)
        switch classification {
        case .images(let claims):
            placementController?.handleImageAction(
                claims: claims,
                documentURL: documentActions?.sourceSnapshot().fileURL ?? documentURL
            )
            case .fallthroughToNativeText, .unsupported:
            if case .unsupported = classification {
                placementController?.alert = .error("Unsupported or corrupt image.")
                return
            }
            // REQ-059: prefer plain-text representation even when RTF/HTML is present.
            if let plain = PastePolicy.plainText(from: .general) {
                let range = selectedRange()
                insertText(plain, replacementRange: range)
            } else {
                super.pasteAsPlainText(sender)
            }
        }
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pb = sender.draggingPasteboard
        let url = documentActions?.sourceSnapshot().fileURL ?? documentURL
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
        let classification = ImagePasteboardClassifier.classifyDragInfo(sender)
        if case .images = classification {
            return .copy
        }
        return super.draggingEntered(sender)
    }
}
