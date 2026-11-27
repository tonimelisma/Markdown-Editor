//
//  MainActorWatchdog.swift
//  Markdown Editor
//

import Foundation
import Synchronization

/// Whether AppKit is running an app-modal session on the main thread: an alert waiting for the
/// person, such as "could not be opened". The main thread is responsive, but the main actor's
/// queued jobs wait until the session ends, so a watchdog probe cannot land. The bad-file alert in
/// tour 45974231615 was recorded as two main-actor stalls, while the app was only asking.
///
/// One instance, `shared`, is the app's; a test makes its own, so a session it runs cannot reach
/// another test's probe.
nonisolated final class AppModalSession: Sendable {
    static let shared = AppModalSession()

    private struct State { var depth = 0; var epoch: UInt64 = 0 }
    private let state = Mutex(State())

    var isActive: Bool { state.withLock { $0.depth > 0 } }

    /// Advances as each session begins and ends: a measurement that starts at one epoch and ends
    /// at another overlapped a session, though none may be running at either end.
    var epoch: UInt64 { state.withLock { $0.epoch } }

    /// Runs `body`, an app-modal presentation that returns when the person dismisses it.
    func around<T>(_ body: () throws -> T) rethrows -> T {
        state.withLock { $0.depth += 1; $0.epoch &+= 1 }
        defer { state.withLock { $0.depth = max(0, $0.depth - 1); $0.epoch &+= 1 } }
        return try body()
    }
}

/// One-shot completion flag observable from another isolation domain.
///
/// // REQ-088: actor isolation rather than a lock plus an unchecked-Sendable opt-out.
actor WatchdogProbeFlag {
    private var completed = false

    func markCompleted() {
        completed = true
    }

    var isCompleted: Bool {
        completed
    }
}

/// Detects an unresponsive main actor from a background task.
///
/// // REQ-096: a hop onto the main actor is raced against the threshold. If the threshold
/// // elapses first the fault is recorded immediately, while the main actor is still stalled,
/// // so a stall that never recovers is still reported. A second record carries the measured
/// // duration once the hop finally lands.
/// //
/// // This watchdog catches a *blocked* main actor. A *busy* main actor — a render loop
/// // burning a core while still servicing hops — is caught by the host update meter instead.
@MainActor
final class MainActorWatchdog {
    static let defaultInterval: Duration = .seconds(1)
    static let defaultThresholdMillis: UInt64 = 1_000

    /// Report sink. Invoked from a background task, so it must be safe off the main actor.
    typealias Report = @Sendable (UInt64) -> Void

    private var task: Task<Void, Never>?
    private let interval: Duration
    private let thresholdMillis: UInt64
    private let report: Report

    init(
        interval: Duration = MainActorWatchdog.defaultInterval,
        thresholdMillis: UInt64 = MainActorWatchdog.defaultThresholdMillis,
        report: @escaping Report
    ) {
        self.interval = interval
        self.thresholdMillis = thresholdMillis
        self.report = report
    }

    func start() {
        guard task == nil else { return }
        let interval = self.interval
        let thresholdMillis = self.thresholdMillis
        let report = self.report
        task = Task.detached(priority: .utility) {
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                if Task.isCancelled { return }
                await Self.probeOnce(thresholdMillis: thresholdMillis, report: report)
            }
        }
    }

    /// Times one hop onto the main actor. Exposed so tests can drive a single probe.
    ///
    /// // REQ-096; ARC-021: deliberately `nonisolated`. If this were main-actor isolated, the
    /// // detached probe task would have to acquire the main actor before it could start timing —
    /// // so it would queue behind the very stall it exists to report, and could only ever
    /// // describe a stall that had already ended.
    ///
    /// No stall is reported while an app-modal session is waiting for the person
    /// (`AppModalSession`): the main thread is serving the alert, not blocked.
    nonisolated static func probeOnce(
        thresholdMillis: UInt64,
        isModalSessionActive: @Sendable () -> Bool = { AppModalSession.shared.isActive },
        report: Report
    ) async {
        let started = DispatchTime.now().uptimeNanoseconds
        let flag = WatchdogProbeFlag()
        let probe = Task<Void, Never> { @MainActor in
            await flag.markCompleted()
        }
        try? await Task.sleep(for: .milliseconds(Int(thresholdMillis)))
        guard await flag.isCompleted == false else { return }
        guard !isModalSessionActive() else {
            await probe.value
            return
        }
        // Still stalled: report now rather than only on recovery.
        report(thresholdMillis)
        await probe.value
        report((DispatchTime.now().uptimeNanoseconds &- started) / 1_000_000)
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    deinit {
        task?.cancel()
    }
}
