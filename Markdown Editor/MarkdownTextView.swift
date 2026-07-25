//
//  MarkdownTextView.swift
//  Markdown Editor
//

import SwiftUI
import AppKit

// REQ-010/011/012/040/046/060–077: live-styled source editor with paste/drop image placement.
struct MarkdownTextView: NSViewRepresentable {
    @Binding var text: String
    var documentURL: URL?
    var placementController: ImagePlacementController

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, placementController: placementController)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = MarkdownSourceTextView(usingTextLayoutManager: false)
        textView.delegate = context.coordinator
        textView.placementController = placementController
        textView.isRichText = false
        textView.allowsUndo = true                          // REQ-011
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
        textView.string = text
        // REQ-060: register all file-promise drag types AppKit may deliver.
        var dragTypes: [NSPasteboard.PasteboardType] = [.fileURL, .png, .tiff]
        dragTypes.append(contentsOf: FilePromiseBridge.readableDraggedTypes)
        textView.registerForDraggedTypes(dragTypes)
        textView.setAccessibilityLabel("Markdown source")

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.documentView = textView

        context.coordinator.textView = textView
        placementController.attach(textView: textView)
        placementController.updateDocumentURL(documentURL)
        context.coordinator.highlight()
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? MarkdownSourceTextView else { return }
        textView.placementController = placementController
        textView.documentURL = documentURL
        placementController.updateDocumentURL(documentURL)
        if textView.string != text {
            context.coordinator.isProgrammaticUpdate = true
            textView.string = text
            context.coordinator.isProgrammaticUpdate = false
            context.coordinator.highlight()
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        let text: Binding<String>
        let theme = MarkdownTheme()
        let placementController: ImagePlacementController
        private let highlighter = MarkdownHighlighter()
        weak var textView: MarkdownSourceTextView?
        var isProgrammaticUpdate = false
        private var version = 0
        private var task: Task<Void, Never>?

        init(text: Binding<String>, placementController: ImagePlacementController) {
            self.text = text
            self.placementController = placementController
        }

        func textDidChange(_ notification: Notification) {
            guard !isProgrammaticUpdate, let textView else { return }
            text.wrappedValue = textView.string
            highlight(debounced: true)
        }

        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            let delta = (replacementString as NSString?)?.length ?? 0
            let change = delta - affectedCharRange.length
            if let source = textView as? MarkdownSourceTextView {
                source.noteEdit(edited: affectedCharRange, changeInLength: change)
            }
            return true
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
    var documentURL: URL?

    private var trackingGeneration = 0
    private var activeTracker: InsertionRangeTracker?
    private var activeGeneration: Int?

    var activeTrackingGeneration: Int { activeGeneration ?? 0 }

    func beginTrackingPlacement(range: NSRange) -> Int {
        trackingGeneration &+= 1
        activeTracker = InsertionRangeTracker(range: range)
        activeGeneration = trackingGeneration
        return trackingGeneration
    }

    func endTrackingPlacement(_ generation: Int) {
        if activeGeneration == generation {
            activeTracker = nil
            activeGeneration = nil
        }
    }

    func trackedPlacement(for generation: Int) -> InsertionRangeTracker? {
        guard activeGeneration == generation else { return nil }
        return activeTracker
    }

    func noteEdit(edited: NSRange, changeInLength delta: Int) {
        guard var tracker = activeTracker else { return }
        tracker.applyEdit(edited: edited, changeInLength: delta)
        activeTracker = tracker
    }

    // REQ-069/073/074: one undoable replacement; select empty description for a single image.
    func insertImageMarkdown(_ markdown: String, at range: NSRange, selectEmptyDescription: Bool) {
        guard let storage = textStorage else { return }
        let safe = NSIntersectionRange(range, NSRange(location: 0, length: storage.length))
        undoManager?.beginUndoGrouping()
        replaceCharacters(in: safe, with: markdown)
        undoManager?.endUndoGrouping()

        if selectEmptyDescription {
            let insertLocation = safe.location
            let descStart = insertLocation + 2
            if descStart <= (string as NSString).length {
                setSelectedRange(NSRange(location: descStart, length: 0))
            }
        } else {
            let end = safe.location + (markdown as NSString).length
            setSelectedRange(NSRange(location: end, length: 0))
        }
        didChangeText()
    }

    override func paste(_ sender: Any?) {
        let classification = ImagePasteboardClassifier.classifyPasteboard(.general)
        switch classification {
        case .images(let claims):
            placementController?.handleImageAction(claims: claims, documentURL: documentURL)
        case .fallthroughToNativeText, .unsupported:
            if case .unsupported = classification {
                placementController?.alert = .error("Unsupported or corrupt image.")
                return
            }
            super.pasteAsPlainText(sender)
        }
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pb = sender.draggingPasteboard
        if let receivers = pb.readObjects(forClasses: [NSFilePromiseReceiver.self], options: nil) as? [NSFilePromiseReceiver],
           !receivers.isEmpty {
            placementController?.handleFilePromises(receivers, documentURL: documentURL)
            return true
        }
        let classification = ImagePasteboardClassifier.classifyDragInfo(sender)
        switch classification {
        case .images(let claims):
            placementController?.handleImageAction(claims: claims, documentURL: documentURL)
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
