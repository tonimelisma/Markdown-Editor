//
//  EditorHost.swift
//  Markdown Editor
//

import AppKit
import Combine
import SwiftUI

/// Window-scoped Add Image / placement entry — no process-wide notification.
///
/// // REQ-082: replaces `.editorAddImageClaims`.
@MainActor
final class EditorActionRouter: ObservableObject {
    weak var placement: ImagePlacementController?
    weak var document: MarkdownDocument?
    weak var session: EditorSession?

    /// Captured selection intent for the window that initiated Add Image.
    private(set) var pendingImageIntent: EditorSelectionIntent?

    func captureImageInsertionIntent(_ intent: EditorSelectionIntent) {
        pendingImageIntent = intent
    }

    func clearPendingImageIntent() {
        pendingImageIntent = nil
    }

    func handleAddImageClaims(_ claims: [ImageClaim]) {
        guard let placement, let document else { return }
        // REQ-082: resolve the captured intent to a source range before placement.
        if let intent = pendingImageIntent {
            let snapshot = document.sourceSnapshot()
            switch intent.resolvedSourceRange(snapshot: snapshot, projection: session?.projection) {
            case .exact(let sourceRange):
                document.reportActiveSelection(sourceRange)
            case .refused:
                pendingImageIntent = nil
                return
            }
        }
        placement.handleImageAction(
            claims: claims,
            documentURL: document.publishedFileURL ?? document.fileURL
        )
        pendingImageIntent = nil
    }
}

/// Mode-local editor chrome state for the persistent dual host.
typealias EditorViewChromeState = EditorViewState

/// Persistent dual TextKit 1 host — both editors live for the representable lifetime.
///
/// // REQ-052/086: toggle visibility/focus only; restore mode-local chrome.
struct EditorHostView: NSViewRepresentable {
    @ObservedObject var document: MarkdownDocument
    @ObservedObject var session: EditorSession
    @ObservedObject var placementController: ImagePlacementController
    @ObservedObject var actionRouter: EditorActionRouter

    func makeCoordinator() -> HostCoordinator {
        HostCoordinator(
            document: document,
            session: session,
            placementController: placementController,
            actionRouter: actionRouter
        )
    }

