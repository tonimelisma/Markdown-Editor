import Foundation
import Synchronization

private nonisolated enum MainActorProbeRelay {
    private static let callbacks = Mutex<[UUID: @MainActor @Sendable (UInt64, UInt64) -> Void]>([:])

    static func install(_ callback: @escaping @MainActor @Sendable (UInt64, UInt64) -> Void) -> UUID {
        let token = UUID()
        callbacks.withLock { $0[token] = callback }
        return token
    }

    static func fire(_ token: UUID) {
        let callback = callbacks.withLock { $0[token] }
        guard let callback else { return }
        let epoch = AppModalSession.epoch
        let start = DispatchTime.now().uptimeNanoseconds
        Task { @MainActor in callback(start, epoch) }
    }

    static func handler(for token: UUID) -> @Sendable () -> Void {
        { MainActorProbeRelay.fire(token) }
    }

    static func remove(_ token: UUID) {
        _ = callbacks.withLock { $0.removeValue(forKey: token) }
    }
}

/// Samples main-actor responsiveness by timing a hop from a background timer.
///
/// A hop that waited out an app-modal alert is not counted, as the watchdog does not report one:
/// the main thread was running the alert, and the hop measured how long the person took to read
/// it. Tour 45974231615's bad-file alert alone put this metric's p95 at 896 ms.
///
/// // REQ-124.
@MainActor
final class MainActorResponsivenessProbe {
    private var timer: DispatchSourceTimer?
    private let sampler: PerformanceSampler
    private var relayToken: UUID?
    private var pendingSamples: [(start: UInt64, epoch: UInt64)] = []

    init(sampler: PerformanceSampler) {
        self.sampler = sampler
    }

    func start() {
        guard timer == nil else { return }
        let token = MainActorProbeRelay.install { [weak self] start, epoch in
            self?.completeSample(start: start, epoch: epoch)
        }
        relayToken = token
        let t = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        t.schedule(deadline: .now() + .milliseconds(100), repeating: .milliseconds(100))
        // Construct the handler in the nonisolated relay so the utility queue never receives a
        // closure implicitly isolated to this main-actor object.
        t.setEventHandler(handler: MainActorProbeRelay.handler(for: token))
        t.resume()
        timer = t
    }

    /// Starts one real main-actor hop. The timer records its timestamp before enqueuing the hop;
    /// a delayed callback therefore measures time spent waiting for the actor, not only time
    /// after the callback has already arrived.
    func captureSampleNow() {
        let epoch = AppModalSession.epoch
        let start = DispatchTime.now().uptimeNanoseconds
        pendingSamples.append((start, epoch))
        DispatchQueue.main.async { [weak self] in
            self?.completeQueuedSample(start: start, epoch: epoch)
        }
    }

    private func completeQueuedSample(start: UInt64, epoch: UInt64) {
        if let index = pendingSamples.firstIndex(where: { $0.start == start && $0.epoch == epoch }) {
            pendingSamples.remove(at: index)
        }
        completeSample(start: start, epoch: epoch)
    }

    private func completeSample(start: UInt64, epoch: UInt64) {
        let end = DispatchTime.now().uptimeNanoseconds
        guard !AppModalSession.isActive, AppModalSession.epoch == epoch else { return }
        sampler.record(.mainActorLatency, durationNanos: end &- start)
    }

    func stop() {
        timer?.cancel()
        timer = nil
        if let relayToken {
            MainActorProbeRelay.remove(relayToken)
            self.relayToken = nil
        }
        let pending = pendingSamples
        pendingSamples.removeAll()
        for sample in pending { completeSample(start: sample.start, epoch: sample.epoch) }
    }

    deinit {
        timer?.cancel()
        if let relayToken { MainActorProbeRelay.remove(relayToken) }
    }
}
