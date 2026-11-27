import Foundation
import Synchronization

private nonisolated enum MainActorProbeRelay {
    private typealias Entry = (
        callback: @MainActor @Sendable (UInt64, UInt64) -> Void,
        sessions: AppModalSession,
        mainRunLoopMode: @Sendable () -> String?
    )
    private static let callbacks = Mutex<[UUID: Entry]>([:])

    static func install(
        _ callback: @escaping @MainActor @Sendable (UInt64, UInt64) -> Void,
        sessions: AppModalSession,
        mainRunLoopMode: @escaping @Sendable () -> String?
    ) -> UUID {
        let token = UUID()
        callbacks.withLock { $0[token] = (callback, sessions, mainRunLoopMode) }
        return token
    }

    static func fire(_ token: UUID) {
        let entry = callbacks.withLock { $0[token] }
        guard let entry else { return }
        let callback = entry.callback
        // Seen every 100 ms, so a wait in AppKit's own loop that lasts longer is seen, and every
        // sample pending across it is dropped.
        if MainRunLoop.isAppKitWait(entry.mainRunLoopMode()) { entry.sessions.noteAppKitWait() }
        let epoch = entry.sessions.epoch
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
/// it. Tour 45974231615's bad-file alert alone put this metric's p95 at 896 ms. Nor is a hop that
/// waited while the main thread ran one of AppKit's own loops (`MainRunLoop`), as it does for the
/// title-bar rename after Duplicate.
///
/// // REQ-124.
@MainActor
final class MainActorResponsivenessProbe {
    private var timer: DispatchSourceTimer?
    private let sampler: PerformanceSampler
    private var relayToken: UUID?
    private var pendingSamples: [(start: UInt64, epoch: UInt64)] = []
    private let modalSessions: AppModalSession
    private let mainRunLoopMode: @Sendable () -> String?

    init(
        sampler: PerformanceSampler,
        modalSessions: AppModalSession = .shared,
        mainRunLoopMode: @escaping @Sendable () -> String? = { MainRunLoop.currentMode() }
    ) {
        self.sampler = sampler
        self.modalSessions = modalSessions
        self.mainRunLoopMode = mainRunLoopMode
    }

    func start() {
        guard timer == nil else { return }
        let token = MainActorProbeRelay.install({ [weak self] start, epoch in
            self?.completeSample(start: start, epoch: epoch)
        }, sessions: modalSessions, mainRunLoopMode: mainRunLoopMode)
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
        let epoch = modalSessions.epoch
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
        guard !modalSessions.isActive, modalSessions.epoch == epoch else { return }
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
