import Foundation
import Synchronization

/// Stable identity for one user-invoked operation and all of its downstream work.
///
/// The raw value is intentionally opaque and is only emitted as a numeric diagnostic field.
/// // REQ-123; ARC-026.
nonisolated struct IntentID: RawRepresentable, Hashable, Sendable, Equatable {
    let rawValue: UInt64
}

/// Counts of work performed per unit of user intent.
///
/// // REQ-123; ARC-026.
nonisolated struct WorkLedger: Sendable, Equatable {
    var documentParses = 0
    var projectionCompiles = 0
    var oracleValidations = 0
    var attributedBuilds = 0
    var attributedCharactersWritten = 0
    var storageFullReplacements = 0
    var imageDecodes = 0
    var fileBytesRead = 0
    var mainThreadBlockedNanos: UInt64 = 0

    static func +(lhs: WorkLedger, rhs: WorkLedger) -> WorkLedger {
        var result = lhs
        result.documentParses += rhs.documentParses
        result.projectionCompiles += rhs.projectionCompiles
        result.oracleValidations += rhs.oracleValidations
        result.attributedBuilds += rhs.attributedBuilds
        result.attributedCharactersWritten += rhs.attributedCharactersWritten
        result.storageFullReplacements += rhs.storageFullReplacements
        result.imageDecodes += rhs.imageDecodes
        result.fileBytesRead += rhs.fileBytesRead
        result.mainThreadBlockedNanos &+= rhs.mainThreadBlockedNanos
        return result
    }

    var max: WorkLedger {
        self
    }
}

nonisolated enum WorkScope: String, Sendable, CaseIterable {
    case acceptedEdit
    case reconciliation
    case documentOpen
    case modeTransition
    case semanticCommand
}

/// Explicit, sendable context retained by every downstream operation.
nonisolated struct IntentContext: Sendable, Equatable {
    let id: IntentID
    let scope: WorkScope
    let recorder: IntentRecorder

    static func == (lhs: IntentContext, rhs: IntentContext) -> Bool {
        lhs.id == rhs.id && lhs.scope == rhs.scope
    }
}

