//
//  MainActorWatchdog.swift
//  Markdown Editor
//

import Foundation

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
    nonisolated static func probeOnce(thresholdMillis: UInt64, report: Report) async {
        let started = DispatchTime.now().uptimeNanoseconds
        let flag = WatchdogProbeFlag()
        let probe = Task<Void, Never> { @MainActor in
            await flag.markCompleted()
        }
        try? await Task.sleep(for: .milliseconds(Int(thresholdMillis)))
        guard await flag.isCompleted == false else { return }
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
