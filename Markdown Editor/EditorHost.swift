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

    func handleAddImageClaims(_ claims: [ImageClaim], intentContext: IntentContext? = nil) {
        guard let placement, let document else {
            if let intentContext { intentContext.recorder.finish(intentContext) }
            return
        }
        guard !claims.isEmpty else {
            if let intentContext { intentContext.recorder.finish(intentContext) }
            pendingImageTarget = nil
            return
        }
        guard let target = pendingImageTarget,
              target.sourceRevision.value == document.sourceVersion,
              target.locationGeneration == document.locationGeneration else {
            // REQ-101: the picker returned known claims, but the source-domain intent is no
            // longer exact. Refuse without mutation while leaving an actionable diagnostic.
            placement.recordRejectedImageAction(claimCount: claims.count, reason: .parentChanged, intentContext: intentContext)
            pendingImageTarget = nil
            return
        }
        placement.handleImageAction(
            intent: ImagePlacementIntent(target: target, claims: claims),
            documentURL: document.publishedFileURL ?? document.fileURL,
            intentContext: intentContext
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
        let root = EditorHostRootView(frame: NSRect(x: 0, y: 0, width: 640, height: 480))
        let host = context.coordinator
        root.onWindow = { [weak host] in host?.focusVisibleEditorIfUnfocused() }
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
        var sourceCoordinator: SourceEditor.Coordinator?
        var wysiwygCoordinator: WYSIWYGEditor.Coordinator?

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
            document.trace?.record(route: .hostUpdateEnded, .hostUpdateEnded(
                    durationNanos: sample.durationNanos,
                    updatesInWindow: sample.updatesInWindow
                )
            )
            if sample.crossedStormThreshold {
                document.trace?.record(route: .hostUpdateStorm, .hostUpdateStorm(updatesInWindow: sample.updatesInWindow))
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
            if let sourceScroll, clipView === sourceScroll.contentView {
                let offset = Self.scrollOffset(in: sourceScroll)
                guard session.sourceModeState.scrollOffset != offset else { return }
                session.updateSourceModeState { $0.scrollOffset = offset }
            } else if let wysiwygScroll, clipView === wysiwygScroll.contentView {
                let offset = Self.scrollOffset(in: wysiwygScroll)
                guard session.wysiwygModeState.scrollOffset != offset else { return }
                session.updateWYSIWYGModeState { $0.scrollOffset = offset }
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
            sourceCoordinator = SourceEditor.Coordinator(
                document: document,
                placementController: placementController,
                session: session
            )
            wysiwygCoordinator = WYSIWYGEditor.Coordinator(
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
            wysiwygCoordinator?.applyProjectionIfNeeded(reason: .reapplyIfDrift)

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
            findBarObservations = [sScroll, wScroll].map { scroll in
                scroll.observe(\.isFindBarVisible, options: [.new]) { [weak self] scroll, change in
                    guard change.newValue == false else { return }
                    MainActor.assumeIsolated { self?.returnKeyboardAfterFind(in: scroll) }
                }
            }
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
        /// A new window gives its page keyboard focus, as TextEdit does, so typing works at once.
        /// Nothing did: a plain launch opened an untitled window whose first keystrokes went
        /// nowhere until the page was clicked (agent-drive tour 45955987611). Only a window
        /// nobody has focused yet is touched.
        func focusVisibleEditorIfUnfocused() {
            let editor: NSTextView? = session.mode == .source ? sourceText : wysiwygText
            guard let editor, let window = editor.window else { return }
            window.initialFirstResponder = editor
            let responder = window.firstResponder
            guard responder == nil || responder === window else { return }
            window.makeFirstResponder(editor)
        }

        func applyModeIfChanged(_ mode: EditorMode) {
            guard lastAppliedMode != mode else { return }
            applyMode(mode, focus: false)
        }

        func applyMode(_ mode: EditorMode, focus: Bool) {
            if lastAppliedMode != nil && lastAppliedMode != mode {
                let intent = session.intentRecorder.begin(.modeTransition)
                defer { session.intentRecorder.finish(intent) }
                applyModeBody(mode, focus: focus)
            } else {
                applyModeBody(mode, focus: focus)
            }
        }

        private func applyModeBody(_ mode: EditorMode, focus: Bool) {
            let performanceStart = DispatchTime.now().uptimeNanoseconds
            guard let sourceScroll, let wysiwygScroll, let sourceText, let wysiwygText else { return }
            let modeChanged = lastAppliedMode != nil && lastAppliedMode != mode
            // REQ-090/103: only a real mode transition is a mode transition. Initial editor
            // construction also lands here, and timing it would put view-setup latency into the
            // 16 ms budget — inflating p95 and able to emit a budget warning for a user who
            // never switched modes.
            defer {
                if modeChanged {
                    session.recordPerformance(
                        .modeTransition,
                        durationNanos: DispatchTime.now().uptimeNanoseconds - performanceStart
                    )
                }
            }
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
            document.currentPrintView = showSource ? sourceText : wysiwygText
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
                    Self.restoreScrollOffset(sourceState.scrollOffset, in: sourceScroll)
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
                    Self.restoreScrollOffset(wysiwygState.scrollOffset, in: wysiwygScroll)
                    if shouldFocus { wysiwygText.window?.makeFirstResponder(wysiwygText) }
                }
            }
        }

        private var findBarObservations: [NSKeyValueObservation] = []

        /// When the find bar closes with the keyboard nowhere, the page it searched takes it back,
        /// as TextEdit's does. Closed with Done, it left no first responder: the next ⌘↓ and
        /// Return went nowhere, and Add Image replaced the word Find had selected (tour
        /// 45974231615).
        func returnKeyboardAfterFind(in scroll: NSScrollView) {
            guard let window = scroll.window, let page = scroll.documentView as? NSTextView,
                  !scroll.isHidden else { return }
            let responder = window.firstResponder
            let inFindBar = (responder as? NSView).map { $0.isDescendant(of: scroll) && !$0.isDescendant(of: page) } ?? false
            guard responder == nil || responder === window || inFindBar else { return }
            window.makeFirstResponder(page)
        }

        func refreshVisibleEditor() {
            if session.mode == .source {
                guard let text = sourceText, let coord = sourceCoordinator else { return }
                if coord.nativeStorageState == .idle, text.string != document.text {
                    coord.withOrigin(.programmaticPresentation) {
                        text.string = document.text
                        coord.highlight(afterReplacingText: true)
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
                wysiwygCoordinator?.applyProjectionIfNeeded(reason: .newSnapshot)
                wysiwygCoordinator?.adoptNativeSelectionIfUnowned()
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

        /// Session scroll state is an offset from the top of the *document*, not a raw clip-view
        /// bounds origin.
        ///
        /// // COR-93: AppKit is free to park a scroll view's document view at a non-zero origin
        /// // inside its clip view, and it does exactly that for the Source editor, which is
        /// // laid out while hidden — measured at `documentView.frame.origin.y == -1044` for an
        /// // 861-point clip over a 2122-point document. `scroll(to: .zero)` then means "1044
        /// // points down", so the first switch into Source opened halfway through the file
        /// // while both the session and the clip view agreed the offset was zero. Neither
        /// // `tile()` nor laying out the clip view resets that placement; measuring against it
        /// // does. Storing the offset relative to the document keeps "no scroll" meaning "the
        /// // top" wherever AppKit has put the document view (REQ-086).
        private static func documentOrigin(in scrollView: NSScrollView) -> CGPoint {
            scrollView.documentView?.frame.origin ?? .zero
        }

        static func scrollOffset(in scrollView: NSScrollView) -> CGPoint {
            let document = documentOrigin(in: scrollView)
            let bounds = scrollView.contentView.bounds.origin
            return CGPoint(x: bounds.x - document.x, y: bounds.y - document.y)
        }

        static func restoreScrollOffset(_ offset: CGPoint, in scrollView: NSScrollView) {
            let document = documentOrigin(in: scrollView)
            scrollView.contentView.scroll(
                to: CGPoint(x: document.x + offset.x, y: document.y + offset.y)
            )
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }

        private func configureSource(_ textView: MarkdownSourceTextView) {
            textView.placementController = placementController
            textView.documentActions = document
            textView.isRichText = false
            textView.allowsUndo = false
            textView.font = MarkdownTypography().bodyFont
            textView.isAutomaticQuoteSubstitutionEnabled = false
            textView.isAutomaticDashSubstitutionEnabled = false
            textView.isAutomaticTextReplacementEnabled = false
            textView.isAutomaticSpellingCorrectionEnabled = false
            // REQ-012: use AppKit's native checker; the editor does not own a spell engine.
            textView.isContinuousSpellCheckingEnabled = true
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
            // Reading-column geometry — inset, measure, and width tracking — belongs to
            // MarkdownWYSIWYGTextView.layout(). Setting it here too would be a second owner of
            // the same fact, disagreeing with the first until the next layout pass.
            textView.isVerticallyResizable = true
            textView.isHorizontallyResizable = false
            textView.autoresizingMask = [.width]
            textView.setAccessibilityLabel("Markdown WYSIWYG")
            textView.isEditable = true
            textView.isSelectable = true
            var dragTypes: [NSPasteboard.PasteboardType] = [.fileURL, .png, .tiff]
            dragTypes.append(contentsOf: FilePromiseBridge.readableDraggedTypes)
            textView.registerForDraggedTypes(dragTypes)
        }
    }
}

/// The editors' container: it tells the host when it joins a window, which is the first moment
/// the page can be given keyboard focus.
final class EditorHostRootView: NSView {
    var onWindow: (() -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        onWindow?()
    }
}
