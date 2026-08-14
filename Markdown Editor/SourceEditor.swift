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
        let theme = MarkdownTypography()
        let placementController: ImagePlacementController
        private let highlighter = MarkdownHighlighter()
        weak var textView: MarkdownSourceTextView? {
            didSet { textView?.sourceCoordinator = self }
        }
        var nativeStorageState: NativeStorageState = .idle
        private var nextNativeGrouping: MutationGrouping?
        private var pendingStyleRange: NSRange?
        private var lastStyledText: String?
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

        /// Native AppKit edits do not pass through `EditorSession.perform`. Create and retain
        /// their intent here, then hand the same identity to the document publication observer
        /// before the canonical mutation is committed.
        @discardableResult
        func commitNativeMutation(_ mutation: SourceMutation) -> SourceEditResult {
            let intent = session?.intentRecorder.begin(.acceptedEdit)
            let staged = if let intent, let session {
                session.stageDocumentMutationIntent(intent)
            } else {
                false
            }
            let result: SourceEditResult = {
                let input = EditorInput.sourceReplacement(
                    EditorReplacementInput(
                        mutation: mutation,
                        selectionIdentity: .source(mutation.selectionBefore),
                        intentID: intent?.id ?? IntentID(rawValue: 0)
                    )
                )
                let committed = session?.commitEditorInput(
                    input,
                    selectionOverride: .source(mutation.selectionBefore)
                ) ?? document.commitEditorInput(
                    input,
                    state: EditorStateSnapshot(
                        source: document.sourceSnapshot(),
                        sourceSelection: mutation.selectionBefore
                    )
                )
                switch committed {
                case .committed(let transaction):
                    guard case .edit(let edit) = transaction.effect else { return .refused(.conflict) }
                    return .committed(edit.sourceSelectionAfter)
                case .refused(let refusal):
                    return .refused(refusal.asSourceRefusal)
                }
            }()
            if let intent {
                if case .committed = result, staged {
                    intent.recorder.finish(intent)
                } else {
                    if staged { session?.cancelStagedDocumentMutationIntent(intent) }
                    intent.recorder.finish(intent)
                }
            }
            return result
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
            switch commitNativeMutation(mutation) {
            case .committed(let selection):
                pendingStyleRange = union(
                    pendingStyleRange,
                    NSRange(location: affectedCharRange.location, length: (replacement as NSString).length)
                )
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
            if let storage = textView.textStorage {
                let edited = storage.editedRange
                if edited.location != NSNotFound {
                    pendingStyleRange = union(pendingStyleRange, edited)
                }
            }
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
            let editedRange = pendingStyleRange
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
                self.apply(
                    tokens,
                    expectedVersion: expectedVersion,
                    expectedText: snapshot,
                    editedRange: editedRange
                )
            }
        }

        // REQ-040/041/043/047–051: style via NSTextStorage attributes — display only.
        func apply(
            _ tokens: [Token],
            expectedVersion: Int,
            expectedText: String,
            editedRange: NSRange? = nil
        ) {
            guard expectedVersion == version,
                  let textView, textView.string == expectedText,
                  let storage = textView.textStorage else { return }
            let full = NSRange(location: 0, length: storage.length)
            let parity = Self.fenceParity(in: expectedText)
            let parityChanged = lastStyledText.map { Self.fenceParity(in: $0) != parity } ?? false
            let window: NSRange
            if parityChanged {
                window = full
                document.trace?.record(route: .sourceHighlightWidened, .sourceHighlightWidened(reason: .fenceParity))
            } else if let editedRange {
                window = Self.styleWindow(for: editedRange, in: expectedText as NSString)
            } else {
                window = full
            }
            let started = DispatchTime.now().uptimeNanoseconds
            storage.beginEditing()
            storage.setAttributes(theme.baseAttributes, range: window)
            for token in tokens {
                let clipped = NSIntersectionRange(token.range, window)
                guard clipped.length > 0, NSMaxRange(clipped) <= full.length else { continue }
                storage.addAttributes(theme.attributes(for: token.style), range: clipped)
            }
            storage.endEditing()
            session?.recordPerformance(
                .sourceHighlightApplication,
                durationNanos: DispatchTime.now().uptimeNanoseconds &- started
            )
            lastStyledText = expectedText
            pendingStyleRange = nil
        }

        func nextNativeEditIsDiscrete() {
            nextNativeGrouping = .discrete
        }

        static func styleWindow(for editedRange: NSRange, in text: NSString) -> NSRange {
            let length = text.length
            guard length > 0 else { return NSRange(location: 0, length: 0) }
            let location = min(max(editedRange.location, 0), length)
            let endLocation = min(max(NSMaxRange(editedRange), location), length)
            var start = location
            while start > 0, text.character(at: start - 1) != 0x0A { start -= 1 }
            var end = endLocation
            while end < length {
                let character = text.character(at: end)
                end += 1
                if character == 0x0A { break }
            }
            return NSRange(location: start, length: end - start)
        }

        private static func fenceParity(in text: String) -> Bool {
            let nsText = text as NSString
            var count = 0
            var activeMarker: unichar?
            var activeLength = 0
            var lineStart = 0
            while lineStart < nsText.length {
                var lineEnd = lineStart
                while lineEnd < nsText.length, nsText.character(at: lineEnd) != 0x0A { lineEnd += 1 }
                var markerStart = lineStart
                var indent = 0
                while markerStart < lineEnd, nsText.character(at: markerStart) == 0x20, indent < 4 {
                    markerStart += 1
                    indent += 1
                }
                if indent <= 3, markerStart < lineEnd {
                    let marker = nsText.character(at: markerStart)
                    if marker == 0x60 || marker == 0x7E {
                        var run = 0
                        while markerStart + run < lineEnd, nsText.character(at: markerStart + run) == marker {
                            run += 1
                        }
                        var onlyWhitespaceAfterRun = true
                        for index in (markerStart + run)..<lineEnd {
                            let character = nsText.character(at: index)
                            if character != 0x20 && character != 0x09 {
                                onlyWhitespaceAfterRun = false
                                break
                            }
                        }
                        let backtickInfoIsValid = marker != 0x60 || !(markerStart + run..<lineEnd).contains {
                            nsText.character(at: $0) == marker
                        }
                        if let currentMarker = activeMarker {
                            if marker == currentMarker, run >= activeLength, onlyWhitespaceAfterRun {
                                activeMarker = nil
                                activeLength = 0
                            }
                        } else if run >= 3, backtickInfoIsValid {
                            count += 1
                            activeMarker = marker
                            activeLength = run
                        }
                    }
                }
                lineStart = lineEnd < nsText.length ? lineEnd + 1 : nsText.length
            }
            return !count.isMultiple(of: 2)
        }

        private func union(_ lhs: NSRange?, _ rhs: NSRange) -> NSRange {
            guard let lhs else { return rhs }
            return NSUnionRange(lhs, rhs)
        }
    }
}

// REQ-060/064: narrow AppKit adapter — intercept image paste/drop; otherwise native.
@MainActor
final class MarkdownSourceTextView: NSTextView {
    weak var sourceCoordinator: SourceEditor.Coordinator?
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
        let result: SourceEditResult
        if let sourceCoordinator {
            result = sourceCoordinator.commitNativeMutation(mutation)
        } else {
            let input = EditorInput.imageReference(
                EditorReplacementInput(mutation: mutation)
            )
            switch actions.commitEditorInput(input) {
            case .committed(let transaction):
                if case .edit(let edit) = transaction.effect {
                    result = .committed(edit.sourceSelectionAfter)
                } else {
                    result = .refused(.conflict)
                }
            case .refused(let refusal):
                result = .refused(refusal.asSourceRefusal)
            }
        }
        switch result {
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
                sourceCoordinator?.nextNativeEditIsDiscrete()
                insertText(plain, replacementRange: range)
            } else {
                sourceCoordinator?.nextNativeEditIsDiscrete()
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