    func makeNSView(context: Context) -> NSView {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 480))
        let host = context.coordinator
        host.buildEditors(in: root)
        host.applyMode(session.mode, focus: false)
        return root
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let host = context.coordinator
        host.document = document
        host.session = session
        host.placementController = placementController
        host.actionRouter = actionRouter
        host.syncDocumentBindings()
        host.applyMode(session.mode, focus: false)
        host.refreshVisibleEditor()
    }

    @MainActor
    final class HostCoordinator {
        var document: MarkdownDocument
        var session: EditorSession
        var placementController: ImagePlacementController
        var actionRouter: EditorActionRouter

        var sourceScroll: NSScrollView?
        var wysiwygScroll: NSScrollView?
        var sourceText: MarkdownSourceTextView?
        var wysiwygText: MarkdownWYSIWYGTextView?
        var sourceCoordinator: MarkdownTextView.Coordinator?
        var wysiwygCoordinator: WYSIWYGTextView.Coordinator?

        var sourceChrome = EditorViewChromeState()
        var wysiwygChrome = EditorViewChromeState()

        /// Stable identities for characterization tests.
        var sourceViewIdentity: ObjectIdentifier? {
            sourceText.map { ObjectIdentifier($0) }
        }
        var wysiwygViewIdentity: ObjectIdentifier? {
            wysiwygText.map { ObjectIdentifier($0) }
        }

        init(
            document: MarkdownDocument,
            session: EditorSession,
            placementController: ImagePlacementController,
            actionRouter: EditorActionRouter
        ) {
            self.document = document
            self.session = session
            self.placementController = placementController
            self.actionRouter = actionRouter
        }

        func buildEditors(in root: NSView) {
            sourceCoordinator = MarkdownTextView.Coordinator(
                document: document,
                placementController: placementController,
                session: session
            )
            wysiwygCoordinator = WYSIWYGTextView.Coordinator(
                document: document,
                session: session,
                placementController: placementController
            )

            let sScroll = NSScrollView()
            sScroll.hasVerticalScroller = true
            sScroll.borderType = .noBorder
            let sText = MarkdownSourceTextView(usingTextLayoutManager: false)
            configureSource(sText)
            sText.delegate = sourceCoordinator
            sScroll.documentView = sText
            sourceCoordinator?.textView = sText
            sourceCoordinator?.highlight()

            let wScroll = NSScrollView()
            wScroll.hasVerticalScroller = true
            wScroll.borderType = .noBorder
            let wText = MarkdownWYSIWYGTextView(usingTextLayoutManager: false)
            configureWYSIWYG(wText)
            wText.delegate = wysiwygCoordinator
            wText.inputCoordinator = wysiwygCoordinator?.input
            wScroll.documentView = wText
            wysiwygCoordinator?.textView = wText
            wysiwygCoordinator?.scrollView = wScroll
            wysiwygCoordinator?.applyProjectionIfNeeded(force: true)

            for scroll in [sScroll, wScroll] {
                scroll.translatesAutoresizingMaskIntoConstraints = false
                root.addSubview(scroll)
                NSLayoutConstraint.activate([
                    scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
                    scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
                    scroll.topAnchor.constraint(equalTo: root.topAnchor),
                    scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor)
                ])
            }

            sourceScroll = sScroll
            wysiwygScroll = wScroll
            sourceText = sText
            wysiwygText = wText
            placementController.attach(actions: document)
            placementController.updateDocumentURL(document.fileURL)

            // REQ-052/086: both views exist; only the active mode is visible.
            let showSource = (session.mode == .source)
            sScroll.isHidden = !showSource
            wScroll.isHidden = showSource
        }

        func syncDocumentBindings() {
            sourceText?.documentActions = document
            sourceText?.placementController = placementController
            sourceCoordinator?.document = document
            sourceCoordinator?.session = session
            wysiwygText?.documentActions = document
            wysiwygText?.session = session
            wysiwygText?.placementController = placementController
            wysiwygCoordinator?.document = document
            wysiwygCoordinator?.session = session
            placementController.attach(actions: document)
            placementController.updateDocumentURL(document.publishedFileURL ?? document.fileURL)
        }

        func applyMode(_ mode: EditorMode, focus: Bool) {
            guard let sourceScroll, let wysiwygScroll, let sourceText, let wysiwygText else { return }
            if sourceScroll.isHidden == false {
                sourceChrome.selection = sourceText.selectedRange()
                sourceChrome.affinity = sourceText.selectionAffinity == .upstream ? .upstream : .downstream
                sourceChrome.scrollOffset = sourceScroll.contentView.bounds.origin
                sourceChrome.acceptedSourceVersion = document.sourceVersion
            }
            if wysiwygScroll.isHidden == false {
                wysiwygChrome.selection = wysiwygText.selectedRange()
                wysiwygChrome.affinity = wysiwygText.selectionAffinity == .upstream ? .upstream : .downstream
                wysiwygChrome.scrollOffset = wysiwygScroll.contentView.bounds.origin
                wysiwygChrome.acceptedSourceVersion = session.acceptedSourceVersion
            }
            let showSource = (mode == .source)
            sourceScroll.isHidden = !showSource
            wysiwygScroll.isHidden = showSource
            if showSource {
                let affinity: NSSelectionAffinity = sourceChrome.affinity == .upstream ? .upstream : .downstream
                sourceText.setSelectedRanges(
                    [NSValue(range: sourceChrome.selection)],
                    affinity: affinity,
                    stillSelecting: false
                )
                sourceScroll.contentView.scroll(to: sourceChrome.scrollOffset)
                sourceScroll.reflectScrolledClipView(sourceScroll.contentView)
                if focus { sourceText.window?.makeFirstResponder(sourceText) }
            } else {
                let affinity: NSSelectionAffinity = wysiwygChrome.affinity == .upstream ? .upstream : .downstream
                wysiwygText.setSelectedRanges(
                    [NSValue(range: wysiwygChrome.selection)],
                    affinity: affinity,
                    stillSelecting: false
                )
                wysiwygScroll.contentView.scroll(to: wysiwygChrome.scrollOffset)
                wysiwygScroll.reflectScrolledClipView(wysiwygScroll.contentView)
                if focus { wysiwygText.window?.makeFirstResponder(wysiwygText) }
            }
        }

        func refreshVisibleEditor() {
            if session.mode == .source {
                guard let text = sourceText, let coord = sourceCoordinator else { return }
                if !coord.isNativeEditInFlight, text.string != document.text {
                    coord.isProgrammaticUpdate = true
                    text.string = document.text
                    coord.isProgrammaticUpdate = false
                    coord.highlight()
                }
            } else {
                wysiwygCoordinator?.applyProjectionIfNeeded(force: false)
            }
            applyPendingSelectionIfNeeded()
        }

        /// Apply document-owned post-edit caret (always source UTF-16) to the visible editor.
        func applyPendingSelectionIfNeeded() {
            guard let pending = document.pendingSelection else { return }
            if session.mode == .source {
                guard let sourceText else { return }
                let length = (sourceText.string as NSString).length
                let loc = min(max(0, pending.location), length)
                let len = min(max(0, pending.length), max(0, length - loc))
                sourceText.setSelectedRange(NSRange(location: loc, length: len))
            } else {
                guard let wysiwygText else { return }
                let projected: NSRange
                if let projection = session.projection,
                   case .exact(let range) = projection.coordinateMap.projectionRange(forSource: pending) {
                    projected = range
                } else {
                    let length = (wysiwygText.string as NSString).length
                    let loc = min(max(0, pending.location), length)
                    let len = min(max(0, pending.length), max(0, length - loc))
                    projected = NSRange(location: loc, length: len)
                }
                wysiwygText.setSelectedRange(projected)
            }
            document.pendingSelection = nil
        }

        private func configureSource(_ textView: MarkdownSourceTextView) {
            textView.placementController = placementController
            textView.documentActions = document
            textView.isRichText = false
            textView.allowsUndo = false
            textView.font = MarkdownTheme().baseFont
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
            textView.string = document.text
            textView.setAccessibilityLabel("Markdown source")
            var dragTypes: [NSPasteboard.PasteboardType] = [.fileURL, .png, .tiff]
            dragTypes.append(contentsOf: FilePromiseBridge.readableDraggedTypes)
            textView.registerForDraggedTypes(dragTypes)
        }

        private func configureWYSIWYG(_ textView: MarkdownWYSIWYGTextView) {
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
            textView.isEditable = true
            textView.isSelectable = true
            var dragTypes: [NSPasteboard.PasteboardType] = [.fileURL, .png, .tiff]
            dragTypes.append(contentsOf: FilePromiseBridge.readableDraggedTypes)
            textView.registerForDraggedTypes(dragTypes)
        }
    }
}
