//
//  DocumentLoadGate.swift
//  Markdown Editor
//

import Foundation
import Synchronization

/// Generation-bound load application state shared between background `read` and main-actor apply.
///
/// // REQ-015: a delayed read cannot overwrite a newer committed mutation.
struct DocumentLoadGateState: Sendable {
    var generation: UInt64 = 0
    /// Mirror of `MarkdownDocument.sourceVersion`, updated on every main-actor mutation/load.
    var revisionMirror: UInt64 = 0
    /// Revision captured when the current in-flight load began (`nil` = no pending load).
    var pendingBeganRevision: UInt64?
}

final class DocumentLoadGate: Sendable {
    private let lock = Mutex(DocumentLoadGateState())

    /// Begins a load: bumps generation, captures the mirrored revision, returns the token.
    nonisolated func beginLoad() -> (token: UInt64, beganAtRevision: UInt64) {
        lock.withLock { state in
            state.generation &+= 1
            let began = state.revisionMirror
            state.pendingBeganRevision = began
            return (state.generation, began)
        }
    }

    /// Updates the mirrored revision after a committed mutation or successful load apply.
    nonisolated func setRevisionMirror(_ revision: UInt64) {
        lock.withLock { $0.revisionMirror = revision }
    }

    /// Validates that `token` is still current and no mutation advanced past `beganAtRevision`.
    nonisolated func validateApplication(token: UInt64, beganAtRevision: UInt64) -> Bool {
        lock.withLock { state in
            guard token == state.generation else { return false }
            guard state.revisionMirror == beganAtRevision else { return false }
            return true
        }
    }

    /// Clears the pending-load marker after a successful or abandoned application.
    nonisolated func clearPending() {
        lock.withLock { $0.pendingBeganRevision = nil }
    }

    /// Test seam: inspect current generation.
    nonisolated func currentGenerationForTesting() -> UInt64 {
        lock.withLock { $0.generation }
    }
}
