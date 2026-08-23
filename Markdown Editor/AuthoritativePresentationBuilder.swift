//
//  AuthoritativePresentationBuilder.swift
//  Markdown Editor
//

import Foundation
import Synchronization

/// Builds complete authoritative presentations away from the main actor.
///
/// Semantic formatting commands may wait for this exact result, but parser, index, and
/// projection work execute on this private worker queue. Ordinary typing uses local transitions.
/// // REQ-085; ARC-Q06
nonisolated enum AuthoritativePresentationBuilder {

    /// Everything `build` is a function of.
    ///
    /// // If two calls agree on all four, they must produce the same snapshot: the body below is
    /// // a pure composition of `MarkdownSourceIndex`, `MarkdownParser`, `MarkdownProjectionModel`
    /// // and `PresentationSnapshot.from`, none of which reads mutable state.
    private struct Key: Hashable, Sendable {
        let source: String
        let sourceRevision: UInt64
        let snapshotID: PresentationSnapshot.ID
        let locationGeneration: UInt64
    }

    /// The most recent build, reused when the same key is requested again.
    ///
    /// // COR-89: one semantic command called this **three times** with an identical key — once in
    /// // `SemanticEditEngine.planAuthoritativeTransition` to produce the snapshot, then twice more
    /// // in `EditorTransactionKernel.validateAcceptedEdit`, reached from
    /// // `EditorTransactionKernel.reduce` and again from `MarkdownDocument.commitEditorTransaction`,
    /// // each rebuilding the whole document to compare against the snapshot just produced. On the
    /// // approved corpus that was ~27 ms × 3 on the main actor, per keystroke-free command
    /// // (`research/2026-08-22-semantic-command-main-actor-cost.md`, Finding 9).
    /// //
    /// // **This weakens no validation.** The owner-boundary proof still rebuilds from the source
    /// // it independently derived and still compares; memoising a pure function is
    /// // indistinguishable from recomputing it. A forged snapshot is caught exactly as before: it
    /// // was never stored under this key, so the lookup misses and the real build runs. A planner
    /// // that used the builder correctly and then returned something else is caught too — the
    /// // cached value is what the builder produced, and the comparison is against what the planner
    /// // returned.
    /// //
    /// // One entry, not a cache: the three calls share a key within one command, and the next
    /// // command has a new source revision and snapshot ID. Nothing stale can be served, and the
    /// // retained snapshot is the one the session already holds.
    private static let memo = Mutex<(key: Key, value: PresentationSnapshot?)?>(nil)

    /// Whole-document builds actually performed, for tests that assert how much work a route does.
    ///
    /// // `WorkLedger.documentParses` is the production instrument for this and is written to
    /// // every run log. It is unreadable from a unit test, because `EditorSession` installs a
    /// // durable work-ledger writer on its own recorder whenever a diagnostic log exists, and
    /// // that writer takes precedence over an injected reporter. This counter is the test seam;
    /// // it is inventoried by `ProductionTestHookInventoryTests`.
    private static let performedBuilds = Mutex<Int>(0)

    static var performedBuildCountForTesting: Int {
        performedBuilds.withLock { $0 }
    }

    static func build(
        source: String,
        sourceRevision: UInt64,
        snapshotID: PresentationSnapshot.ID,
        locationGeneration: UInt64,
        intent: IntentContext? = nil
    ) -> PresentationSnapshot? {
        let key = Key(
            source: source,
            sourceRevision: sourceRevision,
            snapshotID: snapshotID,
            locationGeneration: locationGeneration
        )
        if let entry = memo.withLock({ $0 }), entry.key == key {
            // A hit performs no parse, no projection and no main-actor wait, so it deliberately
            // records none: the work ledger counts work that happened.
            return entry.value
        }

        let built: PresentationSnapshot? = EditorSemanticWorker.sync(intent: intent) {
            let index = MarkdownSourceIndex(source: source, sourceVersion: sourceRevision)
            guard case .success(let tree) = MarkdownParser.parse(
                source,
                sourceVersion: sourceRevision,
                intent: intent
            ) else {
                return PresentationSnapshot?.none
            }
            let model = MarkdownProjectionModel.build(tree: tree, index: index, intent: intent)
            return PresentationSnapshot.from(
                model: model,
                id: snapshotID,
                locationGeneration: locationGeneration,
                sourceText: source
            )
        }
        performedBuilds.withLock { $0 += 1 }
        memo.withLock { $0 = (key: key, value: built) }
        return built
    }

    /// Releases the retained snapshot.
    ///
    /// // A one-entry memo still retains one whole source string and one whole snapshot after the
    /// // document that produced them has closed. That is not a correctness problem — a new key
    /// // supersedes it — but holding several megabytes for a document the user closed is exactly
    /// // the kind of quiet retention `Scripts/leak-smoke.sh` exists to catch. Called from
    /// // `MarkdownDocument.close()`.
    static func releaseMemo() {
        memo.withLock { $0 = nil }
    }

    /// Drops the memo and the build counter. Tests that assert on how much work a route performs
    /// need a cold start.
    static func resetMemoForTesting() {
        memo.withLock { $0 = nil }
        performedBuilds.withLock { $0 = 0 }
    }
}
