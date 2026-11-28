//
//  DiagnosticLifetimeTests.swift
//  Markdown EditorTests
//
//  COR-19 proof: diagnostics follow editor lifetimes, remain observable while the main actor is
//  blocked, and finish without waiting for a main-actor cleanup hop.
//

import AppKit
import Foundation
import Testing
@testable import Markdown_Editor

@MainActor
struct DiagnosticLifetimeTests {

    // Validates: REQ-110
    @Test func detachedSessionsReleaseAllSamplerRegistrations() {
        let coordinator = DiagnosticRunCoordinator()
        weak var releasedSession: EditorSession?

        for _ in 0..<100 {
            var session: EditorSession? = EditorSession(
                performanceSamplerCoordinator: coordinator
            )
            releasedSession = session
            let document = MarkdownDocument()
            document.installTextForTesting("# Lifetime\n")
            session?.attach(document: document)
            #expect(coordinator.liveRegistrationCount == 1)
            session?.detach()
            session = nil
            #expect(coordinator.liveRegistrationCount == 0)
        }

        #expect(releasedSession == nil)
    }

    // Validates: REQ-110
    @Test func samplerInvalidationIsIdempotentAndEmitsOneSummary() {
        let coordinator = DiagnosticRunCoordinator()
        let trace = InMemoryEditorTrace()
        let sampler = PerformanceSampler(trace: trace, coordinator: coordinator)
        sampler.record(.modeTransition, durationNanos: 20)

        sampler.invalidate()
        sampler.invalidate()
        sampler.record(.modeTransition, durationNanos: 30)

        let summaries = trace.eventsMatching {
            if case .performanceSummary = $0 { return true }
            return false
        }
        #expect(summaries.count == 1)
        #expect(coordinator.liveRegistrationCount == 0)
    }

    // Validates: REQ-096 — fault diagnostics remain durable while the main actor is blocked.
    @Test func processFaultReporterWritesWhileMainActorIsBlocked() async {
        let log = DiagnosticLog(directory: temporaryDirectory(), hostKind: .unitTest)
        let report = log.makeProcessFaultReporter()
        let reportTask = Task.detached {
            report(125)
        }

        occupyMainActor(seconds: 0.25)
        await reportTask.value
        await log.drain()
        let text = (try? String(contentsOf: log.fileURL, encoding: .utf8)) ?? ""
        #expect(text.contains("\"ev\":\"mainActorStall\""))
        log.finish()
        await log.drain()
    }

    // Validates: REQ-110
    @Test func synchronousFinishDoesNotWaitForMainActorCleanup() {
        let log = DiagnosticLog(directory: temporaryDirectory(), hostKind: .unitTest)
        let started = DispatchTime.now().uptimeNanoseconds
        log.finishSynchronously(timeoutSeconds: 1)
        let elapsed = DispatchTime.now().uptimeNanoseconds &- started

        #expect(elapsed < 1_000_000_000)
        let text = (try? String(contentsOf: log.fileURL, encoding: .utf8)) ?? ""
        #expect(text.contains("\"ev\":\"runEnd\""))
    }

    private func temporaryDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("diagnostic-lifetime-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
