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

/// Where a diagnostic event originated. This is schema metadata, not a payload value: encoding
/// probes and gate fixtures can therefore never satisfy production route coverage.
nonisolated enum DiagnosticEvidenceOrigin: String, Sendable, Equatable, CaseIterable {
    case productionRoute
    case encodingProbe
    case gateFixture
}

/// Fixed-schema identification of one application run.
///
/// Distinct from `DiagnosticRecord`: these fields are process facts, none derived from a
/// document, so the closed payload value type (ARC-016) does not apply to them.
nonisolated struct DiagnosticRunHeader: Sendable, Equatable {
    static let schemaVersion = 2

    let runID: String
    let startedAt: Date
    let hostKind: DiagnosticHostKind
    let shortVersion: String
    let buildVersion: String
    let osVersion: String
    let processID: Int32

    /// // REQ-095: encoded rather than interpolated. `osVersion` and the bundle versions are
    /// // runtime strings, so a quote or backslash in any of them would otherwise make the one
    /// // record that identifies the run unparseable.
    var jsonLine: String {
        struct Payload: Encodable {
            struct Run: Encodable {
                let id: String
                let host: String
                let version: String
                let build: String
                let os: String
                let pid: Int32
            }
            let v: Int
            let ev: String
            let t: String
            let seq: Int
            let run: Run
        }
        let payload = Payload(
            v: Self.schemaVersion,
            ev: DiagnosticEventName.runStart.rawValue,
            t: DiagnosticTimestamp.iso8601Milliseconds(startedAt),
            seq: 0,
            run: Payload.Run(
                id: runID,
                host: hostKind.rawValue,
                version: shortVersion,
                build: buildVersion,
                os: osVersion,
                pid: processID
            )
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        guard let data = try? encoder.encode(payload),
              let line = String(data: data, encoding: .utf8) else {
            return "{\"v\":\(Self.schemaVersion),\"ev\":\"\(DiagnosticEventName.runStart.rawValue)\",\"seq\":0}"
        }
        return line
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

    /// Appends lines and reports whether the size cap was reached during this batch.
    @discardableResult
    func append(_ lines: [String]) -> Bool {
        guard !truncated, !lines.isEmpty else { return false }
        if handle == nil {
            FileManager.default.createFile(atPath: url.path, contents: nil)
            handle = try? FileHandle(forWritingTo: url)
        }
        guard let handle else { return false }
        var payload = Data()
        for line in lines {
            guard let encoded = (line + "\n").data(using: .utf8) else { continue }
            if bytesWritten + payload.count + encoded.count > byteLimit {
                truncated = true
                break
            }
            payload.append(encoded)
        }
        if !payload.isEmpty {
            try? handle.write(contentsOf: payload)
            bytesWritten += payload.count
        }
        return truncated
    }

    var isTruncated: Bool {
        truncated
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

    private let startUptimeNanos: UInt64
    private let writeCoordinator: DiagnosticWriteCoordinator
    /// Work-ledger records are emitted directly by the recorder rather than through an editor
    /// trace sink. Keep that production owner observable by the same synchronous coverage stream.
    private let coverageRecorder: JSONLinesEditorTrace.ProductionRouteCoverageRecorder?
    private var durabilityTask: Task<Void, Never>?
    private var closed = false
    private var sizeLimitRecorded = false
    private var suddenTerminationDisabled = false

    /// Rate-collapse bookkeeping keyed by event name.
    private struct RepeatWindow {
        var windowStart: Double
        var count: Int
        var suppressed: Int
        var sums: [DiagnosticField: UInt64] = [:]
        var maxima: [DiagnosticField: UInt64] = [:]
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
        // ARC-Q06: enumerating and deleting old runs is file I/O and does not belong on the
        // main actor. Only the directory creation above stays, because `fileURL` depends on it.
        let pruneDirectory = directory
        let keep = Self.maximumRetainedRuns
        Task.detached(priority: .utility) {
            Self.pruneRuns(in: pruneDirectory, keeping: keep)
        }
        let sink = DiagnosticFileSink(url: fileURL, byteLimit: Self.maximumFileBytes)
        writeCoordinator = DiagnosticWriteCoordinator(sink: sink)
        coverageRecorder = hostKind == .unitTest
            ? JSONLinesEditorTrace.ProductionRouteCoverageRecorder(
                directory: JSONLinesEditorTrace.hostedCoverageDirectory()
            )
            : nil
        startUptimeNanos = DispatchTime.now().uptimeNanoseconds
        // A document app with no dirty documents is eligible for sudden termination: the process
        // is killed without `applicationWillTerminate`, so the terminating record never lands and
        // every clean exit is indistinguishable from a crash. Hold it off until the log closes.
        ProcessInfo.processInfo.disableSuddenTermination()
        suddenTerminationDisabled = true
        appendLine(header.jsonLine)
    }

    /// Production location: `~/Library/Logs/Markdown Editor/`. Test runs get their own
    /// subdirectory so a `xcodebuild test` cannot prune a user's production evidence.
    ///
    /// // REQ-097: an explicit `MARKDOWN_EDITOR_DIAGNOSTICS_DIR` override takes priority over
    /// // both branches below, so process-level smoke verification gets a hermetic directory
    /// // that cannot read, prune, or pollute the user's own diagnostics.
    static func defaultDirectory(
        hostKind: DiagnosticHostKind = .production,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        if let override = environment["MARKDOWN_EDITOR_DIAGNOSTICS_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        let base = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library")
        let root = base.appendingPathComponent("Logs").appendingPathComponent(directoryName)
        switch hostKind {
        case .production: return root
        case .unitTest: return root.appendingPathComponent("UnitTests")
        }
    }

    @discardableResult
    static func startShared(hostKind: DiagnosticHostKind) -> DiagnosticLog {
        if let shared { return shared }
        let log = DiagnosticLog(directory: defaultDirectory(hostKind: hostKind), hostKind: hostKind)
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
        origin: DiagnosticEvidenceOrigin = .gateFixture,
        data: [(key: DiagnosticField, value: DiagnosticValue)] = []
    ) {
        guard !closed else { return }
        let uptime = Double(DispatchTime.now().uptimeNanoseconds - startUptimeNanos) / 1_000_000_000

        if event == .workLedger, origin == .productionRoute {
            coverageRecorder?.record(
                event: event,
                level: level,
                category: category,
                data: data
            )
        }

        // REQ-096: a defect firing every run-loop pass must produce bounded evidence — but a
        // fault is the evidence, so it is never collapsed away.
        if level < .error, let collapsed = collapse(event, data: data, at: uptime) {
            switch collapsed {
            case .suppress:
                return
            case .summarize(let count, let sums, let maxima):
                appendCollapseSummary(of: event, count: count, sums: sums, maxima: maxima, uptime: uptime)
            }
        }

        appendRecord(
            event,
            level: level,
            category: category,
            document: document,
            origin: origin,
            data: data,
            uptime: uptime
        )
    }

    private func appendRecord(
        _ event: DiagnosticEventName,
        level: DiagnosticLevel,
        category: DiagnosticCategory,
        document: UInt64?,
        origin: DiagnosticEvidenceOrigin,
        data: [(key: DiagnosticField, value: DiagnosticValue)],
        uptime: Double
    ) {
        let timestamp = Date()
        observeSizeLimit(writeCoordinator.appendRecord { sequence in
            DiagnosticRecord(
                wallClock: timestamp,
                uptimeSeconds: uptime,
                sequence: sequence,
                level: level,
                category: category,
                event: event,
                document: document,
                origin: origin,
                productionRoute: origin == .productionRoute ? event : nil,
                attestation: DiagnosticCoverageAttestation.token(event: event, origin: origin),
                data: data
            ).jsonLine
        })
    }

    private func appendCollapseSummary(
        of event: DiagnosticEventName,
        count: Int,
        sums: [DiagnosticField: UInt64] = [:],
        maxima: [DiagnosticField: UInt64] = [:],
        uptime: Double
    ) {
        var data: [(key: DiagnosticField, value: DiagnosticValue)] = [
            (.count, .int(count)), (.windowMillis, .int(1000))
        ]
        for field in WorkLedgerAggregateField.allCases {
            if let sum = sums[field.source] { data.append((field.sum, .uint(sum))) }
            if let maximum = maxima[field.source] { data.append((field.max, .uint(maximum))) }
        }
        let finalData = data
        let timestamp = Date()
        observeSizeLimit(writeCoordinator.appendRecord { sequence in
            DiagnosticRecord(
                wallClock: timestamp,
                uptimeSeconds: uptime,
                sequence: sequence,
                level: .warn,
                category: .diagnostics,
                event: .repeated,
                collapsedEvent: event,
                data: finalData
            ).jsonLine
        })
    }

    private enum CollapseOutcome {
        case suppress
        case summarize(Int, [DiagnosticField: UInt64], [DiagnosticField: UInt64])
    }

    private enum WorkLedgerAggregateField: CaseIterable {
        case documentParses, projectionCompiles, oracleValidations, attributedBuilds
        case attributedCharactersWritten, storageFullReplacements, imageDecodes, fileBytesRead
        case mainThreadBlockedNanos

        var source: DiagnosticField {
            switch self {
            case .documentParses: return .documentParses
            case .projectionCompiles: return .projectionCompiles
            case .oracleValidations: return .oracleValidations
            case .attributedBuilds: return .attributedBuilds
            case .attributedCharactersWritten: return .attributedCharactersWritten
            case .storageFullReplacements: return .storageFullReplacements
            case .imageDecodes: return .imageDecodes
            case .fileBytesRead: return .fileBytesRead
            case .mainThreadBlockedNanos: return .mainThreadBlockedNanos
            }
        }

        var sum: DiagnosticField {
            switch self {
            case .documentParses: return .sumDocumentParses
            case .projectionCompiles: return .sumProjectionCompiles
            case .oracleValidations: return .sumOracleValidations
            case .attributedBuilds: return .sumAttributedBuilds
            case .attributedCharactersWritten: return .sumAttributedCharactersWritten
            case .storageFullReplacements: return .sumStorageFullReplacements
            case .imageDecodes: return .sumImageDecodes
            case .fileBytesRead: return .sumFileBytesRead
            case .mainThreadBlockedNanos: return .sumMainThreadBlockedNanos
            }
        }

        var max: DiagnosticField {
            switch self {
            case .documentParses: return .maxDocumentParses
            case .projectionCompiles: return .maxProjectionCompiles
            case .oracleValidations: return .maxOracleValidations
            case .attributedBuilds: return .maxAttributedBuilds
            case .attributedCharactersWritten: return .maxAttributedCharactersWritten
            case .storageFullReplacements: return .maxStorageFullReplacements
            case .imageDecodes: return .maxImageDecodes
            case .fileBytesRead: return .maxFileBytesRead
            case .mainThreadBlockedNanos: return .maxMainThreadBlockedNanos
            }
        }
    }

    private func collapse(
        _ event: DiagnosticEventName,
        data: [(key: DiagnosticField, value: DiagnosticValue)],
        at uptime: Double
    ) -> CollapseOutcome? {
        var window = repeatWindows[event] ?? RepeatWindow(windowStart: uptime, count: 0, suppressed: 0)
        if uptime - window.windowStart >= 1.0 {
            let suppressed = window.suppressed
            repeatWindows[event] = RepeatWindow(windowStart: uptime, count: 1, suppressed: 0)
            return suppressed > 0 ? .summarize(suppressed, window.sums, window.maxima) : nil
        }
        window.count += 1
        if window.count > Self.repeatCollapseThreshold {
            window.suppressed += 1
            if event == .workLedger {
                for item in data {
                    guard let value = item.value.uintValue else { continue }
                    window.sums[item.key, default: 0] &+= value
                    window.maxima[item.key] = max(window.maxima[item.key] ?? 0, value)
                }
            }
            repeatWindows[event] = window
            return .suppress
        }
        repeatWindows[event] = window
        return nil
    }

    private func appendLine(_ line: String) {
        observeSizeLimit(writeCoordinator.appendUnsequenced([line]))
    }

    private func observeSizeLimit(_ write: Task<Bool, Never>?) {
        guard let write else { return }
        Task { @MainActor [weak self] in
            if await write.value { self?.noteSizeLimitReached() }
        }
    }

    func flush() {
        // Records are handed to the serialized writer as they are created. This method remains
        // as a no-op compatibility point for callers that used to trigger buffered writes.
    }

    /// Records the cap once, as a well-formed record rather than a hand-written fragment.
    private func noteSizeLimitReached() {
        guard !sizeLimitRecorded, !closed else { return }
        sizeLimitRecorded = true
        record(
            .sizeLimitReached,
            level: .warn,
            category: .diagnostics,
            data: [(.totalBytes, .int(Self.maximumFileBytes))]
        )
    }

    /// Writes the terminating record so a reader can distinguish a clean exit from a crash.
    func finish() {
        guard !closed else { return }
        // Emit any repeats still suppressed so the file never understates what happened.
        let uptime = Double(DispatchTime.now().uptimeNanoseconds - startUptimeNanos) / 1_000_000_000
        for (event, window) in repeatWindows.sorted(by: { $0.key.rawValue < $1.key.rawValue })
        where window.suppressed > 0 {
            appendCollapseSummary(of: event, count: window.suppressed, sums: window.sums, maxima: window.maxima, uptime: uptime)
        }
        repeatWindows.removeAll()
        closed = true
        flush()
        let timestamp = Date()
        let durability = writeCoordinator.closeAfterAppending { sequence in
            DiagnosticRecord(
                wallClock: timestamp,
                uptimeSeconds: uptime,
                sequence: sequence,
                level: .info,
                category: .lifecycle,
                event: .runEnd,
                data: [(.count, .uint(sequence - 1))]
            ).jsonLine
        }
        durabilityTask = durability
        Task { @MainActor [weak self] in
            await durability.value
            self?.allowSuddenTermination()
        }
    }

    /// Balances the `disableSuddenTermination` taken in `init`, exactly once.
    private func allowSuddenTermination() {
        guard suddenTerminationDisabled else { return }
        suddenTerminationDisabled = false
        ProcessInfo.processInfo.enableSuddenTermination()
    }

    deinit {
        if suddenTerminationDisabled {
            ProcessInfo.processInfo.enableSuddenTermination()
        }
    }

    /// Blocks the caller until every queued record has reached the file. Test support only.
    func drain() async {
        flush()
        await writeCoordinator.drain()
    }

    /// Supplies the watchdog with a direct serialized-sink route that never hops through the
    /// main actor. Atomic sequence-and-writer reservation preserves ordering and privacy.
    func makeProcessFaultReporter() -> @Sendable (UInt64) -> Void {
        let writer = self.writeCoordinator
        let start = self.startUptimeNanos
        return { millis in
            let timestamp = Date()
            _ = writer.appendRecord { sequence in
                DiagnosticRecord(
                    wallClock: timestamp,
                    uptimeSeconds: Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000_000,
                    sequence: sequence,
                    level: .fault,
                    category: .lifecycle,
                    event: .mainActorStall,
                    data: [(.millis, .uint(millis))]
                ).jsonLine
            }
        }
    }

    /// Terminal flush for `applicationWillTerminate`.
    ///
    /// // REQ-095: the terminating record must reach disk before the process exits, so an
    /// // agent can tell a clean exit from a crash. The serialized appender runs off the main
    /// // actor, so blocking the main thread cannot deadlock the bounded wait.
    func finishSynchronously(timeoutSeconds: Double = 2) {
        finish()
        let pending = durabilityTask
        guard let pending else { return }
        let gate = DispatchSemaphore(value: 0)
        Task.detached {
            await pending.value
            gate.signal()
        }
        _ = gate.wait(timeout: .now() + timeoutSeconds)
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
