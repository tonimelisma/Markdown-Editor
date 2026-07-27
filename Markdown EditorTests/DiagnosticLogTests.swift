//
//  DiagnosticLogTests.swift
//  Markdown EditorTests
//
//  REQ-089/095/096; ARC-016: per-run JSON Lines diagnostics that cannot represent content.
//

import Testing
import AppKit
import Foundation
@testable import Markdown_Editor

@MainActor
struct DiagnosticLogTests {

    private func makeTemporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("diagnostics-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Decodes one JSON Lines record into a dictionary.
    private func object(_ line: String) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any]
    }

    private func lines(of log: DiagnosticLog) async -> [String] {
        await log.drain()
        let text = (try? String(contentsOf: log.fileURL, encoding: .utf8)) ?? ""
        return text.split(separator: "\n").map(String.init)
    }

    // Verifies: REQ-089; ARC-016 — the payload value type has no string case, so document
    // content, URLs, filenames, and paths are unrepresentable rather than merely omitted.
    @Test func diagnosticPayloadHasNoStringCase() {
        // Exhaustive over `DiagnosticValue`: adding a `.string` case fails to compile here.
        let samples: [DiagnosticValue] = [
            .int(-3), .uint(7), .double(1.5), .bool(true), .symbol(.wysiwyg)
        ]
        for value in samples {
            switch value {
            case .int, .uint, .double, .bool, .symbol:
                continue
            }
        }
        // Every symbol is a compile-time literal from a closed vocabulary.
        #expect(DiagnosticSymbol.allCases.allSatisfy { !$0.rawValue.isEmpty })
        #expect(DiagnosticValue.symbol(.setLink).jsonFragment == "\"setLink\"")
    }

    // Verifies: REQ-089 — no `EditorTraceEvent` maps onto a payload carrying free text.
    @Test func everyTraceEventMapsToSymbolicPayload() {
        let events: [EditorTraceEvent] = [
            .mutationRefused(id: UUID(), reason: .contentMismatch),
            .editRouted(context: .wysiwyg, groupingTyping: true, planner: PlannerKind(.toggleBold)),
            .editRefused(category: .refusal(.crossCell)),
            .editRefused(category: .invalidPresentationTransition),
            .reconciliationDiscarded(sourceRevision: 3, reason: .identityMismatch),
            .viewReconciliationViolation(kind: .publication),
            .mainActorStall(millis: 1_400)
        ]
        for event in events {
            let mapped = JSONLinesEditorTrace.map(event)
            for field in mapped.data {
                if case .symbol(let symbol) = field.value {
                    #expect(DiagnosticSymbol.allCases.contains(symbol))
                }
            }
        }
    }

    // Verifies: REQ-095 — the first record identifies the run, including whether it is
    // production usage or a hosted test run.
    @Test func runHeaderIdentifiesHostKindAndBuild() async {
        let log = DiagnosticLog(directory: makeTemporaryDirectory(), hostKind: .unitTest)
        log.record(.documentOpened, level: .info, category: .document, document: 1)
        let recorded = await lines(of: log)

        #expect(recorded.count >= 2)
        let header = object(recorded[0])
        let run = header?["run"] as? [String: Any]
        #expect(run?["host"] as? String == "unitTest")
        #expect(run?["id"] as? String != nil)
        #expect(run?["build"] as? String != nil)
        #expect(header?["v"] as? Int == DiagnosticRunHeader.schemaVersion)
    }

    // Verifies: REQ-095 — every record is one parsable JSON object on its own line with a
    // strictly increasing sequence number, so a truncated run still reads cleanly.
    @Test func everyRecordIsOneParsableJSONLine() async {
        let log = DiagnosticLog(directory: makeTemporaryDirectory(), hostKind: .unitTest)
        for index in 0..<10 {
            log.record(
                .presentationInstalled,
                level: .debug,
                category: .projection,
                document: 1,
                data: [(.snapshot, .uint(UInt64(index)))]
            )
        }
        let recorded = await lines(of: log)

        var previousSequence = -1
        for line in recorded {
            let decoded = object(line)
            #expect(decoded != nil, "line is not valid JSON")
            let sequence = decoded?["seq"] as? Int ?? -1
            #expect(sequence > previousSequence)
            previousSequence = sequence
        }
        #expect(recorded.count == 11)
    }

    // Verifies: REQ-095 — the terminating record distinguishes a clean exit from a crash.
    @Test func finishWritesTerminatingRecord() async {
        let log = DiagnosticLog(directory: makeTemporaryDirectory(), hostKind: .unitTest)
        log.record(.documentOpened, level: .info, category: .document)
        log.finish()
        let recorded = await lines(of: log)

        #expect(recorded.last?.contains("\"ev\":\"runEnd\"") == true)
        // Records after termination are dropped rather than appended past the end marker.
        log.record(.documentClosed, level: .info, category: .document)
        let afterFinish = await lines(of: log)
        #expect(afterFinish.count == recorded.count)
    }

    // Verifies: REQ-096 — a defect firing every run-loop pass produces bounded evidence.
    @Test func repeatedEventsCollapseWithCount() async {
        let log = DiagnosticLog(directory: makeTemporaryDirectory(), hostKind: .unitTest)
        let burst = DiagnosticLog.repeatCollapseThreshold * 5
        for _ in 0..<burst {
            log.record(.hostUpdateEnded, level: .debug, category: .viewUpdate)
        }
        log.finish()
        let recorded = await lines(of: log)

        let emitted = recorded.filter { $0.contains("\"ev\":\"hostUpdateEnded\"") }.count
        #expect(emitted <= DiagnosticLog.repeatCollapseThreshold + 1)
        let summaries = recorded.filter {
            $0.contains("\"ev\":\"repeated\"") && $0.contains("\"of\":\"hostUpdateEnded\"")
        }
        #expect(summaries.count == 1)
        let suppressed = burst - emitted
        #expect(summaries.first?.contains("\"count\":\(suppressed)") == true)
    }

    // Verifies: REQ-095 — retention keeps the newest runs and removes the oldest.
    @Test func retentionRemovesOldestRuns() throws {
        let directory = makeTemporaryDirectory()
        let manager = FileManager.default
        // Distinct modification dates so ordering is deterministic.
        for index in 0..<8 {
            let url = directory.appendingPathComponent("run-2026072\(index)T000000Z-\(index).jsonl")
            manager.createFile(atPath: url.path, contents: Data("{}\n".utf8))
            try manager.setAttributes(
                [.modificationDate: Date(timeIntervalSince1970: 1_000 + Double(index) * 60)],
                ofItemAtPath: url.path
            )
        }

        DiagnosticLog.pruneRuns(in: directory, keeping: 3)

        let remaining = try manager.contentsOfDirectory(atPath: directory.path).sorted()
        #expect(remaining.count == 3)
        #expect(remaining.contains("run-20260727T000000Z-7.jsonl"))
        #expect(!remaining.contains("run-20260720T000000Z-0.jsonl"))
    }

    // Verifies: REQ-095 — a document wires the production sink and records its own lifecycle.
    @Test func documentRecordsLifecycleThroughSink() async {
        let log = DiagnosticLog(directory: makeTemporaryDirectory(), hostKind: .unitTest)
        let document = MarkdownDocument()
        document.trace = JSONLinesEditorTrace(log: log)
        document.installTextForTesting("# Hello\n")
        document.trace?.record(.documentOpened(utf16Count: 8))
        let recorded = await lines(of: log)

        let opened = recorded.filter { $0.contains("\"ev\":\"documentOpened\"") }
        #expect(opened.count == 1)
        #expect(opened.first?.contains("\"utf16Count\":8") == true)
        // Documents appear as opaque handles, never as names or paths.
        #expect(opened.first?.contains("\"doc\":1") == true)
    }
}
