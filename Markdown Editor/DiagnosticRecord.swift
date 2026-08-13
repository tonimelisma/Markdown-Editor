//
//  DiagnosticRecord.swift
//  Markdown Editor
//

import Foundation

/// Severity of one diagnostic record. Ordered so thresholds are comparable.
nonisolated enum DiagnosticLevel: String, Sendable, Equatable, Comparable, CaseIterable {
    case debug
    case info
    case warn
    case error
    case fault

    private var rank: Int {
        switch self {
        case .debug: return 0
        case .info: return 1
        case .warn: return 2
        case .error: return 3
        case .fault: return 4
        }
    }

    static func < (lhs: DiagnosticLevel, rhs: DiagnosticLevel) -> Bool {
        lhs.rank < rhs.rank
    }
}

/// Subsystem a record belongs to. Chosen so an agent can filter a run without reading every line.
nonisolated enum DiagnosticCategory: String, Sendable, Equatable, CaseIterable {
    case lifecycle
    case document
    case session
    case projection
    case edit
    case image
    case viewUpdate
    case diagnostics
}

/// One append-only diagnostic record.
///
/// // REQ-095: wall clock, monotonic uptime, strictly increasing sequence, level, category,
/// // event name, opaque document handle, and a flat payload of non-string values.
nonisolated struct DiagnosticRecord: Sendable, Equatable {
    let wallClock: Date
    let uptimeSeconds: Double
    let sequence: UInt64
    let level: DiagnosticLevel
    let category: DiagnosticCategory
    let event: DiagnosticEventName
    /// Opaque per-run document handle. Never a name, path, or URL.
    let document: UInt64?
    /// Set only on a `repeated` summary: the event whose repeats were collapsed.
    let collapsedEvent: DiagnosticEventName?
    /// Evidence provenance used by executable proof gates. Lifecycle records may omit it;
    /// ordinary records always carry an explicit origin.
    let origin: DiagnosticEvidenceOrigin?
    /// The production route's closed event name. Present only for observed production-route
    /// records, so a route checker can compare evidence with the reviewed map.
    let productionRoute: DiagnosticEventName?
    /// Present only on records written through the gate-owned production evidence channel.
    let evidenceChannel: String?
    /// Trusted harness identity supplied by the owning diagnostic run, never inferred from a
    /// copied log filename.
    let evidenceHarness: String?
    /// Random capture-session identity supplied by the gate and checked against its sidecar.
    let evidenceSession: String?
    let data: [(key: DiagnosticField, value: DiagnosticValue)]

    init(
        wallClock: Date,
        uptimeSeconds: Double,
        sequence: UInt64,
        level: DiagnosticLevel,
        category: DiagnosticCategory,
        event: DiagnosticEventName,
        document: UInt64? = nil,
        collapsedEvent: DiagnosticEventName? = nil,
        origin: DiagnosticEvidenceOrigin? = .gateFixture,
        productionRoute: DiagnosticEventName? = nil,
        evidenceChannel: String? = nil,
        evidenceHarness: String? = nil,
        evidenceSession: String? = nil,
        data: [(key: DiagnosticField, value: DiagnosticValue)] = []
    ) {
        self.wallClock = wallClock
        self.uptimeSeconds = uptimeSeconds
        self.sequence = sequence
        self.level = level
        self.category = category
        self.event = event
        self.document = document
        self.collapsedEvent = collapsedEvent
        self.origin = origin
        self.productionRoute = productionRoute
        self.evidenceChannel = evidenceChannel
        self.evidenceHarness = evidenceHarness
        self.evidenceSession = evidenceSession
        self.data = data
    }

    static func == (lhs: DiagnosticRecord, rhs: DiagnosticRecord) -> Bool {
        lhs.sequence == rhs.sequence
            && lhs.level == rhs.level
            && lhs.category == rhs.category
            && lhs.event == rhs.event
            && lhs.document == rhs.document
            && lhs.collapsedEvent == rhs.collapsedEvent
            && lhs.origin == rhs.origin
            && lhs.productionRoute == rhs.productionRoute
            && lhs.evidenceChannel == rhs.evidenceChannel
            && lhs.evidenceHarness == rhs.evidenceHarness
            && lhs.evidenceSession == rhs.evidenceSession
            && lhs.data.count == rhs.data.count
            && zip(lhs.data, rhs.data).allSatisfy { $0.key == $1.key && $0.value == $1.value }
    }

    /// One complete JSON object on one line, with no embedded newline.
    ///
    /// // REQ-095: every field is either a fixed literal or a number, so the line is well-formed
    /// // without escaping and cannot be broken by document content.
    var jsonLine: String {
        var parts: [String] = [
            "\"t\":\"\(DiagnosticTimestamp.iso8601Milliseconds(wallClock))\"",
            "\"up\":\(String(format: "%.6f", uptimeSeconds))",
            "\"seq\":\(sequence)",
            "\"lvl\":\"\(level.rawValue)\"",
            "\"cat\":\"\(category.rawValue)\"",
            "\"ev\":\"\(event.rawValue)\""
        ]
        if let document {
            parts.append("\"doc\":\(document)")
        }
        if let collapsedEvent {
            parts.append("\"of\":\"\(collapsedEvent.rawValue)\"")
        }
        if let origin {
            parts.append("\"origin\":\"\(origin.rawValue)\"")
        }
        if let productionRoute {
            parts.append("\"route\":\"\(productionRoute.rawValue)\"")
        }
        if let evidenceChannel {
            parts.append("\"channel\":\"\(evidenceChannel)\"")
        }
        if let evidenceHarness {
            parts.append("\"harness\":\"\(evidenceHarness)\"")
        }
        if let evidenceSession {
            parts.append("\"session\":\"\(evidenceSession)\"")
        }
        if !data.isEmpty {
            let fields = data.map { "\"\($0.key.rawValue)\":\($0.value.jsonFragment)" }
            parts.append("\"data\":{\(fields.joined(separator: ","))}")
        }
        return "{\(parts.joined(separator: ","))}"
    }
}

