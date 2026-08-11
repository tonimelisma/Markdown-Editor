import Foundation
import AppKit

/// Observes display-link intervals and derives hitch statistics.
///
/// // REQ-125.
@MainActor
final class FrameObserver {
    private var timer: Timer?
    private var lastTimestamp: CFTimeInterval = 0
    private var hitchMillisPerSecond: Double = 0
    private var longestFrameNanos: UInt64 = 0
    private var framesObserved: Int = 0
    private let trace: (any EditorTraceSink)?
    private var displayBudget: Double = 1.0 / 60.0

    init(sampler: PerformanceSampler, trace: (any EditorTraceSink)? = nil) {
        _ = sampler
        self.trace = trace
    }

    func start() {
        guard ProcessInfo.processInfo.environment["MARKDOWN_EDITOR_FRAME_OBSERVER"] == "1" else { return }
        guard timer == nil else { return }
        // Use display link's real cadence via NSScreen maximumFramesPerSecond, never hardcoded 16.67.
        if let screen = NSScreen.main {
            let fps = Double(screen.maximumFramesPerSecond)
            if fps > 0 { displayBudget = 1.0 / fps }
        }
        timer = Timer.scheduledTimer(withTimeInterval: displayBudget, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        guard framesObserved > 0 else { return }
        trace?.record(.frameStatistics(
            hitchMillisPerSecond: hitchMillisPerSecond,
            longestFrameNanos: longestFrameNanos,
            framesObserved: framesObserved
        ))
    }

    private func tick() {
        let ts = CACurrentMediaTime()
        if lastTimestamp != 0 {
            let delta = ts - lastTimestamp
            let budget = displayBudget
            let frameNanos = UInt64(delta * 1_000_000_000)
            framesObserved += 1
            longestFrameNanos = max(longestFrameNanos, frameNanos)
            if delta > budget {
                hitchMillisPerSecond += (delta - budget) * 1000
            }
        }
        lastTimestamp = ts
    }

    nonisolated static func hitchMillisPerSecond(
        frameIntervalsNanos: [UInt64],
        cadenceNanos: UInt64
    ) -> Double {
        guard cadenceNanos > 0 else { return 0 }
        return frameIntervalsNanos.reduce(0) { total, interval in
            total + Double(interval > cadenceNanos ? interval - cadenceNanos : 0) / 1_000_000
        }
    }
}
