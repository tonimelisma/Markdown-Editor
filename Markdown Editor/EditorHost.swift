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

    /// Immutable source-domain intent captured before async picker/promise work.
    private(set) var pendingImageTarget: ImagePlacementTarget?

    func captureImagePlacementTarget(_ target: ImagePlacementTarget) {
        pendingImageTarget = target
    }

    func clearPendingImageTarget() {
        pendingImageTarget = nil
    }

    func handleAddImageClaims(_ claims: [ImageClaim]) {
        guard let placement, let document else { return }
        guard let target = pendingImageTarget,
              target.sourceRevision.value == document.sourceVersion,
              target.locationGeneration == document.locationGeneration else {
            pendingImageTarget = nil
            return
        }
        placement.handleImageAction(
            intent: ImagePlacementIntent(target: target, claims: claims),
            documentURL: document.publishedFileURL ?? document.fileURL
        )
        pendingImageTarget = nil
    }
}

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
        // Apply the newest presentation before accepting native coordinates as
        // belonging to it. The previous TextKit storage still owns the old snapshot.
        host.refreshVisibleEditor()
        host.applyMode(session.mode, focus: false)
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

        /// Last mode applied to visibility — used to transfer focus on toggle.
        private var lastAppliedMode: EditorMode?

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
            let modeChanged = lastAppliedMode != nil && lastAppliedMode != mode
            let firstResponder = sourceText.window?.firstResponder
            let hadEditorFocus =
                firstResponder === sourceText
                || firstResponder === wysiwygText
                || firstResponder === sourceScroll
                || firstResponder === wysiwygScroll
            if sourceScroll.isHidden == false {
                session.updateSourceModeState {
                    $0.selection = SourceSelection(
                        utf16: sourceText.selectedRange(),
                        affinity: sourceText.selectionAffinity == .upstream ? .upstream : .downstream
                    )
                    $0.scrollOffset = sourceScroll.contentView.bounds.origin
                }
            }
            if wysiwygScroll.isHidden == false {
                if let presentation = session.presentation,
                   wysiwygCoordinator?.hasAppliedSnapshot(presentation.id) == true {
                    let affinity: SelectionAffinity =
                        wysiwygText.selectionAffinity == .upstream ? .upstream : .downstream
                    session.updateWYSIWYGModeState {
                        $0.selection = ProjectionSelection(
                            utf16: wysiwygText.selectedRange(),
                            revision: presentation.projectionRevision,
                            affinity: affinity
                        )
                        $0.scrollOffset = wysiwygScroll.contentView.bounds.origin
                    }
                }
            }
            let showSource = (mode == .source)
            sourceScroll.isHidden = !showSource
            wysiwygScroll.isHidden = showSource
            let shouldFocus = focus || (modeChanged && hadEditorFocus)
            lastAppliedMode = mode
            session.updateOrigin.with(.modeRestoration) {
                if showSource {
                    let sourceState = session.sourceModeState
                    let affinity: NSSelectionAffinity =
                        sourceState.selection.affinity == .upstream ? .upstream : .downstream
                    sourceText.setSelectedRanges(
                        [NSValue(range: sourceState.selection.range.utf16)],
                        affinity: affinity,
                        stillSelecting: false
                    )
                    sourceScroll.contentView.scroll(to: sourceState.scrollOffset)
                    sourceScroll.reflectScrolledClipView(sourceScroll.contentView)
                    if shouldFocus { sourceText.window?.makeFirstResponder(sourceText) }
                } else {
                    let wysiwygState = session.wysiwygModeState
                    let range = wysiwygState.selection?.range.utf16 ?? NSRange(location: 0, length: 0)
                    let affinity: NSSelectionAffinity =
                        (wysiwygState.selection?.affinity == .upstream) ? .upstream : .downstream
                    wysiwygText.setSelectedRanges(
                        [NSValue(range: range)],
                        affinity: affinity,
                        stillSelecting: false
                    )
                    wysiwygScroll.contentView.scroll(to: wysiwygState.scrollOffset)
                    wysiwygScroll.reflectScrolledClipView(wysiwygScroll.contentView)
                    if shouldFocus { wysiwygText.window?.makeFirstResponder(wysiwygText) }
                }
            }
        }

        func refreshVisibleEditor() {
            if session.mode == .source {
                guard let text = sourceText, let coord = sourceCoordinator else { return }
                if coord.nativeStorageState == .idle, text.string != document.text {
                    coord.withOrigin(.programmaticPresentation) {
                        text.string = document.text
                        coord.highlight()
                    }
                }
            } else {
                wysiwygCoordinator?.applyProjectionIfNeeded(force: false)
            }
            applyPendingSelectionIfNeeded()
        }

        /// Apply one-shot session selection restoration to the visible editor.
        ///
        /// // REQ-083/086: never clamp source coords into a stale projection.
        func applyPendingSelectionIfNeeded() {
            if let restoration = session.pendingSelectionRestoration {
                switch restoration.domain {
                case .source:
                    guard session.mode == .source, let sourceText else { return }
                    session.updateOrigin.with(.selectionRestoration) {
                        let length = (sourceText.string as NSString).length
                        let pending = restoration.sourceSelection.range.utf16
                        let loc = min(max(0, pending.location), length)
                        let len = min(max(0, pending.length), max(0, length - loc))
                        sourceText.setSelectedRange(NSRange(location: loc, length: len))
                        _ = session.consumePendingSelectionRestoration()
                    }
                case .projection(let snapshotID):
                    guard session.mode == .wysiwyg, let wysiwygText else { return }
                    guard let presentation = session.presentation, presentation.id == snapshotID else {
                        return
                    }
                    session.updateOrigin.with(.selectionRestoration) {
                        if let projected = restoration.projectionSelection {
                            wysiwygText.setSelectedRange(projected.range.utf16)
                        } else if case .exact(let projected) = presentation.coordinateMap.projectionRange(
                            forSource: restoration.sourceSelection.range.utf16
                        ) {
                            wysiwygText.setSelectedRange(projected)
                        } else {
                            return
                        }
                        _ = session.consumePendingSelectionRestoration()
                    }
                }
            }
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
            textView.isAutomaticSpellingCorrectionEnabled = false
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
            textView.isAutomaticSpellingCorrectionEnabled = false
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
