import Foundation

/// Samples main-actor responsiveness by timing a hop from a background timer.
///
/// // REQ-124.
@MainActor
final class MainActorResponsivenessProbe {
    private var timer: DispatchSourceTimer?
    private let sampler: PerformanceSampler

    init(sampler: PerformanceSampler) {
        self.sampler = sampler
    }

    func start() {
        guard timer == nil else { return }
        let t = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        t.schedule(deadline: .now() + .milliseconds(100), repeating: .milliseconds(100))
        t.setEventHandler { [weak self] in
            let t0 = DispatchTime.now().uptimeNanoseconds
            Task { @MainActor in
                let t1 = DispatchTime.now().uptimeNanoseconds
                let latency = t1 &- t0
                self?.sampler.record(.mainActorLatency, durationNanos: latency)
            }
        }
        t.resume()
        timer = t
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    deinit {
        timer?.cancel()
    }
}
