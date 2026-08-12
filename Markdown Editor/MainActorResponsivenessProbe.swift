import Foundation
import Synchronization

private nonisolated enum MainActorProbeRelay {
    private static let callbacks = Mutex<[UUID: @MainActor @Sendable (UInt64) -> Void]>([:])

    static func install(_ callback: @escaping @MainActor @Sendable (UInt64) -> Void) -> UUID {
        let token = UUID()
        callbacks.withLock { $0[token] = callback }
        return token
    }

    static func fire(_ token: UUID) {
        let callback = callbacks.withLock { $0[token] }
        guard let callback else { return }
        let start = DispatchTime.now().uptimeNanoseconds
        Task { @MainActor in callback(start) }
    }

    static func handler(for token: UUID) -> @Sendable () -> Void {
        { MainActorProbeRelay.fire(token) }
    }

    static func remove(_ token: UUID) {
        callbacks.withLock { $0.removeValue(forKey: token) }
    }
}

/// Samples main-actor responsiveness by timing a hop from a background timer.
///
/// // REQ-124.
@MainActor
final class MainActorResponsivenessProbe {
    private var timer: DispatchSourceTimer?
    private let sampler: PerformanceSampler
    private var relayToken: UUID?
    private var pendingSamples: [UInt64] = []

    init(sampler: PerformanceSampler) {
        self.sampler = sampler
    }

    func start() {
        guard timer == nil else { return }
        let token = MainActorProbeRelay.install { [weak self] start in
            self?.completeSample(start: start)
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
        let start = DispatchTime.now().uptimeNanoseconds
        pendingSamples.append(start)
        DispatchQueue.main.async { [weak self] in
            self?.completeQueuedSample(start: start)
        }
    }

    private func completeQueuedSample(start: UInt64) {
        if let index = pendingSamples.firstIndex(of: start) {
            pendingSamples.remove(at: index)
        }
        completeSample(start: start)
    }

    private func completeSample(start: UInt64) {
        sampler.record(.mainActorLatency, durationNanos: DispatchTime.now().uptimeNanoseconds &- start)
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
        for start in pending { completeSample(start: start) }
    }

    deinit {
        timer?.cancel()
        if let relayToken { MainActorProbeRelay.remove(relayToken) }
    }
}
