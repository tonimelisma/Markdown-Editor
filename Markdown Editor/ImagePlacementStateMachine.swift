//
//  ImagePlacementStateMachine.swift
//  Markdown Editor
//

import Foundation

// REQ-060/069: pure reducer — one owner, one terminal outcome, UUID-gated results.

nonisolated enum ImagePlacementEvent: Sendable {
    case begin(ImageActionID)
    case startReceivingPromises
    case startAwaitingSave
    case promisesReceived
    case saveSucceeded
    case saveCancelledOrFailed
    case startStaging
    case startPublishing
    case startCommitting
    case succeed
    case fail(ImagePlacementError)
    case cancel
}

nonisolated struct ImagePlacementState: Equatable, Sendable {
    var phase: ImagePlacementPhase = .idle
    var activeID: ImageActionID?

    var isTerminal: Bool {
        switch phase {
        case .committed, .cancelled, .failed, .idle: return true
        default: return false
        }
    }

}

nonisolated enum ImagePlacementReducer {
    /// Returns the next state, or `nil` if the event must be ignored (wrong UUID / illegal).
    static func reduce(
        state: ImagePlacementState,
        event: ImagePlacementEvent,
        actionID: ImageActionID?
    ) -> ImagePlacementState? {
        var next = state
        switch event {
        case .begin(let id):
            guard state.phase == .idle else { return nil }
            next.phase = .accepted
            next.activeID = id
            return next

        default:
            guard let actionID, state.activeID == actionID else { return nil }
        }

        switch (state.phase, event) {
        case (.accepted, .startReceivingPromises):
            next.phase = .receivingPromises
        case (.accepted, .startAwaitingSave):
            next.phase = .awaitingSave
        case (.accepted, .startStaging),
             (.receivingPromises, .startStaging),
             (.awaitingSave, .startStaging):
            next.phase = .staging
        case (.receivingPromises, .promisesReceived):
            next.phase = .accepted
        case (.awaitingSave, .saveSucceeded):
            next.phase = .accepted
        case (.awaitingSave, .saveCancelledOrFailed):
            next.phase = .cancelled
            next.activeID = nil
        case (.staging, .startPublishing):
            next.phase = .publishing
        case (.publishing, .startCommitting):
            next.phase = .committing
        case (.committing, .succeed),
             (.publishing, .succeed):
            // allow succeed from publishing if commit is immediate
            next.phase = .committed
            next.activeID = nil
        case (_, .succeed) where state.phase == .committing:
            next.phase = .committed
            next.activeID = nil
        case (_, .fail(let error)):
            guard !state.isTerminal || state.phase == .accepted || state.phase == .staging
                    || state.phase == .publishing || state.phase == .committing
                    || state.phase == .receivingPromises || state.phase == .awaitingSave else {
                return nil
            }
            _ = error
            next.phase = .failed
            next.activeID = nil
        case (_, .cancel):
            guard !state.isTerminal || state.phase == .accepted || state.phase == .staging
                    || state.phase == .publishing || state.phase == .committing
                    || state.phase == .receivingPromises || state.phase == .awaitingSave else {
                return nil
            }
            next.phase = .cancelled
            next.activeID = nil
        default:
            return nil
        }
        return next
    }
}
