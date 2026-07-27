//
//  MainActorWatchdog.swift
//  Markdown Editor
//

import Foundation

/// Detects an unresponsive main actor from a background task.
///
/// // REQ-096: a stall is measured by timing a hop onto the main actor. The record is written
/// // when the hop completes, so the duration of a recovered stall is exact. A main actor that
/// // never recovers produces no record — that case is a crash-report concern, not a log concern.
/// // The editor-host update meter, not this watchdog, is what catches a busy main actor.
@MainActor
final class MainActorWatchdog {
    static let defaultInterval: Duration = .seconds(1)
    static let defaultThresholdMillis: UInt64 = 1_000

    private var task: Task<Void, Never>?
    private let interval: Duration
    private let thresholdMillis: UInt64
    private let report: @MainActor (UInt64) -> Void

    init(
        interval: Duration = MainActorWatchdog.defaultInterval,
        thresholdMillis: UInt64 = MainActorWatchdog.defaultThresholdMillis,
        report: @escaping @MainActor (UInt64) -> Void
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
                let start = DispatchTime.now().uptimeNanoseconds
                let elapsedMillis = await MainActor.run {
                    (DispatchTime.now().uptimeNanoseconds &- start) / 1_000_000
                }
                if elapsedMillis >= thresholdMillis {
                    await MainActor.run { report(elapsedMillis) }
                }
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    deinit {
        task?.cancel()
    }
}
