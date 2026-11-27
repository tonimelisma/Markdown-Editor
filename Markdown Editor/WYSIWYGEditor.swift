//
//  WYSIWYGEditor.swift
//  Markdown Editor
//

import AppKit
import SwiftUI

/// TextKit 1 WYSIWYG adapter — delimiter-free rich storage; edits become source transactions.
///
/// Namespace for the WYSIWYG coordinator. `EditorHostView` owns the persistent text views
/// (REQ-052/086), so this type carries no `NSViewRepresentable` conformance.
///
/// // REQ-052/054–059/078–084/086: rich projection host; tasks/links; plain paste; accessibility.
enum WYSIWYGEditor {
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

        func beginMarkedText(
            sourceVersion: UInt64,
            sourceRange: NSRange,
            marked: NSRange,
            snapshotID: PresentationSnapshot.ID? = nil
        ) {
            if composition.isComposing {
                composition.update(marked: marked)
            } else {
                composition.begin(
                    sourceVersion: sourceVersion,
                    sourceRange: sourceRange,
                    marked: marked,
                    snapshotID: snapshotID
                )
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

        func complete() -> (version: UInt64, range: NSRange, snapshotID: PresentationSnapshot.ID?)? {
            composition.complete()
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var document: MarkdownDocument
        var session: EditorSession
        let placementController: ImagePlacementController
        let input = WYSIWYGInputCoordinator()
        weak var textView: MarkdownWYSIWYGTextView? {
            didSet { textView?.adapterCoordinator = self }
        }
        weak var scrollView: NSScrollView?
        /// The snapshot currently in storage. Kept whole, not just by ID, because patching to a
        /// newer snapshot needs the text it is patching *from*.
        private var appliedSnapshot: PresentationSnapshot?
        private var appliedSnapshotID: PresentationSnapshot.ID? { appliedSnapshot?.id }
        /// Resolved images belong to attributed storage, not the semantic snapshot. An
        /// authoritative result can keep the same semantics while replacing a placeholder with
        /// a decoded image, so that identity must participate in an attribute refresh.
        private var appliedImageIdentities: [MarkdownNodeID: ObjectIdentifier] = [:]
        private let textStorageApplier = TextStorageApplier()

        init(document: MarkdownDocument, session: EditorSession, placementController: ImagePlacementController) {
            self.document = document
            self.session = session
            self.placementController = placementController
        }

        enum ApplyReason: Sendable {
            case newSnapshot
            case reapplyIfDrift
        }

        func applyProjectionIfNeeded(
            reason: ApplyReason,
            nativeTextAlreadyApplied: Bool = false
        ) {
            let force = (reason == .reapplyIfDrift)
            guard let textView else { return }
            guard let presentation = session.presentation else {
                textView.isEditable = false
                return
            }
            let intent = session.takePresentationIntent(for: presentation.id)
            defer {
                if let intent {
                    intent.recorder.finish(intent)
                }
            }
            let editable: Bool
            if case .editable(let id) = session.wysiwygModeState.availability, id == presentation.id {
                editable = true
            } else {
                editable = false
            }
            textView.isEditable = editable
            guard editable else { return }
            guard force || appliedSnapshotID != presentation.id else { return }
            // Never replace storage during marked text.
            if textView.hasMarkedText() || input.composition.isComposing { return }

            // REQ-109; ARC-019/ARC-Q16: force only means reapply the snapshot already in
            // storage. A newer snapshot must take the bounded route regardless of whether it
            // arrived from reconciliation, a task press, or an IME commit.
            if let applied = appliedSnapshot {
                if applied.id != presentation.id {
                    if let reason = incrementalRecoveryReason(
                        from: applied,
                        to: presentation,
                        in: textView,
                        intent: intent,
                        nativeTextAlreadyApplied: nativeTextAlreadyApplied
                    ) {
                        // An unprovable newer snapshot is exceptional, never an ordinary
                        // fallback. This route records the typed fault and takes WYSIWYG out of
                        // service until authoritative reconciliation can establish a new current
                        // snapshot.
                        recoverFullPresentation(to: presentation, in: textView, reason: reason, intent: intent)
                    } else {
                        return
                    }
                    return
                }
                // `force` is used by state-changing callers to request prompt application. It
                // does not itself prove drift, and a refused command may leave this exact
                // snapshot in storage, so recovering without a mismatch would be spurious.
                guard force, textView.string != presentation.renderedString else { return }
                recoverFullPresentation(
                    to: presentation,
                    in: textView,
                    reason: .appliedStorageMismatch,
                    intent: intent
                )
                return
            }

            session.updateOrigin.with(.programmaticPresentation) {
                let built = buildPresentation(presentation, intent: intent)
                textStorageApplier.applyInitialPresentation(built, to: textView, intent: intent)
                appliedSnapshot = presentation
                appliedImageIdentities = imageIdentities(for: presentation)
                restoreSelection(for: presentation, in: textView, limit: built.attributed.length)
                // A document opens with the caret at its start, as TextEdit's do. Replacing the
                // storage left AppKit's caret at the end, and that is where the first keystroke
                // of a newly opened document went (NewWindowReadinessTests).
                if session.wysiwygModeState.selection == nil {
                    textView.setSelectedRange(NSRange(location: 0, length: 0))
                }
            }
        }

        /// Applies a newer snapshot without replacing the whole storage. A typed reason means
        /// the local proof failed and the caller must take the exceptional recovery route.
        private func incrementalRecoveryReason(
            from applied: PresentationSnapshot,
            to presentation: PresentationSnapshot,
            in textView: MarkdownWYSIWYGTextView,
            intent: IntentContext?,
            nativeTextAlreadyApplied: Bool
        ) -> PresentationRecoveryReason? {
            // Same text, new identity — an authoritative snapshot replacing a provisional one.
            // Attributes may differ; characters do not. Refreshing attributes is not a
            // replacement, so this stays outside the full-replacement allowlist.
            if applied.renderedString == presentation.renderedString {
                guard let scope = PresentationPatch.attributeRefreshScope(
                    current: applied,
                    next: presentation,
                    imageRefreshLocations: imageRefreshLocations(for: presentation)
                ) else {
                    return .patchUnprovable
                }
                var refreshed = false
                session.updateOrigin.with(.programmaticPresentation) {
                    refreshed = textStorageApplier.applyAttributeRefresh(
                        AttributedPresentationBuilder.buildScoped(
                            model: presentation.asProjectionModel,
                            theme: MarkdownTypography(),
                            images: session.resolvedImages,
                            onTaskPress: { [weak self] nodeID in self?.captureAndPerformTaskToggle(nodeID: nodeID) },
                            scope: scope,
                            intent: intent
                        ),
                        to: textView,
                        expectedCurrent: applied
                    )
                }
                if refreshed {
                    appliedSnapshot = presentation
                    appliedImageIdentities = imageIdentities(for: presentation)
                    return nil
                }
                return .appliedStorageMismatch
            }

            let selection = session.wysiwygModeState.selection.flatMap {
                $0.range.revision.snapshotID == presentation.id ? $0 : nil
            }
            if nativeTextAlreadyApplied,
               textView.string == presentation.renderedString,
               let patch = PresentationPatch.between(
                   current: applied,
                   next: presentation,
                   selectionAfter: selection,
                   buildScope: { [weak self] model, scope in
                       AttributedPresentationBuilder.buildScoped(
                           model: model,
                           theme: MarkdownTypography(),
                           images: self?.session.resolvedImages ?? [:],
                           onTaskPress: { nodeID in self?.captureAndPerformTaskToggle(nodeID: nodeID) },
                           scope: scope,
                           intent: intent
                       )
                   }
               ) {
                textView.beginLayoutApplication(for: patch.nextRange)
                var refreshed = false
                session.updateOrigin.with(.programmaticPresentation) {
                    refreshed = textStorageApplier.applyAlreadyAppliedPatch(
                        patch,
                        to: textView,
                        expectedNext: presentation
                    )
                }
                guard refreshed else {
                    textView.cancelLayoutApplication()
                    return .appliedStorageMismatch
                }
                appliedSnapshot = presentation
                appliedImageIdentities = imageIdentities(for: presentation)
                return nil
            }
            guard let patch = PresentationPatch.between(
                current: applied,
                next: presentation,
                selectionAfter: selection,
                buildScope: { [weak self] model, scope in
                    AttributedPresentationBuilder.buildScoped(
                        model: model,
                        theme: MarkdownTypography(),
                        images: self?.session.resolvedImages ?? [:],
                        onTaskPress: { nodeID in self?.captureAndPerformTaskToggle(nodeID: nodeID) },
                        scope: scope,
                        intent: intent
                    )
                }
            ) else {
                return .patchUnprovable
            }

            textView.beginLayoutApplication(for: patch.nextRange)
            var patched = false
            session.updateOrigin.with(.programmaticPresentation) {
                patched = textStorageApplier.applyPatch(patch, to: textView, expectedCurrent: applied)
            }
            guard patched else {
                textView.cancelLayoutApplication()
                return .appliedStorageMismatch
            }
            appliedSnapshot = presentation
            appliedImageIdentities = imageIdentities(for: presentation)
            // No selection fallback here on purpose. `selection` is nil exactly when the session
            // has no selection belonging to this snapshot — `installPresentation` clears it when
            // it cannot be carried forward — so there is nothing to restore, and a call guarded
            // by that same condition could only ever be a no-op.
            return nil
        }

        private func buildPresentation(_ snapshot: PresentationSnapshot, intent: IntentContext?) -> AttributedPresentation {
            AttributedPresentationBuilder.build(
                model: snapshot.asProjectionModel,
                theme: MarkdownTypography(),
                images: session.resolvedImages,
                onTaskPress: { [weak self] nodeID in
                    self?.captureAndPerformTaskToggle(nodeID: nodeID)
                },
                intent: intent
            )
        }

        private func imageRefreshLocations(for snapshot: PresentationSnapshot) -> Set<Int> {
            let current = imageIdentities(for: snapshot)
            return Set(snapshot.attachments.compactMap { attachment in
                guard case .image = attachment.kind,
                      appliedImageIdentities[attachment.nodeID] != current[attachment.nodeID]
                else { return nil }
                return attachment.utf16Location
            })
        }

        private func imageIdentities(for snapshot: PresentationSnapshot) -> [MarkdownNodeID: ObjectIdentifier] {
            Dictionary(
                uniqueKeysWithValues: snapshot.attachments.compactMap { attachment in
                    guard case .image = attachment.kind,
                          let image = session.resolvedImages[attachment.nodeID]
                    else { return nil }
                    return (attachment.nodeID, ObjectIdentifier(image))
                }
            )
        }

        private func restoreSelection(
            for presentation: PresentationSnapshot,
            in textView: NSTextView,
            limit: Int
        ) {
            guard let selection = session.wysiwygModeState.selection,
                  selection.range.revision.snapshotID == presentation.id else { return }
            let range = selection.range.utf16
            precondition(
                range.location >= 0 && NSMaxRange(range) <= limit,
                "Current typed selection is outside its presentation snapshot"
            )
            textView.setSelectedRange(range)
        }

        func hasAppliedSnapshot(_ id: PresentationSnapshot.ID) -> Bool {
            appliedSnapshotID == id
        }

        /// The caret AppKit shows becomes the owner's selection when the owner has none and the
        /// page has keyboard focus: when a new window's page gains focus, or a presentation lands
        /// under a focused page. Only a selection *change* reported it before, and an untouched
        /// caret never changes, so a new document's first keystroke and first command were
        /// refused as `ambiguousSelection` (agent-drive tour 45955987611). Deferred one turn so it
        /// never writes session state from inside view reconciliation (ARC-015), and it goes
        /// through the same guarded capture a real selection change does.
        func adoptNativeSelectionIfUnowned() {
            guard let textView, textView.window?.firstResponder === textView,
                  session.wysiwygModeState.selection == nil else { return }
            Task { @MainActor [weak self] in
                guard let self, let textView = self.textView,
                      textView.window?.firstResponder === textView,
                      self.session.wysiwygModeState.selection == nil,
                      self.session.updateOrigin.current == .nativeUserInput else { return }
                self.textViewDidChangeSelection(
                    Notification(name: NSTextView.didChangeSelectionNotification, object: textView)
                )
            }
        }

        func textView(
            _ textView: NSTextView,
            shouldChangeTextIn affectedCharRange: NSRange,
            replacementString: String?
        ) -> Bool {
            let nativeInputStart = DispatchTime.now().uptimeNanoseconds
            defer {
                session.recordPerformance(
                    .nativeInputCallback,
                    durationNanos: DispatchTime.now().uptimeNanoseconds &- nativeInputStart
                )
            }
            if session.updateOrigin.current != .nativeUserInput { return true }
            // Attribute-only changes (nil replacement) stay native.
            guard let replacement = replacementString else { return true }

            // REQ-084: marked-text / IME updates stay transient until composition completes.
            if input.committingComposition || input.allowingMarkedText || textView.hasMarkedText() || input.composition.isComposing {
                return true
            }

            guard let presentation = session.presentation,
                  case .editable(let id) = session.wysiwygModeState.availability,
                  id == presentation.id,
                  appliedSnapshotID == presentation.id,
                  textStorageApplier.isKnownCurrent(textView, expected: presentation),
                  affectedCharRange.location >= 0,
                  NSMaxRange(affectedCharRange) <= (presentation.renderedString as NSString).length
            else {
                // Applied storage is not the snapshot this keystroke targets. Resynchronizing is
                // a full replacement, so it is recorded for the same reason a post-commit
                // recovery is: storage drift must never be silent. So is the refused keystroke:
                // typing that vanished without a trace took an agent-drive run to see
                // (45943545906).
                document.trace?.record(route: .editRefused, .editRefused(category: .refusal(.stalePresentation)))
                applyProjectionIfNeeded(reason: .reapplyIfDrift)
                return false
            }
            let appliedPresentation = presentation

            // The owner's selection decides, affinity included: AppKit's affinity after a
            // programmatic insertion need not match the owner's for the same caret, and comparing
            // it refused every keystroke after the first (agent-drive run 45944610103).
            let nativeRange = ProjectionRange(affectedCharRange, revision: presentation.projectionRevision)
            guard let ownerSelection = session.wysiwygModeState.selection,
                  let resolved = Self.command(
                      replacing: affectedCharRange,
                      with: replacement,
                      owner: ownerSelection,
                      native: nativeRange,
                      presentation: presentation
                  ) else {
                // The native selection callback is the owner-state capture point. A mutation
                // callback cannot promote its affected range into current state after the fact.
                document.trace?.record(route: .editRefused, .editRefused(category: .refusal(.ambiguousSelection)))
                applyProjectionIfNeeded(reason: .reapplyIfDrift)
                return false
            }
            let (command, projectionSelection) = resolved
            if projectionSelection != ownerSelection {
                // A deletion AppKit derived from the caret, such as Option-Delete or Forward
                // Delete: the range it names becomes the owner's selection, as the caret it
                // came from was.
                session.captureSelection(.projection(projectionSelection))
            }
            let outcome = session.perform(
                command,
                selection: .projection(projectionSelection),
                expectedSourceRevision: SourceRevision(value: document.sourceVersion),
                inputRoute: .wysiwygReplacement
            )
            switch outcome {
            case .accepted(let edit):
                // REQ-091; ARC-005: apply the accepted presentation transition programmatically
                // and refuse TextKit's optimistic second mutation.
                guard let wysiwygTextView = self.textView else { return false }
                applyAcceptedEdit(edit, from: appliedPresentation, in: wysiwygTextView)
                return false
            case .refused:
                return false
            }
        }

        /// The semantic command a native replacement asks for, and the selection it acts on.
        ///
        /// The owner's selection decides. A replacement of exactly that selection is typing,
        /// Return or a deletion of it. A deletion next to a collapsed caret is AppKit's own reading
        /// of Delete, which names the character before the caret (or the word, or the character
        /// after) rather than the caret: refused as a mismatch, Backspace did nothing in WYSIWYG.
        /// Backspace over a block boundary is the block planner's.
        nonisolated static func command(
            replacing affected: NSRange,
            with replacement: String,
            owner: ProjectionSelection,
            native: ProjectionRange,
            presentation: PresentationSnapshot
        ) -> (SemanticCommand, ProjectionSelection)? {
            if owner.range == native {
                if replacement.isEmpty, affected.length > 0 { return (.insertText(""), owner) }
                if replacement.isEmpty {
                    let caret = affected.location
                    return (BlockBoundaryPlanner.deletesBlockBoundary(atCaret: caret, in: presentation) ? .joinBlockBackward : .deleteBackward, owner)
                }
                if isParagraphBreak(replacement) { return (.insertParagraphBreak, owner) }
                return (.insertText(replacement), owner)
            }
            let caret = owner.range.utf16
            guard replacement.isEmpty,
                  caret.length == 0,
                  affected.length > 0,
                  owner.range.revision == native.revision,
                  NSMaxRange(affected) == caret.location || affected.location == caret.location else {
                return nil
            }
            let rendered = presentation.renderedString as NSString
            if NSMaxRange(affected) == caret.location,
               affected == rendered.rangeOfComposedCharacterSequence(at: caret.location - 1) {
                let command: SemanticCommand = BlockBoundaryPlanner.deletesBlockBoundary(atCaret: caret.location, in: presentation)
                    ? .joinBlockBackward
                    : .deleteBackward
                return (command, owner)
            }
            return (.insertText(""), ProjectionSelection(utf16: affected, revision: native.revision, affinity: owner.affinity))
        }

        /// Return and Enter, as AppKit spells them.
        nonisolated static func isParagraphBreak(_ text: String) -> Bool {
            text == "\n" || text == "\r" || text == "\r\n" || text == "\u{2029}"
        }

        func applyAcceptedEdit(
            _ edit: AcceptedEdit,
            from current: PresentationSnapshot,
            in textView: MarkdownWYSIWYGTextView
        ) {
            guard let transition = edit.presentationTransition else {
                preconditionFailure("Accepted WYSIWYG edit must carry a presentation transition")
            }
            // Only the touched semantic block scope is turned into attributed content. Building
            // the complete next presentation here would put the whole document's cost inside
            // every keystroke, which is exactly what ARC-019 exists to prevent.
            guard let patch = PresentationPatch.make(
                transition: transition,
                current: current,
                buildScope: { [weak self] model, scope in
                    AttributedPresentationBuilder.buildScoped(
                        model: model,
                        theme: MarkdownTypography(),
                        images: self?.session.resolvedImages ?? [:],
                        onTaskPress: { nodeID in self?.captureAndPerformTaskToggle(nodeID: nodeID) },
                        scope: scope,
                        intent: edit.intent
                    )
                }
            ) else {
                recoverFullPresentation(
                    to: transition.nextSnapshot,
                    in: textView,
                    reason: .patchUnprovable,
                    intent: edit.intent
                )
                return
            }
            textView.beginLayoutApplication(for: patch.nextRange)
            session.updateOrigin.with(.programmaticPresentation) {
                guard textStorageApplier.applyPatch(patch, to: textView, expectedCurrent: current) else {
                    textView.cancelLayoutApplication()
                    recoverFullPresentation(
                        to: transition.nextSnapshot,
                        in: textView,
                        reason: .appliedStorageMismatch,
                        intent: edit.intent
                    )
                    return
                }
                appliedSnapshot = transition.nextSnapshot
            }
        }

        /// The only route from an accepted edit to a full replacement. It is an invariant
        /// violation, not a fallback: it records a typed reason and makes WYSIWYG unavailable
        /// until an authoritative reconciliation lands, so a recovery can never be mistaken for
        /// an ordinary edit that happened to be slow.
        private func recoverFullPresentation(
            to snapshot: PresentationSnapshot,
            in textView: NSTextView,
            reason: PresentationRecoveryReason,
            intent: IntentContext?
        ) {
            document.trace?.record(route: .presentationRecovered, .presentationRecovered(
                    snapshotID: snapshot.id.value,
                    sourceRevision: snapshot.sourceRevision.value,
                    reason: reason
                )
            )
            session.updateWYSIWYGModeState {
                $0.availability = .waitingForCurrentProjection(snapshot.sourceRevision)
            }
            // The session state will also disable this view during the next host reconciliation,
            // but recovery is synchronous: leave no native-input window where stale rich text can
            // accept another edit before SwiftUI observes the new availability.
            textView.isEditable = false
            let built = AttributedPresentationBuilder.build(
                model: snapshot.asProjectionModel,
                theme: MarkdownTypography(),
                images: session.resolvedImages,
                onTaskPress: { [weak self] nodeID in
                    self?.captureAndPerformTaskToggle(nodeID: nodeID)
                },
                intent: intent
            )
            session.updateOrigin.with(.programmaticPresentation) {
                textStorageApplier.applyRecoveryPresentation(built, to: textView, intent: intent)
            }
            appliedSnapshot = snapshot
            appliedImageIdentities = imageIdentities(for: snapshot)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView else { return }
            // REQ-094; ARC-013/015: a programmatic set is restoring a value the session already
            // holds. Writing it back turns restoration into a state change and, when the set
            // happens during reconciliation, into a self-feeding update loop.
            guard session.updateOrigin.current == .nativeUserInput else { return }
            let range = textView.selectedRange()
            if let presentation = session.presentation,
               case .editable(let id) = session.wysiwygModeState.availability,
               id == presentation.id,
               appliedSnapshotID == presentation.id,
               textView.string == presentation.renderedString,
               range.location >= 0,
               NSMaxRange(range) <= (presentation.renderedString as NSString).length {
                session.updateWYSIWYGModeState { state in
                    state.selection = ProjectionSelection(
                        utf16: range,
                        revision: presentation.projectionRevision,
                        affinity: textView.selectionAffinity == .upstream ? .upstream : .downstream
                    )
                }
            }
        }

        /// Task attachment presses are native action events, so their identity is captured at
        /// this callback boundary before the semantic command is planned. The mutation produced
        /// by that command cannot write this state back into the owner.
        private func captureAndPerformTaskToggle(nodeID: MarkdownNodeID) {
            guard let presentation = session.presentation,
                  let attachment = presentation.attachments.first(where: { $0.nodeID == nodeID }) else {
                return
            }
            session.captureSelection(.projection(
                ProjectionSelection(
                    utf16: NSRange(location: attachment.utf16Location, length: 1),
                    revision: presentation.projectionRevision
                )
            ))
            performTaskToggle(nodeID: nodeID)
        }

        func performTaskToggle(nodeID: MarkdownNodeID) {
            guard let presentation = session.presentation,
                  let attachment = presentation.attachments.first(where: { $0.nodeID == nodeID }) else {
                return
            }
            let selection = ProjectionSelection(
                utf16: NSRange(location: attachment.utf16Location, length: 1),
                revision: presentation.projectionRevision
            )
            guard session.wysiwygModeState.selection == selection else { return }
            _ = session.perform(
                .toggleTask(nodeID: nodeID),
                selection: .projection(selection),
                expectedSourceRevision: presentation.sourceRevision,
                inputRoute: .checkbox
            )
            applyProjectionIfNeeded(reason: .reapplyIfDrift)
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
final class MarkdownWYSIWYGTextView: NSTextView, NSLayoutManagerDelegate {
    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { adapterCoordinator?.adoptNativeSelectionIfUnowned() }
        return accepted
    }

    weak var session: EditorSession?
    weak var documentActions: DocumentActionInterface?
    weak var placementController: ImagePlacementController?
    weak var inputCoordinator: WYSIWYGEditor.WYSIWYGInputCoordinator?
    weak var adapterCoordinator: WYSIWYGEditor.Coordinator?

    /// REQ-116; ARC-020: measures layout for a changed presentation range through TextKit's
    /// completed-layout callback. Caret repaints call `draw(_:)` too, but do not apply a pending
    /// range and therefore cannot create a layout sample.
    private var pendingLayoutApplication: (range: NSRange, started: UInt64)?

    /// AppKit can retain a stale marked range after `unmarkText()` in a headless component test.
    /// The coordinator's composition state is the authoritative native-input identity, so expose
    /// its cleared state consistently through both NSTextInputClient queries.
    override func hasMarkedText() -> Bool {
        if let inputCoordinator { return inputCoordinator.composition.isComposing }
        return super.hasMarkedText()
    }

    override func markedRange() -> NSRange {
        if let inputCoordinator {
            return inputCoordinator.composition.markedRange
                ?? NSRange(location: NSNotFound, length: 0)
        }
        return super.markedRange()
    }

    func beginLayoutApplication(for range: NSRange) {
        guard range.location >= 0 else { return }
        layoutManager?.delegate = self
        pendingLayoutApplication = (
            range: range,
            started: DispatchTime.now().uptimeNanoseconds
        )
    }

    func cancelLayoutApplication() {
        pendingLayoutApplication = nil
    }

    func layoutManager(
        _ layoutManager: NSLayoutManager,
        didCompleteLayoutFor textContainer: NSTextContainer?,
        atEnd layoutFinished: Bool
    ) {
        guard layoutFinished, textContainer != nil, let pending = pendingLayoutApplication else { return }
        pendingLayoutApplication = nil
        guard let textStorage,
              pending.range.location <= textStorage.length,
              NSMaxRange(pending.range) <= textStorage.length else { return }
        session?.recordPerformance(
            .layoutApplication,
            durationNanos: DispatchTime.now().uptimeNanoseconds &- pending.started
        )
    }

    override func layout() {
        super.layout()
        guard bounds.width > 0, let textContainer else { return }
        let horizontalInset = max(
            MarkdownTypography.minimumHorizontalInset,
            (bounds.width - MarkdownTypography.maximumReadingMeasure) / 2
        )
        let measure = max(1, bounds.width - (horizontalInset * 2))
        let wantedInset = NSSize(
            width: horizontalInset,
            height: MarkdownTypography.minimumVerticalInset
        )
        if textContainerInset != wantedInset {
            textContainerInset = wantedInset
        }
        textContainer.widthTracksTextView = false
        if textContainer.containerSize.width != measure {
            textContainer.containerSize = NSSize(
                width: measure,
                height: CGFloat.greatestFiniteMagnitude
            )
        }
    }

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
        guard let documentActions else {
            super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
            return
        }
        // This is the native IME event boundary. Capture the pre-composition caret before the
        // transient update is reduced; the later source commit must validate against this state,
        // never against its proposed replacement range.
        if let session, let presentation = session.presentation {
            session.captureSelection(.projection(
                ProjectionSelection(
                    utf16: self.selectedRange(),
                    revision: presentation.projectionRevision,
                    affinity: selectionAffinity == .upstream ? .upstream : .downstream
                )
            ))
        }
        let updateInput = EditorInput.markedText(
            EditorMarkedTextInput(
                phase: .update,
                sourceRevision: SourceRevision(value: version),
                projectionID: session?.presentation?.id
            )
        )
        let updateResult = session?.commitEditorInput(updateInput)
            ?? documentActions.commitEditorInput(updateInput)
        guard case .committed = updateResult else {
            if cancelMarkedTextForInput() {
                (documentActions as? MarkdownDocument)?.trace?.record(route: .compositionCancelled, .compositionCancelled)
            }
            return
        }
        inputCoordinator?.beginMarkedText(
            sourceVersion: version,
            sourceRange: sourceRange,
            marked: NSRange(location: sourceRange.location, length: markedLength),
            snapshotID: session?.presentation?.id
        )
        inputCoordinator?.allowingMarkedText = true
        if let session {
            session.updateOrigin.with(.composition) {
                super.setMarkedText(
                    string,
                    selectedRange: selectedRange,
                    replacementRange: replacementRange
                )
            }
        } else {
            super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
        }
        inputCoordinator?.allowingMarkedText = false
        (documentActions as? MarkdownDocument)?.trace?.record(route: .compositionBegan, .compositionBegan(sourceVersion: version))
    }

    override func unmarkText() {
        // Some IMEs finish composition via unmarkText rather than insertText. Commit the
        // marked characters to source before clearing composition state; empty marked text
        // (Escape / cancel) still cancels without a source write.
        if let input = inputCoordinator, input.committingComposition {
            performNativeUnmark()
            return
        }
        if let input = inputCoordinator, input.composition.isComposing || hasMarkedText() {
            let marked = markedRange()
            let text: String
            if marked.location != NSNotFound, let storage = textStorage {
                guard marked.location >= 0, NSMaxRange(marked) <= storage.length else {
                    guard cancelMarkedTextForInput() else { return }
                    (documentActions as? MarkdownDocument)?.trace?.record(route: .compositionCancelled, .compositionCancelled)
                    return
                }
                text = (storage.string as NSString).substring(with: marked)
            } else {
                text = ""
            }
            if text.isEmpty {
                guard cancelMarkedTextForInput() else { return }
                (documentActions as? MarkdownDocument)?.trace?.record(route: .compositionCancelled, .compositionCancelled)
                return
            }
            _ = commitComposition(text: text)
            return
        }
        guard cancelMarkedTextForInput() else { return }
        (documentActions as? MarkdownDocument)?.trace?.record(route: .compositionCancelled, .compositionCancelled)
    }

    /// Reduces cancellation before touching native marked-text state. A refusal leaves both the
    /// document-owned undo group and AppKit composition state untouched for the caller to recover.
    private func cancelMarkedTextForInput() -> Bool {
        guard reduceMarkedTextPhase(.cancel) else { return false }
        inputCoordinator?.cancel()
        performNativeUnmark()
        return true
    }

    @discardableResult
    private func reduceMarkedTextPhase(_ phase: EditorMarkedTextInput.Phase) -> Bool {
        let snapshot = documentActions?.sourceSnapshot()
        let input = EditorInput.markedText(
            EditorMarkedTextInput(
                phase: phase,
                sourceRevision: snapshot.map { SourceRevision(value: $0.sourceVersion) },
                projectionID: session?.presentation?.id
            )
        )
        let result = session?.commitEditorInput(input)
            ?? documentActions?.commitEditorInput(input)
        if case .committed = result { return true }
        return false
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

        _ = commitComposition(text: text)
    }

    /// The single route from a completed IME composition to a source transaction. Both
    /// `insertText`- and `unmarkText`-terminated compositions use this route so their stale
    /// handling, snapshot validation, source commit, trace, and native cleanup cannot diverge.
    @discardableResult
    private func commitComposition(text: String) -> Bool {
        guard let input = inputCoordinator else { return false }
        let currentVersion = documentActions?.sourceSnapshot().sourceVersion ?? 0
        guard input.prepareCommit(currentVersion: currentVersion),
              let captured = input.complete() else {
            guard cancelMarkedTextForInput() else { return false }
            (documentActions as? MarkdownDocument)?.trace?.record(route: .compositionRefusedStale, .compositionRefusedStale)
            return false
        }
        guard let session,
              let presentation = session.presentation,
              let capturedSnapshotID = captured.snapshotID,
              presentation.id == capturedSnapshotID,
              adapterCoordinator?.hasAppliedSnapshot(capturedSnapshotID) == true else {
            guard cancelMarkedTextForInput() else { return false }
            (documentActions as? MarkdownDocument)?.trace?.record(route: .compositionCancelled, .compositionCancelled)
            return false
        }
        guard let ownerSelection = session.wysiwygModeState.selection,
              ownerSelection.range.utf16 == captured.range,
              ownerSelection.range.revision.snapshotID == presentation.id else {
            guard cancelMarkedTextForInput() else { return false }
            (documentActions as? MarkdownDocument)?.trace?.record(route: .compositionCancelled, .compositionCancelled)
            return false
        }
        let selection = ProjectionSelection(
            utf16: captured.range,
            revision: presentation.projectionRevision,
            affinity: ownerSelection.affinity
        )
        let result = session.perform(
            .insertText(text),
            selection: .projection(selection),
            expectedSourceRevision: SourceRevision(value: captured.version),
            inputRoute: .markedText
        )
        switch result {
        case .accepted:
            (documentActions as? MarkdownDocument)?.trace?.record(route: .compositionCommitted, .compositionCommitted(sourceVersion: captured.version, replacementLength: (text as NSString).length)
            )
            input.committingComposition = true
            input.allowingMarkedText = true
            performNativeUnmark()
            input.allowingMarkedText = false
            input.committingComposition = false
            adapterCoordinator?.applyProjectionIfNeeded(
                reason: .reapplyIfDrift,
                nativeTextAlreadyApplied: true
            )
            return true
        case .refused:
            guard cancelMarkedTextForInput() else { return false }
            (documentActions as? MarkdownDocument)?.trace?.record(route: .compositionCancelled, .compositionCancelled)
            return false
        }
    }

    private func performNativeUnmark() {
        if let session {
            session.updateOrigin.with(.composition) {
                super.unmarkText()
            }
        } else {
            super.unmarkText()
        }
    }

    // MARK: - Task checkbox: mouse, Space, Return, accessibility (REQ-078/032/084)

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let index = characterIndexForAttachment(at: point) {
            if let session,
               let presentation = session.presentation {
                session.captureSelection(.projection(
                    ProjectionSelection(
                        utf16: NSRange(location: index, length: 1),
                        revision: presentation.projectionRevision
                    )
                ))
            }
            if toggleTask(atUTF16: index) { return }
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
              let presentation = session.presentation,
              let attachment = presentation.attachments.first(where: { $0.utf16Location == index }),
              case .task = attachment.kind else {
            return false
        }
        let selection = ProjectionSelection(
            utf16: NSRange(location: index, length: 1),
            revision: presentation.projectionRevision
        )
        guard session.wysiwygModeState.selection == selection else { return false }
        let result = session.perform(
            .toggleTask(nodeID: attachment.nodeID),
            selection: .projection(selection),
            expectedSourceRevision: presentation.sourceRevision,
            inputRoute: .checkbox
        )
        if case .accepted = result { return true }
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

    /// Resolve the live WYSIWYG selection to an immutable source-domain placement intent.
    ///
    /// // REQ-060; ARC-012: capture before asynchronous paste/drop work.
    private func imagePlacementTarget() -> ImagePlacementTarget? {
        guard let actions = documentActions,
              let session,
              let presentation = session.presentation,
              case .editable(let id) = session.wysiwygModeState.availability,
              id == presentation.id else {
            return nil
        }
        let snapshot = actions.sourceSnapshot()
        guard presentation.sourceRevision.value == snapshot.sourceVersion else { return nil }
        switch presentation.coordinateMap.sourceRange(
            forProjection: selectedRange(),
            affinity: selectionAffinity == .upstream ? .upstream : .downstream
        ) {
        case .exact(let sourceRange):
            return ImagePlacementTarget(
                sourceSelection: SourceSelection(
                    utf16: sourceRange,
                    affinity: selectionAffinity == .upstream ? .upstream : .downstream
                ),
                sourceRevision: SourceRevision(value: snapshot.sourceVersion),
                locationGeneration: snapshot.locationGeneration,
                operationID: UUID()
            )
        case .refused:
            return nil
        }
    }

    override func paste(_ sender: Any?) {
        let classification = ImagePasteboardClassifier.classifyPasteboard(.general)
        switch classification {
        case .images(let claims):
            guard let target = imagePlacementTarget() else {
                placementController?.presentAlert(.error("Could not resolve image insertion point."), reason: .noInsertionTarget)
                return
            }
            placementController?.handleImageAction(
                intent: ImagePlacementIntent(target: target, claims: claims),
                documentURL: documentActions?.sourceSnapshot().fileURL
            )
        case .fallthroughToNativeText, .unsupported:
            if case .unsupported = classification {
                placementController?.presentAlert(.error(ImagePlacementError.unsupportedOrCorrupt.userMessage), reason: .pasteboardUnsupportedOrCorrupt)
                return
            }
            // REQ-059: always paste plain text even when RTF/HTML are available.
            if let plain = PastePolicy.plainText(from: .general) {
                _ = pastePlainText(plain)
            }
        }
    }

    /// Apply plain-text paste as the same atomic source/presentation transaction as typing.
    ///
    /// Exposed to integration tests so paste behavior is verified without UI automation.
    @discardableResult
    func pastePlainText(_ plain: String) -> Bool {
        guard let session,
              let presentation = session.presentation,
              let adapterCoordinator,
              let snapshot = documentActions?.sourceSnapshot(),
              presentation.sourceRevision.value == snapshot.sourceVersion else {
            return false
        }
        let appliedPresentation = presentation
        let selection = ProjectionSelection(
            utf16: selectedRange(),
            revision: presentation.projectionRevision,
            affinity: selectionAffinity == .upstream ? .upstream : .downstream
        )
        guard session.wysiwygModeState.selection == selection else { return false }
        // Paste must not coalesce into an open typing undo group (REQ-016).
        let outcome = session.perform(
            .insertText(plain),
            selection: .projection(selection),
            expectedSourceRevision: SourceRevision(value: snapshot.sourceVersion),
            grouping: .discrete,
            inputRoute: .wysiwygReplacement
        )
        guard case .accepted(let edit) = outcome else { return false }
        adapterCoordinator.applyAcceptedEdit(edit, from: appliedPresentation, in: self)
        return true
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pb = sender.draggingPasteboard
        let url = documentActions?.sourceSnapshot().fileURL
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
                placementController?.presentAlert(.error(ImagePlacementError.unsupportedOrCorrupt.userMessage), reason: .pasteboardUnsupportedOrCorrupt)
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
