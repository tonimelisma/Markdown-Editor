import Foundation

/// Samples main-actor responsiveness by timing a hop from a background timer.
///
/// // REQ-124.
@MainActor
final class MainActorResponsivenessProbe {
    private var timer: DispatchSourceTimer?
    private let sampler: PerformanceSampler
    private var pendingStart: UInt64?

    init(sampler: PerformanceSampler) {
        self.sampler = sampler
    }

    func start() {
        guard timer == nil else { return }
        let t = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        t.schedule(deadline: .now() + .milliseconds(100), repeating: .milliseconds(100))
        t.setEventHandler { [weak self] in
            self?.captureSampleNow()
        }
        t.resume()
        timer = t
    }

    /// Captures a hop boundary immediately. The timer uses this same route; keeping the
    /// scheduling boundary in one method also lets component tests place a known main-actor
    /// stall after t0 without fabricating sampler input.
    func captureSampleNow() {
        let t0 = DispatchTime.now().uptimeNanoseconds
        pendingStart = t0
        DispatchQueue.main.async { [weak self] in
            self?.completePendingSample()
        }
    }

    private func completePendingSample() {
        guard let start = pendingStart else { return }
        pendingStart = nil
        sampler.record(.mainActorLatency, durationNanos: DispatchTime.now().uptimeNanoseconds &- start)
    }

    func stop() {
        timer?.cancel()
        timer = nil
        completePendingSample()
    }

    deinit {
        timer?.cancel()
    }
}
