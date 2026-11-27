//
//  MainActorWatchdog.swift
//  Markdown Editor
//

import AppKit
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

    /// Opens a session that something other than a call's extent ends, such as the Versions
    /// browser, which opens and closes in separate events. Each `begin` is matched by one `end`.
    func begin() {
        state.withLock { $0.depth += 1; $0.epoch &+= 1 }
    }

    func end() {
        state.withLock { $0.depth = max(0, $0.depth - 1); $0.epoch &+= 1 }
    }

    /// Notes that the main thread was seen waiting in one of AppKit's own loops
    /// (`MainRunLoop.isAppKitWait`): a measurement spanning it did not measure the app.
    func noteAppKitWait() {
        state.withLock { $0.epoch &+= 1 }
    }

    /// Runs `body`, an app-modal presentation that returns when the person dismisses it.
    func around<T>(_ body: () throws -> T) rethrows -> T {
        state.withLock { $0.depth += 1; $0.epoch &+= 1 }
        defer { state.withLock { $0.depth = max(0, $0.depth - 1); $0.epoch &+= 1 } }
        return try body()
    }
}

/// The main run loop's mode, read from another thread, and what it says about a main actor
/// whose queued jobs are not running.
///
/// The main dispatch queue, and so the main actor, is served in the common modes: default, event
/// tracking and modal panel. A main actor that does not run while the loop is in one of them is
/// held by a callout: work, the app's or AppKit's. In any other mode the main thread is inside
/// one of AppKit's own loops that serves no queue: waiting on a remote view service, as the title
/// bar's rename after Duplicate does (probe 45982413288's sample), or running a blocking
/// animation. That is AppKit waiting, not the app stalled; a deadlock in such a loop, as the close
/// hang was, never ends, and the watchdog reports it once it outlasts
/// `MainActorWatchdog.appKitWaitBoundMillis`.
nonisolated enum MainRunLoop {
    static let modesServingTheMainQueue: Set<String> = [
        CFRunLoopMode.defaultMode.rawValue as String,
        "NSEventTrackingRunLoopMode",
        "NSModalPanelRunLoopMode",
    ]

    static func currentMode() -> String? {
        CFRunLoopCopyCurrentMode(CFRunLoopGetMain()).map { $0.rawValue as String }
    }

    /// Whether a main actor that is not running is waiting in AppKit's own loop.
    static func isAppKitWait(_ mode: String?) -> Bool {
        guard let mode else { return false }
        return !modesServingTheMainQueue.contains(mode)
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
    /// How long a wait in AppKit's own loop (`MainRunLoop`) may hold the main actor before it is
    /// reported: a deadlock there never ends.
    static let appKitWaitBoundMillis: UInt64 = 10_000

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
    /// (`AppModalSession`): the main thread is serving the alert, not blocked. A main thread
    /// waiting in AppKit's own loop (`MainRunLoop`) is reported only if the wait outlasts
    /// `appKitWaitBoundMillis`, or if the loop leaves for a mode where the actor should run.
    nonisolated static func probeOnce(
        thresholdMillis: UInt64,
        appKitWaitBoundMillis: UInt64 = MainActorWatchdog.appKitWaitBoundMillis,
        isModalSessionActive: @Sendable () -> Bool = { AppModalSession.shared.isActive },
        mainRunLoopMode: @Sendable () -> String? = { MainRunLoop.currentMode() },
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
        let bound = started &+ appKitWaitBoundMillis &* 1_000_000
        while MainRunLoop.isAppKitWait(mainRunLoopMode()), DispatchTime.now().uptimeNanoseconds < bound {
            try? await Task.sleep(for: .milliseconds(50))
            if await flag.isCompleted { return }
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

/// Holds an app-modal session for as long as a window shows the Versions browser.
///
/// AppKit runs a blocking animation as the browser opens and again as it closes, after Restore or
/// Done, and the document cannot be edited in between. Only the opening call was a session, so the
/// closing animation's wait counted as main-actor latency: a 361–391 ms p95 in every tour minute
/// that visited the browser (tours 45985053390, 45985821997), and under 0.5 ms in a probe of the
/// same steps without it (45985991466).
@MainActor
final class VersionBrowserSessions {
    private let sessions: AppModalSession
    private var browsing: Set<ObjectIdentifier> = []
    /// Kept for the observers' lifetime; the app's instance lives as long as the app.
    private var observers: [NSObjectProtocol] = []

    /// AppKit posts both notifications on the main thread, where the observers run (`queue: nil`).
    init(sessions: AppModalSession = .shared, center: NotificationCenter = .default) {
        self.sessions = sessions
        observers.append(center.addObserver(
            forName: NSWindow.willEnterVersionBrowserNotification, object: nil, queue: nil
        ) { [weak self] note in
            let window = (note.object as AnyObject?).map(ObjectIdentifier.init)
            MainActor.assumeIsolated { self?.entered(window) }
        })
        observers.append(center.addObserver(
            forName: NSWindow.didExitVersionBrowserNotification, object: nil, queue: nil
        ) { [weak self] note in
            let window = (note.object as AnyObject?).map(ObjectIdentifier.init)
            MainActor.assumeIsolated { self?.exited(window) }
        })
    }

    private func entered(_ window: ObjectIdentifier?) {
        guard let window, browsing.insert(window).inserted else { return }
        sessions.begin()
    }

    private func exited(_ window: ObjectIdentifier?) {
        guard let window, browsing.remove(window) != nil else { return }
        sessions.end()
    }
}
