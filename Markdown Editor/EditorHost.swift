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
        guard !claims.isEmpty else {
            pendingImageTarget = nil
            return
        }
        guard let target = pendingImageTarget,
              target.sourceRevision.value == document.sourceVersion,
              target.locationGeneration == document.locationGeneration else {
            // REQ-101: the picker returned known claims, but the source-domain intent is no
            // longer exact. Refuse without mutation while leaving an actionable diagnostic.
            placement.recordRejectedImageAction(claimCount: claims.count, reason: .parentChanged)
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

    /// // REQ-094; ARC-015: a pure reader. Rebind references, apply a newer presentation,
    /// // restore a pending one-shot selection, and apply a mode change — nothing else.
    /// // Publishing session state here would re-dirty the view being reconciled, and because
    /// // `@Published` invalidates on assignment rather than on change, the loop never settles.
    func updateNSView(_ nsView: NSView, context: Context) {
        let host = context.coordinator
        let started = DispatchTime.now().uptimeNanoseconds
        session.withViewReconciliation {
            host.document = document
            host.session = session
            host.placementController = placementController
            host.actionRouter = actionRouter
            host.syncDocumentBindings()
            // Apply the newest presentation before accepting native coordinates as
            // belonging to it. The previous TextKit storage still owns the old snapshot.
            host.refreshVisibleEditor()
            host.applyModeIfChanged(session.mode)
        }
        host.noteHostUpdate(durationNanos: DispatchTime.now().uptimeNanoseconds &- started)
    }

    @MainActor
    final class HostCoordinator: NSObject {
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

        /// Rolling host-update rate (REQ-096; ARC-Q11).
        private let updateMeter = HostUpdateMeter()

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
            super.init()
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        /// Records one completed host update and reports a sustained storm.
        ///
        /// // REQ-096; ARC-Q11: an idle document settles. Sustained reconciliation without user
        /// // input is the signature of a self-feeding update loop and is reported as a fault.
        func noteHostUpdate(durationNanos: UInt64) {
            let sample = updateMeter.record(durationNanos: durationNanos)
            document.trace?.record(
                .hostUpdateEnded(
                    durationNanos: sample.durationNanos,
                    updatesInWindow: sample.updatesInWindow
                )
            )
            if sample.crossedStormThreshold {
                document.trace?.record(.hostUpdateStorm(updatesInWindow: sample.updatesInWindow))
            }
        }

        /// Records live scroll position from the clip view's own bounds notification.
        ///
        /// // REQ-086/094; ARC-015: scroll enters the session from a real AppKit event, never
        /// // from view reconciliation, and never while a programmatic origin is in scope.
        @objc
        private func clipViewBoundsDidChange(_ notification: Notification) {
            guard session.updateOrigin.current == .nativeUserInput else { return }
            guard session.viewReconciliationDepth == 0 else { return }
            guard let clipView = notification.object as? NSClipView else { return }
            let origin = clipView.bounds.origin
            if clipView === sourceScroll?.contentView {
                guard session.sourceModeState.scrollOffset != origin else { return }
                session.updateSourceModeState { $0.scrollOffset = origin }
            } else if clipView === wysiwygScroll?.contentView {
                guard session.wysiwygModeState.scrollOffset != origin else { return }
                session.updateWYSIWYGModeState { $0.scrollOffset = origin }
            }
        }

        private func observeScrollBounds(_ scrollView: NSScrollView) {
            scrollView.contentView.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(clipViewBoundsDidChange(_:)),
                name: NSView.boundsDidChangeNotification,
                object: scrollView.contentView
            )
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
            observeScrollBounds(sScroll)
            observeScrollBounds(wScroll)
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
            // The document URL is driven by ContentView's `onChange(of:)` hooks. Calling it
            // here too can publish `placementController.alert` from inside reconciliation —
            // the same illegal direction of flow as ARC-015, on a different observed object.
        }

        /// Applies a mode only when it actually changed.
        ///
        /// // REQ-094; ARC-015: reconciling an unchanged mode performs no work and mutates no
        /// // session state. Visibility, focus, and restoration are consequences of a real mode
        /// // change, not of the view graph running an update pass.
        func applyModeIfChanged(_ mode: EditorMode) {
            guard lastAppliedMode != mode else { return }
            applyMode(mode, focus: false)
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
            // The outgoing mode's selection and scroll are already current: selection arrives
            // from `textViewDidChangeSelection` and scroll from the clip view's bounds
            // notification, both of which are real AppKit events. Capturing them here instead
            // would write session state from inside view reconciliation (ARC-015).
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
                        // Replacing storage collapses the native caret. Re-apply the session's
                        // selection so the visible caret and `sourceModeState.selection` — which
                        // toolbar commands act on — cannot diverge after a load or revert.
                        // Reading session state here is allowed; writing it would not be
                        // (REQ-094; ARC-015).
                        let length = (document.text as NSString).length
                        let wanted = session.sourceModeState.selection.range.utf16
                        let location = min(max(0, wanted.location), length)
                        let extent = min(max(0, wanted.length), max(0, length - location))
                        text.setSelectedRange(NSRange(location: location, length: extent))
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
