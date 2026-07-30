//
//  SourceEditor.swift
//  Markdown Editor
//

import SwiftUI
import AppKit

// REQ-010/011/012/040/046/060–077: live-styled source editor with paste/drop image placement.
// REQ-016: reports exact SourceEdit transactions; document owns undo.
//
// Namespace for the source coordinator. `EditorHostView` owns the persistent text views
// (REQ-052/086), so this type carries no `NSViewRepresentable` conformance.
enum SourceEditor {
    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        enum NativeStorageState {
            case idle
            case awaitingTextDidChange
        }

        var document: MarkdownDocument
        var session: EditorSession?
        let theme = MarkdownTheme()
        let placementController: ImagePlacementController
        private let highlighter = MarkdownHighlighter()
        weak var textView: MarkdownSourceTextView?
        var nativeStorageState: NativeStorageState = .idle
        var nextNativeGrouping: MutationGrouping?
        private var version = 0
        private var task: Task<Void, Never>?

        init(document: MarkdownDocument, placementController: ImagePlacementController, session: EditorSession?) {
            self.document = document
            self.placementController = placementController
            self.session = session
        }

        func withOrigin<T>(_ origin: EditorUpdateOrigin, _ body: () -> T) -> T {
            guard let session else { return body() }
            return session.updateOrigin.with(origin, body)
        }

        private var currentOrigin: EditorUpdateOrigin {
            session?.updateOrigin.current ?? .nativeUserInput
        }

        func textView(
            _ textView: NSTextView,
            shouldChangeTextIn affectedCharRange: NSRange,
            replacementString: String?
        ) -> Bool {
            guard currentOrigin == .nativeUserInput else { return true }
            // Attribute-only or marked-text updates may omit a replacement string.
            guard let replacement = replacementString else { return true }
            let ns = document.text as NSString
            let expectedText: String
            if affectedCharRange.location >= 0,
               NSMaxRange(affectedCharRange) <= ns.length {
                expectedText = ns.substring(with: affectedCharRange)
            } else {
                return false
            }
            let grouping = nextNativeGrouping ?? .typing
            nextNativeGrouping = nil
            let selectionBefore = session?.sourceModeState.selection
                ?? SourceSelection(
                    utf16: textView.selectedRange(),
                    affinity: textView.selectionAffinity == .upstream ? .upstream : .downstream
                )
            let afterLocation = affectedCharRange.location + (replacement as NSString).length
            let mutation = SourceMutation(
                expectedRevision: document.sourceVersion,
                range: affectedCharRange,
                expectedText: expectedText,
                replacement: replacement,
                selectionBefore: selectionBefore,
                selectionAfter: SourceSelection(utf16: NSRange(location: afterLocation, length: 0)),
                actionName: grouping == .discrete ? "Paste" : "Typing",
                grouping: grouping
            )
            switch document.commitSourceMutation(mutation) {
            case .committed(let selection):
                session?.updateSourceModeState { $0.selection = selection }
                // Prevent updateNSView from rewriting storage before the text view applies
                // the same replacement, avoiding recursive writeback.
                nativeStorageState = .awaitingTextDidChange
                return true
            case .refused:
                return false
            }
        }

        func textDidChange(_ notification: Notification) {
            guard currentOrigin == .nativeUserInput, let textView else { return }
            nativeStorageState = .idle
            // Canonical source already updated in shouldChangeTextIn via transaction.
            session?.updateSourceModeState {
                $0.selection = SourceSelection(
                    utf16: textView.selectedRange(),
                    affinity: textView.selectionAffinity == .upstream ? .upstream : .downstream
                )
            }
            highlight(debounced: true)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView else { return }
            // REQ-094; ARC-013/015: programmatic restoration re-reports a value the session
            // already holds. Writing it back makes reconciliation a state change.
            guard currentOrigin == .nativeUserInput else { return }
            let range = textView.selectedRange()
            // Close typing groups on caret moves; skip selection churn from in-flight typing.
            if nativeStorageState == .idle {
                document.closeTypingUndoGroup()
            }
            session?.updateSourceModeState { state in
                state.selection = SourceSelection(
                    utf16: range,
                    affinity: textView.selectionAffinity == .upstream ? .upstream : .downstream
                )
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
        guard range.location >= 0,
              NSMaxRange(range) <= (snapshot.text as NSString).length else {
            return
        }
        let selectionBefore = SourceSelection(
            utf16: selectedRange(),
            affinity: selectionAffinity == .upstream ? .upstream : .downstream
        )
        guard let mutation = SourceMutation.exact(
            snapshot: snapshot,
            range: range,
            replacement: markdown,
            selectionBefore: selectionBefore,
            actionName: "Insert Image",
            grouping: .discrete
        ) else {
            return
        }
        switch actions.commitSourceMutation(mutation) {
        case .committed:
            if selectEmptyDescription {
                let descStart = range.location + 2
                let pending = SourceSelection(utf16: NSRange(location: descStart, length: 0))
                actions.requestSelectionRestoration(pending)
            } else {
                let end = range.location + (markdown as NSString).length
                let pending = SourceSelection(utf16: NSRange(location: end, length: 0))
                actions.requestSelectionRestoration(pending)
            }
        case .refused:
            break
        }
    }

    override func paste(_ sender: Any?) {
        let classification = ImagePasteboardClassifier.classifyPasteboard(.general)
        switch classification {
        case .images(let claims):
            guard let target = imagePlacementTarget() else { return }
            placementController?.handleImageAction(
                intent: ImagePlacementIntent(target: target, claims: claims),
                documentURL: documentActions?.sourceSnapshot().fileURL ?? documentURL
            )
            case .fallthroughToNativeText, .unsupported:
            if case .unsupported = classification {
                placementController?.presentAlert(.error("Unsupported or corrupt image."), reason: .pasteboardUnsupportedOrCorrupt)
                return
            }
            // REQ-059: prefer plain-text representation even when RTF/HTML is present.
            if let plain = PastePolicy.plainText(from: .general) {
                let range = selectedRange()
                // Paste must not coalesce into the open typing undo group (REQ-016).
                (delegate as? SourceEditor.Coordinator)?.nextNativeGrouping = .discrete
                insertText(plain, replacementRange: range)
            } else {
                (delegate as? SourceEditor.Coordinator)?.nextNativeGrouping = .discrete
                super.pasteAsPlainText(sender)
            }
        }
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pb = sender.draggingPasteboard
        let url = documentActions?.sourceSnapshot().fileURL ?? documentURL
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
                placementController?.presentAlert(.error("Unsupported or corrupt image."), reason: .pasteboardUnsupportedOrCorrupt)
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

    private func imagePlacementTarget() -> ImagePlacementTarget? {
        guard let actions = documentActions else { return nil }
        let snapshot = actions.sourceSnapshot()
        let selected = selectedRange()
        guard selected.location >= 0,
              NSMaxRange(selected) <= (snapshot.text as NSString).length else {
            return nil
        }
        return ImagePlacementTarget(
            sourceSelection: SourceSelection(
                utf16: selected,
                affinity: selectionAffinity == .upstream ? .upstream : .downstream
            ),
            sourceRevision: SourceRevision(value: snapshot.sourceVersion),
            locationGeneration: snapshot.locationGeneration,
            operationID: UUID()
        )
    }
}
