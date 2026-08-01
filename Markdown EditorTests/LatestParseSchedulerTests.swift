//
//  LatestParseSchedulerTests.swift
//  Markdown EditorTests
//

import Foundation
import Testing
@testable import Markdown_Editor

@MainActor
struct LatestParseSchedulerTests {
    @Test func cancelledParserWaiterStopsBeforeSourceCopy() {
        let result = MarkdownParser.parse(
            String(repeating: "x", count: 100_000),
            sourceVersion: 1,
            isCancelled: { true }
        )
        #expect(result == .failure(.cancelled))
    }

    @Test func keepsOnlyNewestPendingRevision() {
        let scheduler = LatestParseScheduler()
        let source = { (version: UInt64) in
            LatestParseRequest(
                source: SourceSnapshot(text: "v\(version)", sourceVersion: version, locationGeneration: 1, fileURL: nil),
                operationGeneration: version
            )
        }
        #expect(scheduler.submit(source(1)))
        #expect(!scheduler.submit(source(2)))
        #expect(!scheduler.submit(source(3)))
        #expect(scheduler.requestedCount == 3)
        #expect(scheduler.discardedBeforeParseCount == 1)
        #expect(scheduler.hasRunningRequest)
        #expect(scheduler.hasPendingRequest)
        #expect(scheduler.pendingRequest?.operationGeneration == 3)
        #expect(scheduler.finish())
        #expect(!scheduler.hasPendingRequest)
        #expect(!scheduler.finish())
    }

    @Test func oneHundredRevisionsDiscardEveryOlderPendingRequest() {
        let scheduler = LatestParseScheduler()
        for version in 1...100 {
            let request = LatestParseRequest(
                source: SourceSnapshot(text: "v\(version)", sourceVersion: UInt64(version), locationGeneration: 1, fileURL: nil),
                operationGeneration: UInt64(version)
            )
            _ = scheduler.submit(request)
        }
        #expect(scheduler.requestedCount == 100)
        #expect(scheduler.discardedBeforeParseCount == 98)
        #expect(scheduler.pendingRequest?.operationGeneration == 100)
    }

    @Test func detachCancelsRunningAndPendingDemand() {
        let scheduler = LatestParseScheduler()
        let request = LatestParseRequest(
            source: SourceSnapshot(text: "", sourceVersion: 1, locationGeneration: 1, fileURL: nil),
            operationGeneration: 1
        )
        #expect(scheduler.submit(request))
        #expect(!scheduler.submit(request))
        scheduler.cancel()
        #expect(!scheduler.hasRunningRequest)
        #expect(!scheduler.hasPendingRequest)
        #expect(!scheduler.finish())
    }
}
