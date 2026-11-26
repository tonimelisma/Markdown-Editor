//
//  AppUpdaterTests.swift
//  Markdown EditorTests
//

import Foundation
import Testing
@testable import Markdown_Editor

/// REQ-033/034: which builds update themselves, and what the built bundle tells Sparkle.
///
/// // What makes these red: dropping any guard in `AppUpdater.updatesItself` (the matrix), putting
/// // the update key into the Debug configuration or turning system profiling on (the bundle
/// // test), or starting the updater in a test host (the last test). Whether an installed copy
/// // really updates is proved only by a published release reaching it — no test here can.
struct AppUpdaterTests {
    private static let key = "cNfGpuDnEMlBbZwHydswCggLeu07YkLG/aL4QSfS/Yk="
    private static let feed = "https://github.com/owner/name/releases/latest/download/appcast.xml"

    // Verifies: REQ-033/034 — the one combination that updates, and each guard on its own.
    @Test func onlyAKeyedBuildOutsideVerificationUpdatesItself() {
        #expect(AppUpdater.updatesItself(publicKey: Self.key, feedURL: Self.feed, isTestHost: false, isVerificationRun: false))

        #expect(!AppUpdater.updatesItself(publicKey: nil, feedURL: Self.feed, isTestHost: false, isVerificationRun: false))
        #expect(!AppUpdater.updatesItself(publicKey: "", feedURL: Self.feed, isTestHost: false, isVerificationRun: false))
        #expect(!AppUpdater.updatesItself(publicKey: "  \n", feedURL: Self.feed, isTestHost: false, isVerificationRun: false))
        #expect(!AppUpdater.updatesItself(publicKey: Self.key, feedURL: nil, isTestHost: false, isVerificationRun: false))
        #expect(!AppUpdater.updatesItself(
            publicKey: Self.key, feedURL: Self.feed.replacingOccurrences(of: "https:", with: "http:"),
            isTestHost: false, isVerificationRun: false
        ))
        #expect(!AppUpdater.updatesItself(publicKey: Self.key, feedURL: "", isTestHost: false, isVerificationRun: false))
        #expect(!AppUpdater.updatesItself(publicKey: Self.key, feedURL: Self.feed, isTestHost: true, isVerificationRun: false))
        #expect(!AppUpdater.updatesItself(publicKey: Self.key, feedURL: Self.feed, isTestHost: false, isVerificationRun: true))
    }

    // Verifies: REQ-033/034 — the Debug bundle hosting these tests carries the feed but no key, and
    // asks Sparkle for no system profile.
    @Test func theDebugBundleNeverUpdatesItselfAndSendsNoProfile() throws {
        let info = try #require(Bundle.main.infoDictionary)
        let feed = try #require(info["SUFeedURL"] as? String)
        let url = try #require(URL(string: feed))
        #expect(url.scheme == "https")
        #expect(url.host == "github.com")
        #expect(url.path.hasSuffix("/releases/latest/download/appcast.xml"))
        #expect(((info["SUPublicEDKey"] as? String) ?? "").isEmpty, "a Debug build carries the update key")
        #expect((info["SUEnableSystemProfiling"] as? Bool) == false)
    }

    // Verifies: REQ-034 — this test host did not start an updater.
    @MainActor
    @Test func theTestHostDoesNotUpdateItself() {
        #expect(!AppUpdater.isEnabledForThisProcess)
    }
}
