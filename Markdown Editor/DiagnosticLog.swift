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
    let evidenceSession: String?

    init(
        runID: String,
        startedAt: Date,
        hostKind: DiagnosticHostKind,
        shortVersion: String,
        buildVersion: String,
        osVersion: String,
        processID: Int32,
        evidenceSession: String? = nil
    ) {
        self.runID = runID
        self.startedAt = startedAt
        self.hostKind = hostKind
        self.shortVersion = shortVersion
        self.buildVersion = buildVersion
        self.osVersion = osVersion
        self.processID = processID
        self.evidenceSession = evidenceSession
    }

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
                let session: String?
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
                pid: processID,
                session: evidenceSession
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
    private let reservedTerminalBytes: Int
    private var handle: FileHandle?
    private var bytesWritten = 0
    private var truncated = false

    init(url: URL, byteLimit: Int, reservedTerminalBytes: Int = 0) {
        self.url = url
        self.byteLimit = byteLimit
        self.reservedTerminalBytes = min(max(reservedTerminalBytes, 0), byteLimit)
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
            if bytesWritten + payload.count + encoded.count > byteLimit - reservedTerminalBytes {
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

    /// Appends terminal records after ordinary writes have reached their reserved limit. The
    /// reservation keeps terminal records within the file-size bound while preserving the
    /// ordinary sink's refusal semantics for all later writes. A capped run needs both its cap
    /// marker and its run-end marker.
    @discardableResult
    func appendTerminal(_ lines: [String]) -> Bool {
        guard !lines.isEmpty else { return false }
        if handle == nil {
            FileManager.default.createFile(atPath: url.path, contents: nil)
            handle = try? FileHandle(forWritingTo: url)
        }
        guard let handle else { return false }
        var payload = Data()
        for line in lines {
            guard let encoded = (line + "\n").data(using: .utf8) else { continue }
            guard bytesWritten + payload.count + encoded.count <= byteLimit else { return false }
            payload.append(encoded)
        }
        guard !payload.isEmpty else { return false }
        try? handle.write(contentsOf: payload)
        bytesWritten += payload.count
        return true
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
    static var maximumFileBytes: Int {
        // A complete COR-69 matrix intentionally emits more structured route evidence than an
        // ordinary user run. Keep normal retention bounded at 8 MiB, while allowing the explicit
        // process benchmark to retain its terminal runEnd and all case ledgers.
        ProcessInfo.processInfo.environment["MARKDOWN_EDITOR_BENCHMARK"] == "1"
            ? 64 * 1024 * 1024
            : 8 * 1024 * 1024
    }
    static let flushRecordThreshold = 64
    static let flushInterval: Duration = .milliseconds(250)
    /// Above this count within one second, an identical event collapses into a summary.
    static let repeatCollapseThreshold = 20

    let header: DiagnosticRunHeader
    let fileURL: URL

    private let startUptimeNanos: UInt64
    private let writeCoordinator: DiagnosticWriteCoordinator
    /// Production route records are copied to the gate-owned FIFO by this internal writer. The
    /// writer is not addressable through the editor trace protocol or an evidence-origin argument.
    private let coverageRecorder: JSONLinesEditorTrace.ProductionRouteCoverageRecorder?
    private var durabilityTask: Task<Void, Never>?
    private var closed = false
    private var suddenTerminationDisabled = false
    private let byteLimit: Int

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

    init(
        directory: URL,
        hostKind: DiagnosticHostKind,
        startedAt: Date = Date(),
        byteLimit: Int? = nil
    ) {
        let runID = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12)
        let configuredByteLimit = byteLimit ?? Self.maximumFileBytes
        self.byteLimit = configuredByteLimit
        let bundle = Bundle.main.infoDictionary
        header = DiagnosticRunHeader(
            runID: String(runID),
            startedAt: startedAt,
            hostKind: hostKind,
            shortVersion: (bundle?["CFBundleShortVersionString"] as? String) ?? "0",
            buildVersion: (bundle?["CFBundleVersion"] as? String) ?? "0",
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            processID: ProcessInfo.processInfo.processIdentifier,
            evidenceSession: nil
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
        // Reserve room for both the cap marker and the clean-shutdown marker. A capped run must
        // retain enough terminal space for `sizeLimitReached` followed by `runEnd`.
        let terminalReservation = min(2048, max(1024, configuredByteLimit / 4))
        let sink = DiagnosticFileSink(
            url: fileURL,
            byteLimit: configuredByteLimit,
            reservedTerminalBytes: terminalReservation
        )
        writeCoordinator = DiagnosticWriteCoordinator(sink: sink)
        coverageRecorder = JSONLinesEditorTrace.ProductionRouteCoverageRecorder(hostKind: hostKind)
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
        data: [(key: DiagnosticField, value: DiagnosticValue)] = []
    ) {
        recordInternal(
            event,
            level: level,
            category: category,
            document: document,
            origin: .gateFixture,
            route: nil,
            data: data
        )
    }

    func recordEncodingProbe(
        _ event: DiagnosticEventName,
        level: DiagnosticLevel = .debug,
        category: DiagnosticCategory,
        document: UInt64? = nil,
        data: [(key: DiagnosticField, value: DiagnosticValue)] = []
    ) {
        recordInternal(
            event,
            level: level,
            category: category,
            document: document,
            origin: .encodingProbe,
            route: nil,
            data: data
        )
    }

    /// The only application API that can produce production-route evidence. The route is a
    /// closed event identifier supplied by the production owner, never a caller-controlled
    /// evidence-origin argument. The record is copied to the gate-owned FIFO by the internal
    /// recorder only after the typed route identity matches the event.
    func recordProduction(
        _ event: DiagnosticEventName,
        level: DiagnosticLevel = .debug,
        category: DiagnosticCategory,
        document: UInt64? = nil,
        route: DiagnosticEventName,
        data: [(key: DiagnosticField, value: DiagnosticValue)] = []
    ) {
        guard event == route else { return }
        recordInternal(
            event,
            level: level,
            category: category,
            document: document,
            origin: .productionRoute,
            route: route,
            data: data
        )
    }

    /// Binds the intent recorder directly to the serialized writer. The binding reserves ledger
    /// records synchronously off-main, so termination cannot close the stream before late work is
    /// durable and no function-closure ownership cycle can recurse through the recorder.
    func installWorkLedgerWriter(on recorder: IntentRecorder) {
        recorder.setDurableWriter(writeCoordinator, startUptimeNanos: startUptimeNanos)
    }

    private func recordInternal(
        _ event: DiagnosticEventName,
        level: DiagnosticLevel,
        category: DiagnosticCategory,
        document: UInt64?,
        origin: DiagnosticEvidenceOrigin,
        route: DiagnosticEventName?,
        data: [(key: DiagnosticField, value: DiagnosticValue)]
    ) {
        guard !closed else { return }
        let uptime = Double(DispatchTime.now().uptimeNanoseconds - startUptimeNanos) / 1_000_000_000

        if let route, origin == .productionRoute {
            coverageRecorder?.record(
                event: event,
                level: level,
                category: category,
                route: route,
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
            productionRoute: route,
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
        productionRoute: DiagnosticEventName?,
        data: [(key: DiagnosticField, value: DiagnosticValue)],
        uptime: Double,
        terminal: Bool = false
    ) {
        let timestamp = Date()
        let terminalTimestamp = Date()
        let terminalUptime = Double(DispatchTime.now().uptimeNanoseconds - startUptimeNanos) / 1_000_000_000
        let capBytes = byteLimit
        _ = terminal
            ? writeCoordinator.appendTerminalRecord { sequence in
                DiagnosticRecord(
                    wallClock: timestamp,
                    uptimeSeconds: uptime,
                    sequence: sequence,
                    level: level,
                    category: category,
                    event: event,
                    document: document,
                    origin: origin,
                    productionRoute: productionRoute,
                    data: data
                ).jsonLine
            }
            : writeCoordinator.appendRecord({ sequence in
                DiagnosticRecord(
                    wallClock: timestamp,
                    uptimeSeconds: uptime,
                    sequence: sequence,
                    level: level,
                    category: category,
                    event: event,
                    document: document,
                    origin: origin,
                    productionRoute: productionRoute,
                    data: data
                ).jsonLine
            }, terminalOnTruncation: { sequence in
                DiagnosticRecord(
                    wallClock: terminalTimestamp,
                    uptimeSeconds: terminalUptime,
                    sequence: sequence,
                    level: .warn,
                    category: .diagnostics,
                    event: .sizeLimitReached,
                    data: [(.totalBytes, .int(capBytes))]
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
        let capBytes = byteLimit
        _ = writeCoordinator.appendRecord({ sequence in
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
        }, terminalOnTruncation: { sequence in
            DiagnosticRecord(
                wallClock: timestamp,
                uptimeSeconds: uptime,
                sequence: sequence,
                level: .warn,
                category: .diagnostics,
                event: .sizeLimitReached,
                data: [(.totalBytes, .int(capBytes))]
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
                    guard item.key.isWorkLedgerMeasurement else { continue }
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
        _ = writeCoordinator.appendUnsequenced([line])
    }

    func flush() {
        // Records are handed to the serialized writer as they are created. This method remains
        // as a no-op compatibility point for callers that used to trigger buffered writes.
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
        // `finish()` schedules this balance on the main actor, but this method is itself used
        // from the main actor immediately before process termination. Waiting for durability
        // without releasing the disable-sudden-termination token leaves the app alive forever:
        // the main actor cannot run the scheduled callback while the caller is blocked here.
        allowSuddenTermination()
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