/// Closed vocabulary of payload field names.
nonisolated enum DiagnosticField: String, Sendable, Equatable, CaseIterable {
    case claimCount
    case cost
    case count
    case direction
    case durationNanos
    case editable
    case fileCount
    case fromPhase
    case fromSnapshot
    case generation
    case grouping
    case kind
    case length
    case level
    case location
    case millis
    case mode
    case metric
    case maxNanos
    case nameLength
    case origin
    case phase
    case planner
    case p50Nanos
    case p95Nanos
    case provisional
    case reason
    case budgetNanos
    case removedFileCount
    case replacementLength
    case revision
    case snapshot
    case sourceRevision
    case toPhase
    case totalBytes
    case updatesPerSecond
    case utf16Count
    case windowMillis
    case scope
    case intentID
    case orphaned
    case orphanReason
    case lateWork
    case documentParses
    case projectionCompiles
    case oracleValidations
    case attributedBuilds
    case attributedCharactersWritten
    case storageFullReplacements
    case imageDecodes
    case fileBytesRead
    case mainThreadBlockedNanos
    case hitchMillisPerSecond
    case longestFrameNanos
    case framesObserved
    case bytes
    case peakBytes
    // Repeated work-ledger records retain both dimensions of the collapsed work. These are
    // intentionally closed fields rather than a string-keyed map (ARC-016).
    case sumDocumentParses
    case maxDocumentParses
    case sumProjectionCompiles
    case maxProjectionCompiles
    case sumOracleValidations
    case maxOracleValidations
    case sumAttributedBuilds
    case maxAttributedBuilds
    case sumAttributedCharactersWritten
    case maxAttributedCharactersWritten
    case sumStorageFullReplacements
    case maxStorageFullReplacements
    case sumImageDecodes
    case maxImageDecodes
    case sumFileBytesRead
    case maxFileBytesRead
    case sumMainThreadBlockedNanos
    case maxMainThreadBlockedNanos

    var isWorkLedgerMeasurement: Bool {
        switch self {
        case .documentParses, .projectionCompiles, .oracleValidations, .attributedBuilds,
             .attributedCharactersWritten, .storageFullReplacements, .imageDecodes,
             .fileBytesRead, .mainThreadBlockedNanos:
            return true
        default:
            return false
        }
    }
}

/// Closed vocabulary of event names.
nonisolated enum DiagnosticEventName: String, Sendable, Equatable, CaseIterable {
    // lifecycle / diagnostics
    case runStart
    case runEnd
    case repeated
    case sizeLimitReached

    // document
    case documentOpened
    case documentClosed
    case documentLoaded
    case documentLoadFailed
    case documentSaveStarted
    case documentSaveSucceeded
    case documentSaveFailed
    case documentReverted
    case mutationRequested
    case mutationCommitted
    case mutationRefused
    case undoRegistered
    case historyApplied
    case historyRefused

    // projection / session
    case parseStarted
    case parseCompleted
    case parseCancelled
    case presentationInstalled
    case presentationTransition
    case presentationRecovered
    case reconciliationScheduled
    case reconciliationDiscarded
    case reconciliationApplied
    case availabilityChanged

    // edit
    case editRouted
    case editRefused
    case modeToggle
    case updateOrigin
    case compositionBegan
    case compositionCommitted
    case compositionCancelled
    case compositionRefusedStale

    // image
    case imageCacheStore
    case imageResolutionFailed

    // image placement (REQ-101/102; ARC-017)
    case imagePlacementPhase
    case imagePlacementStarted
    case imagePlacementCommitted
    case imagePlacementFailed
    case imagePlacementRolledBack
    case assetDirectoryPublished
    case userAlertPresented
    case performanceSummary
    case budgetExceeded
    case sourceHighlightWidened

    // view update
    case hostUpdateEnded
    case hostUpdateStorm
    case viewReconciliationViolation
    case mainActorStall
    case workLedger
    case frameStatistics
    case memoryFootprint
}

/// ISO-8601 formatting with millisecond resolution, computed without a shared formatter.
nonisolated enum DiagnosticTimestamp {
    static func iso8601Milliseconds(_ date: Date) -> String {
        var components = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let parts = components.dateComponents(
            [.year, .month, .day, .hour, .minute, .second, .nanosecond],
            from: date
        )
        let milliseconds = (parts.nanosecond ?? 0) / 1_000_000
        return String(
            format: "%04d-%02d-%02dT%02d:%02d:%02d.%03dZ",
            parts.year ?? 0,
            parts.month ?? 0,
            parts.day ?? 0,
            parts.hour ?? 0,
            parts.minute ?? 0,
            parts.second ?? 0,
            milliseconds
        )
    }

    /// Filename-safe compact UTC stamp: `20260727T141530Z`.
    static func compactUTC(_ date: Date) -> String {
        var components = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let parts = components.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date
        )
        return String(
            format: "%04d%02d%02dT%02d%02d%02dZ",
            parts.year ?? 0,
            parts.month ?? 0,
            parts.day ?? 0,
            parts.hour ?? 0,
            parts.minute ?? 0,
            parts.second ?? 0
        )
    }
}