/// Lock-guarded, session-owned recorder. It has no task-local or process-global current owner:
/// callers must pass the context through every actor, task, and GCD boundary.
nonisolated final class IntentRecorder: @unchecked Sendable {
    typealias Reporter = @Sendable (IntentContext, WorkLedger, Bool, DiagnosticSymbol?) -> Void
    private struct State {
        var nextID: UInt64 = 0
        var ledgers: [IntentID: WorkLedger] = [:]
        var leases: [IntentID: Int] = [:]
        var orphaned: Set<IntentID> = []
        var superseded: Set<IntentID> = []
    }

    private let state = Mutex(State())
    private let durableWriter = Mutex<(writer: DiagnosticWriteCoordinator?, startUptimeNanos: UInt64)>((nil, 0))
    private let reporterState = Mutex<Reporter?>(nil)

    func setReporter(_ reporter: @escaping Reporter) {
        reporterState.withLock { $0 = reporter }
    }

    func setDurableWriter(_ writer: DiagnosticWriteCoordinator, startUptimeNanos: UInt64) {
        durableWriter.withLock { $0 = (writer, startUptimeNanos) }
    }

    func begin(_ scope: WorkScope) -> IntentContext {
        state.withLock { state in
            state.nextID &+= 1
            let id = IntentID(rawValue: state.nextID)
            state.ledgers[id] = WorkLedger()
            state.leases[id] = 1
            return IntentContext(id: id, scope: scope, recorder: self)
        }
    }

    /// Retains ownership for a downstream adapter that will finish work after the current
    /// actor/task boundary returns. The lease prevents a normal parse completion from closing an
    /// intent before its presentation host has recorded attributed work.
    @discardableResult
    func retain(_ context: IntentContext) -> Bool {
        state.withLock { state in
            guard state.ledgers[context.id] != nil else { return false }
            state.leases[context.id, default: 0] += 1
            return true
        }
    }

    func add(_ context: IntentContext, _ mutate: (inout WorkLedger) -> Void) {
        let accepted = state.withLock { state in
            guard state.ledgers[context.id] != nil else { return false }
            mutate(&state.ledgers[context.id]!)
            return true
        }
        guard !accepted else { return }
        report(context: context, ledger: WorkLedger(), orphaned: true, reason: .lateWork)
    }

    func snapshot(_ context: IntentContext) -> WorkLedger? {
        state.withLock { $0.ledgers[context.id] }
    }

    /// Completes an intent exactly once. An operation that ends without completing is terminally
    /// classified instead of silently losing the work it performed: `superseded` when newer
    /// demand replaced it or its owner went away, which latest-wins scheduling does by design and
    /// is recorded at debug level; an orphan, a fault, when it ended incomplete for any other
    /// reason. Until 2026-11-27 both were faults, so every document open and every burst of fast
    /// typing logged one, and the smoke verifier had to admit them wholesale
    /// (`--allow-orphaned-intents`), which hid a double parse on every open.
    @discardableResult
    func finish(_ context: IntentContext, orphaned: Bool = false, superseded: Bool = false) -> Bool {
        let result: (ledger: WorkLedger, orphaned: Bool, superseded: Bool)? = state.withLock { state in
            guard state.ledgers[context.id] != nil else { return nil }
            if superseded {
                state.superseded.insert(context.id)
            } else if orphaned {
                state.orphaned.insert(context.id)
            }
            let remaining = state.leases[context.id, default: 1] - 1
            if remaining > 0 {
                state.leases[context.id] = remaining
                return nil
            }
            let ledger = state.ledgers.removeValue(forKey: context.id)!
            state.leases.removeValue(forKey: context.id)
            let wasSuperseded = state.superseded.remove(context.id) != nil
            let wasOrphaned = state.orphaned.remove(context.id) != nil && !wasSuperseded
            return (ledger, wasOrphaned, wasSuperseded)
        }
        guard let result else {
            // A live downstream lease makes this a normal release rather than a terminal report.
            // A missing ledger is the only genuinely late completion and remains typed below.
            let stillLive = state.withLock { $0.ledgers[context.id] != nil }
            if stillLive { return true }
            return false
        }
        let reason: DiagnosticSymbol? = result.orphaned ? .cancelled : (result.superseded ? .superseded : nil)
        report(context: context, ledger: result.ledger, orphaned: result.orphaned, reason: reason)
        return true
    }

    private func report(context: IntentContext, ledger: WorkLedger, orphaned: Bool, reason: DiagnosticSymbol?) {
        // An installed reporter is an *observer*, not an alternative sink, so it is notified
        // whichever destination the record goes to.
        //
        // // Until COR-92 the durable writer returned early and a reporter installed by
        // // `setReporter` was silently never called. Installing an observer and having it never
        // // fire, with no error, is the shape of failure this repository exists to prevent: a
        // // test that measured work through it would pass while measuring nothing.
        if let reporter = reporterState.withLock({ $0 }) {
            reporter(context, ledger, orphaned, reason)
        }
        let destination = durableWriter.withLock { $0 }
        if let writer = destination.writer {
            let start = destination.startUptimeNanos
            let timestamp = Date()
            _ = writer.appendRecord { sequence in
                DiagnosticRecord(
                    wallClock: timestamp,
                    uptimeSeconds: Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000_000,
                    sequence: sequence,
                    level: orphaned ? .fault : .debug,
                    category: .diagnostics,
                    event: .workLedger,
                    origin: .productionRoute,
                    productionRoute: .workLedger,
                    data: Self.data(context: context, ledger: ledger, orphaned: orphaned, reason: reason)
                ).jsonLine
            }
            return
        }
        if reporterState.withLock({ $0 }) != nil { return }
        Task { @MainActor in
            guard let log = DiagnosticLog.shared else { return }
            log.recordProduction(.workLedger, level: orphaned ? .fault : .debug, category: .diagnostics, route: .workLedger,
                data: Self.data(context: context, ledger: ledger, orphaned: orphaned, reason: reason))
        }
    }

    static func data(context: IntentContext, ledger: WorkLedger, orphaned: Bool, reason: DiagnosticSymbol?) -> [(key: DiagnosticField, value: DiagnosticValue)] {
        var data: [(key: DiagnosticField, value: DiagnosticValue)] = [
            (.scope, .symbol(context.scope.symbol)),
            (.intentID, .uint(context.id.rawValue)),
            (.orphaned, .bool(orphaned)),
            (.documentParses, .int(ledger.documentParses)),
            (.projectionCompiles, .int(ledger.projectionCompiles)),
            (.oracleValidations, .int(ledger.oracleValidations)),
            (.attributedBuilds, .int(ledger.attributedBuilds)),
            (.attributedCharactersWritten, .int(ledger.attributedCharactersWritten)),
            (.storageFullReplacements, .int(ledger.storageFullReplacements)),
            (.imageDecodes, .int(ledger.imageDecodes)),
            (.fileBytesRead, .int(ledger.fileBytesRead)),
            (.mainThreadBlockedNanos, .uint(ledger.mainThreadBlockedNanos)),
        ]
        if let reason {
            data.append((.orphanReason, .symbol(reason)))
            data.append((.lateWork, .bool(reason == .lateWork)))
        }
        return data
    }
}

extension WorkScope {
    var symbol: DiagnosticSymbol {
        switch self {
        case .acceptedEdit: return .acceptedEdit
        case .reconciliation: return .reconciliation
        case .documentOpen: return .documentOpen
        case .modeTransition: return .modeTransition
        case .semanticCommand: return .semanticCommand
        }
    }
}
