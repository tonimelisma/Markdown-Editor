import Foundation
import Synchronization

private nonisolated enum MainActorProbeRelay {
    private static let callbacks = Mutex<[UUID: @MainActor @Sendable () -> Void]>([:])

    static func install(_ callback: @escaping @MainActor @Sendable () -> Void) -> UUID {
        let token = UUID()
        callbacks.withLock { $0[token] = callback }
        return token
    }

    static func fire(_ token: UUID) {
        let callback = callbacks.withLock { $0[token] }
        guard let callback else { return }
        Task { @MainActor in callback() }
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
    private var pendingStart: UInt64?
    private var relayToken: UUID?

    init(sampler: PerformanceSampler) {
        self.sampler = sampler
    }

    func start() {
        guard timer == nil else { return }
        let token = MainActorProbeRelay.install { [weak self] in
            self?.captureSampleNow()
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
        if let relayToken {
            MainActorProbeRelay.remove(relayToken)
            self.relayToken = nil
        }
        completePendingSample()
    }

    deinit {
        timer?.cancel()
        if let relayToken { MainActorProbeRelay.remove(relayToken) }
    }
}
