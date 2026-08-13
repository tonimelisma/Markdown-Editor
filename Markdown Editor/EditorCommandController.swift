//
//  EditorCommandController.swift
//  Markdown Editor
//

import AppKit
import Combine

nonisolated enum EditorCommandResult: Equatable, Sendable {
    case accepted
    case started
    case refused
    case disabled(EditorCommandDisabledReason)
}

/// One command authority per document window.
@MainActor
final class EditorCommandController: ObservableObject {
    weak var document: MarkdownDocument?
    weak var session: EditorSession?
    weak var actionRouter: EditorActionRouter?
    weak var presentingWindow: NSWindow?

    @Published private(set) var linkSheetPresented = false
    @Published private(set) var linkDestination = ""

    func bind(
        document: MarkdownDocument,
        session: EditorSession,
        actionRouter: EditorActionRouter,
        window: NSWindow?
    ) {
        self.document = document
        self.session = session
        self.actionRouter = actionRouter
        self.presentingWindow = window
    }

    func availability(for command: EditorCommand) -> EditorCommandAvailability {
        guard let document, let session else { return .disabled(.noDocument) }
        switch command {
        case .sourceMode, .wysiwygMode:
            return .enabled
        case .addImage:
            return session.canAddImages ? .enabled : .disabled(.unavailablePresentation)
        case .editLink:
            guard selectionLength(in: session) > 0 else { return .disabled(.noSelection) }
            return session.mode == .wysiwyg && session.presentation == nil
                ? .disabled(.unavailablePresentation) : .enabled
        case .codeBlock:
            // COR-38: retired stage-1 dry-run. After .normalizedCodeBlock atomic, CRLF code is
            // no longer .uneditable, so availability collapses to the default branch.
            // Target-covering .uneditable (e.g. raw HTML at caret) is still refused by the
            // planner via REQ-113, not by availability.
            fallthrough
        default:
            guard session.mode == .source || isCurrentWYSIWYG(session) else {
                return .disabled(.unavailablePresentation)
            }
            _ = document
            return .enabled
        }
    }

    @discardableResult
    func perform(_ command: EditorCommand) -> EditorCommandResult {
        guard availability(for: command).isEnabled else {
            if case .disabled(let reason) = availability(for: command) { return .disabled(reason) }
            return .disabled(.detached)
        }
        guard let document, let session else { return .disabled(.noDocument) }
        switch command {
        case .sourceMode:
            session.setMode(.source)
            return .accepted
        case .wysiwygMode:
            session.setMode(.wysiwyg)
            return .accepted
        case .addImage:
            Task { await session.addImages() }
            return .started
        case .editLink:
            linkDestination = linkDestinationForCurrentSelection(in: session) ?? ""
            linkSheetPresented = true
            return .started
        case .removeLink:
            return route(.setLink(destination: nil), document: document, session: session)
        default:
            guard let semantic = command.semanticCommand else { return .disabled(.detached) }
            return route(semantic, document: document, session: session)
        }
    }

    func commitLink(destination: String) {
        guard let document, let session else { return }
        let normalizedDestination = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        _ = route(
            .setLink(destination: normalizedDestination.isEmpty ? nil : normalizedDestination),
            document: document,
            session: session
        )
        linkSheetPresented = false
    }

    func cancelLink() { linkSheetPresented = false }

    func updateLinkDestination(_ value: String) { linkDestination = value }

    private func route(
        _ command: SemanticCommand,
        document: MarkdownDocument,
        session: EditorSession
    ) -> EditorCommandResult {
        let outcome = session.perform(
            command,
            selection: currentSelection(in: session),
            expectedSourceRevision: SourceRevision(value: document.sourceVersion),
            intentScope: .semanticCommand
        )
        if case .accepted = outcome { return .accepted }
        return .refused
    }

    private func currentSelection(in session: EditorSession) -> EditorSelection {
        switch session.mode {
        case .source:
            return .source(session.sourceModeState.selection)
        case .wysiwyg:
            if let selection = session.wysiwygModeState.selection { return .projection(selection) }
            if let presentation = session.presentation,
               case .editable(let id) = session.wysiwygModeState.availability,
               id == presentation.id {
                return .projection(ProjectionSelection(utf16: NSRange(location: 0, length: 0), revision: presentation.projectionRevision))
            }
            return .source(session.sourceModeState.selection)
        }
    }

    private func selectionLength(in session: EditorSession) -> Int {
        switch currentSelection(in: session) {
        case .source(let selection): return selection.range.utf16.length
        case .projection(let selection): return selection.range.utf16.length
        }
    }

    private func isCurrentWYSIWYG(_ session: EditorSession) -> Bool {
        guard let presentation = session.presentation,
              case .editable(let id) = session.wysiwygModeState.availability else { return false }
        return id == presentation.id
    }

    private func linkDestinationForCurrentSelection(in session: EditorSession) -> String? {
        guard session.mode == .wysiwyg,
              let presentation = session.presentation,
              let selection = session.wysiwygModeState.selection,
              selection.range.revision.snapshotID == presentation.id else { return nil }
        return presentation.runs.first {
            $0.linkDestination != nil && NSIntersectionRange($0.utf16Range, selection.range.utf16).length > 0
        }?.linkDestination
    }
}
