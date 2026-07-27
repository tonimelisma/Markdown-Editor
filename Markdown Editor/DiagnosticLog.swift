//
//  DiagnosticLog.swift
//  Markdown Editor
//

import Foundation

/// Whether a run is ordinary application use or a hosted test run.
///
/// // REQ-095: a reader must never mistake test traffic for production usage.
nonisolated enum DiagnosticHostKind: String, Sendable, Equatable {
    case production
    case unitTest
}

/// Fixed-schema identification of one application run.
///
/// Distinct from `DiagnosticRecord`: these fields are process facts, none derived from a
/// document, so the closed payload value type (ARC-016) does not apply to them.
nonisolated struct DiagnosticRunHeader: Sendable, Equatable {
    static let schemaVersion = 1

    let runID: String
    let startedAt: Date
    let hostKind: DiagnosticHostKind
    let shortVersion: String
    let buildVersion: String
    let osVersion: String
    let processID: Int32

    var jsonLine: String {
        let run = [
            "\"id\":\"\(runID)\"",
            "\"host\":\"\(hostKind.rawValue)\"",
            "\"version\":\"\(shortVersion)\"",
            "\"build\":\"\(buildVersion)\"",
            "\"os\":\"\(osVersion)\"",
            "\"pid\":\(processID)"
        ].joined(separator: ",")
        return "{\"v\":\(Self.schemaVersion)"
            + ",\"ev\":\"\(DiagnosticEventName.runStart.rawValue)\""
            + ",\"t\":\"\(DiagnosticTimestamp.iso8601Milliseconds(startedAt))\""
            + ",\"seq\":0"
            + ",\"run\":{\(run)}}"
    }
}

/// Serialized appender. Actor isolation keeps the file handle off the main actor without an
/// unchecked-Sendable opt-out.
///
/// // REQ-088: Swift 6 complete concurrency; no mutable state escapes.
actor DiagnosticFileSink {
    private let url: URL
    private let byteLimit: Int
    private var handle: FileHandle?
    private var bytesWritten = 0
    private var truncated = false

    init(url: URL, byteLimit: Int) {
        self.url = url
        self.byteLimit = byteLimit
    }

    func append(_ lines: [String]) {
        guard !truncated, !lines.isEmpty else { return }
        if handle == nil {
            FileManager.default.createFile(atPath: url.path, contents: nil)
            handle = try? FileHandle(forWritingTo: url)
        }
        guard let handle else { return }
        var payload = Data()
        for line in lines {
            guard let encoded = (line + "\n").data(using: .utf8) else { continue }
            if bytesWritten + payload.count + encoded.count > byteLimit {
                truncated = true
                let notice = "{\"ev\":\"\(DiagnosticEventName.retentionPruned.rawValue)\""
                    + ",\"data\":{\"\(DiagnosticField.reason.rawValue)\":\"sizeLimit\"}}\n"
                if let noticeData = notice.data(using: .utf8) {
                    payload.append(noticeData)
                }
                break
            }
            payload.append(encoded)
        }
        guard !payload.isEmpty else { return }
        try? handle.write(contentsOf: payload)
        bytesWritten += payload.count
    }

    func close() {
        try? handle?.close()
        handle = nil
    }
}

/// One JSON Lines diagnostic file per application run.
///
/// // REQ-095/096: run-scoped local evidence. Nothing is transmitted; the file is an ordinary
/// // user-owned file under `~/Library/Logs/Markdown Editor/`.
@MainActor
final class DiagnosticLog {
    /// Shared production log. Absent until `startShared` runs, so tests stay isolated.
    private(set) static var shared: DiagnosticLog?

    static let directoryName = "Markdown Editor"
    static let maximumRetainedRuns = 20
    static let maximumFileBytes = 8 * 1024 * 1024
    static let flushRecordThreshold = 64
    static let flushInterval: Duration = .milliseconds(250)
    /// Above this count within one second, an identical event collapses into a summary.
    static let repeatCollapseThreshold = 20

    let header: DiagnosticRunHeader
    let fileURL: URL

    private let sink: DiagnosticFileSink
    private let startUptimeNanos: UInt64
    private var sequence: UInt64 = 0
    private var buffer: [String] = []
    private var flushTask: Task<Void, Never>?
    private var timerTask: Task<Void, Never>?
    private var closed = false

    /// Rate-collapse bookkeeping keyed by event name.
    private struct RepeatWindow {
        var windowStart: Double
        var count: Int
        var suppressed: Int
    }
    private var repeatWindows: [DiagnosticEventName: RepeatWindow] = [:]

    private var nextDocumentHandle: UInt64 = 0

    init(directory: URL, hostKind: DiagnosticHostKind, startedAt: Date = Date()) {
        let runID = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12)
        let bundle = Bundle.main.infoDictionary
        header = DiagnosticRunHeader(
            runID: String(runID),
            startedAt: startedAt,
            hostKind: hostKind,
            shortVersion: (bundle?["CFBundleShortVersionString"] as? String) ?? "0",
            buildVersion: (bundle?["CFBundleVersion"] as? String) ?? "0",
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            processID: ProcessInfo.processInfo.processIdentifier
        )
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        fileURL = directory.appendingPathComponent(
            "run-\(DiagnosticTimestamp.compactUTC(startedAt))-\(runID).jsonl"
        )
        sink = DiagnosticFileSink(url: fileURL, byteLimit: Self.maximumFileBytes)
        startUptimeNanos = DispatchTime.now().uptimeNanoseconds
        // A document app with no dirty documents is eligible for sudden termination: the process
        // is killed without `applicationWillTerminate`, so the terminating record never lands and
        // every clean exit is indistinguishable from a crash. Hold it off until the log closes.
        ProcessInfo.processInfo.disableSuddenTermination()
        buffer.append(header.jsonLine)
        Self.pruneRuns(in: directory, keeping: Self.maximumRetainedRuns)
        startFlushTimer()
    }

    /// Default production location: `~/Library/Logs/Markdown Editor/`.
    static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library")
        return base.appendingPathComponent("Logs").appendingPathComponent(directoryName)
    }

    @discardableResult
    static func startShared(hostKind: DiagnosticHostKind) -> DiagnosticLog {
        if let shared { return shared }
        let log = DiagnosticLog(directory: defaultDirectory(), hostKind: hostKind)
        shared = log
        return log
    }

    /// Allocates an opaque per-run document handle. Never derived from a name, path, or URL.
    func makeDocumentHandle() -> UInt64 {
        nextDocumentHandle &+= 1
        return nextDocumentHandle
    }

    func record(
        _ event: DiagnosticEventName,
        level: DiagnosticLevel = .debug,
        category: DiagnosticCategory,
        document: UInt64? = nil,
        data: [(key: DiagnosticField, value: DiagnosticValue)] = []
    ) {
        guard !closed else { return }
        let uptime = Double(DispatchTime.now().uptimeNanoseconds - startUptimeNanos) / 1_000_000_000

        // REQ-096: a defect firing every run-loop pass must produce bounded evidence.
        if let collapsed = collapse(event, at: uptime) {
            switch collapsed {
            case .suppress:
                return
            case .summarize(let count):
                appendLine(makeCollapseSummary(of: event, count: count, uptime: uptime).jsonLine)
            }
        }

        let entry = makeRecord(
            event,
            level: level,
            category: category,
            document: document,
            data: data,
            uptime: uptime
        )
        appendLine(entry.jsonLine)
        if level >= .error {
            flush()
        } else if buffer.count >= Self.flushRecordThreshold {
            flush()
        }
    }

    private func makeRecord(
        _ event: DiagnosticEventName,
        level: DiagnosticLevel,
        category: DiagnosticCategory,
        document: UInt64?,
        data: [(key: DiagnosticField, value: DiagnosticValue)],
        uptime: Double
    ) -> DiagnosticRecord {
        sequence &+= 1
        return DiagnosticRecord(
            wallClock: Date(),
            uptimeSeconds: uptime,
            sequence: sequence,
            level: level,
            category: category,
            event: event,
            document: document,
            data: data
        )
    }

    private func makeCollapseSummary(
        of event: DiagnosticEventName,
        count: Int,
        uptime: Double
    ) -> DiagnosticRecord {
        sequence &+= 1
        return DiagnosticRecord(
            wallClock: Date(),
            uptimeSeconds: uptime,
            sequence: sequence,
            level: .warn,
            category: .diagnostics,
            event: .repeated,
            collapsedEvent: event,
            data: [(.count, .int(count)), (.windowMillis, .int(1000))]
        )
    }

    private enum CollapseOutcome {
        case suppress
        case summarize(Int)
    }

    private func collapse(_ event: DiagnosticEventName, at uptime: Double) -> CollapseOutcome? {
        var window = repeatWindows[event] ?? RepeatWindow(windowStart: uptime, count: 0, suppressed: 0)
        if uptime - window.windowStart >= 1.0 {
            let suppressed = window.suppressed
            repeatWindows[event] = RepeatWindow(windowStart: uptime, count: 1, suppressed: 0)
            return suppressed > 0 ? .summarize(suppressed) : nil
        }
        window.count += 1
        if window.count > Self.repeatCollapseThreshold {
            window.suppressed += 1
            repeatWindows[event] = window
            return .suppress
        }
        repeatWindows[event] = window
        return nil
    }

    private func appendLine(_ line: String) {
        buffer.append(line)
    }

    func flush() {
        guard !buffer.isEmpty else { return }
        let batch = buffer
        buffer.removeAll(keepingCapacity: true)
        let sink = self.sink
        // Chain onto the previous flush so records reach the file in sequence order.
        // `Task.detached`, not `Task`: an inherited main-actor task cannot run while
        // `finishSynchronously` is blocking the main thread, and the terminal flush would
        // deadlock against its own appender.
        let previous = flushTask
        flushTask = Task.detached {
            await previous?.value
            await sink.append(batch)
        }
    }

    /// Writes the terminating record so a reader can distinguish a clean exit from a crash.
    func finish() {
        guard !closed else { return }
        // Emit any repeats still suppressed so the file never understates what happened.
        let uptime = Double(DispatchTime.now().uptimeNanoseconds - startUptimeNanos) / 1_000_000_000
        for (event, window) in repeatWindows.sorted(by: { $0.key.rawValue < $1.key.rawValue })
        where window.suppressed > 0 {
            appendLine(makeCollapseSummary(of: event, count: window.suppressed, uptime: uptime).jsonLine)
        }
        repeatWindows.removeAll()
        record(
            .runEnd,
            level: .info,
            category: .lifecycle,
            data: [(.count, .uint(sequence))]
        )
        closed = true
        timerTask?.cancel()
        timerTask = nil
        flush()
        ProcessInfo.processInfo.enableSuddenTermination()
        let sink = self.sink
        let previous = flushTask
        flushTask = Task.detached {
            await previous?.value
            await sink.close()
        }
    }

    /// Blocks the caller until every queued record has reached the file. Test support only.
    func drain() async {
        flush()
        await flushTask?.value
    }

    /// Terminal flush for `applicationWillTerminate`.
    ///
    /// // REQ-095: the terminating record must reach disk before the process exits, so an
    /// // agent can tell a clean exit from a crash. The buffered writer is asynchronous, and
    /// // an exiting process does not run its pending tasks; this bounds the wait instead.
    /// // The appender runs on the cooperative pool, so blocking the main thread cannot
    /// // deadlock it.
    func finishSynchronously(timeoutSeconds: Double = 2) {
        finish()
        let pending = flushTask
        guard let pending else { return }
        let gate = DispatchSemaphore(value: 0)
        Task.detached {
            await pending.value
            gate.signal()
        }
        _ = gate.wait(timeout: .now() + timeoutSeconds)
    }

    private func startFlushTimer() {
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.flushInterval)
                guard let self, !Task.isCancelled else { return }
                self.flush()
            }
        }
    }

    /// Keeps the newest `keeping` run files; removes the rest oldest-first.
    nonisolated static func pruneRuns(in directory: URL, keeping: Int) {
        let manager = FileManager.default
        guard let entries = try? manager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        let runs = entries
            .filter { $0.pathExtension == "jsonl" && $0.lastPathComponent.hasPrefix("run-") }
            .sorted { left, right in
                let leftDate = (try? left.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                let rightDate = (try? right.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                if leftDate == rightDate {
                    return left.lastPathComponent > right.lastPathComponent
                }
                return leftDate > rightDate
            }
        guard runs.count > keeping else { return }
        for stale in runs.dropFirst(keeping) {
            try? manager.removeItem(at: stale)
        }
    }
}
