//
//  AppUpdater.swift
//  Markdown Editor
//

import AppKit
@preconcurrency import Sparkle

/// Self-update through Sparkle (REQ-033; `docs/DECISIONS.md`, "Cloud-first development").
///
/// CI builds every `main` commit whose checks passed and that changed the app, signs it, and
/// publishes it to GitHub Releases with Sparkle's feed (`Scripts/release.sh`). An installed copy
/// reads that feed every hour, downloads a newer build in the background, and installs it when the
/// app quits — `NSDocument` has already autosaved by then. Sparkle accepts a download only when its
/// EdDSA signature matches `SUPublicEDKey`. That key is derived in CI from a GitHub secret
/// (`Scripts/sparkle-key.sh`); releases are signed ad hoc unless a certificate is configured, which
/// Sparkle accepts because the update key, not the signing identity, is what stays the same.
///
/// This is the application's only network access (REQ-030): a request for the feed and, when it
/// names a newer build, the archive. No system profile is sent (`SUEnableSystemProfiling` is off).
///
/// Only a build that carries the update key updates itself, and never a test host or a smoke or
/// benchmark run. The key is set only in the Release configuration, so a Debug build — the one
/// Xcode runs, the tests host, and the smoke scripts launch — never replaces itself with a
/// published build.
@MainActor
final class AppUpdater {
    private let controller: SPUStandardUpdaterController

    private init() {
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }

    /// Starts the updater when this process should update itself; `nil` otherwise.
    static func startIfEnabled() -> AppUpdater? {
        isEnabledForThisProcess ? AppUpdater() : nil
    }

    /// Whether this process updates itself. Fixed for the process's lifetime, so the menu item's
    /// enabled state cannot disagree with whether an updater was started.
    static var isEnabledForThisProcess: Bool {
        updatesItself(
            publicKey: Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
            feedURL: Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
            isTestHost: MarkdownAppDelegate.isRunningUnitTests,
            isVerificationRun: MarkdownAppDelegate.isSmokeRun || BenchmarkDriver.isRequested
        )
    }

    /// The decision, as a pure function of its inputs.
    nonisolated static func updatesItself(
        publicKey: String?,
        feedURL: String?,
        isTestHost: Bool,
        isVerificationRun: Bool
    ) -> Bool {
        guard !isTestHost, !isVerificationRun else { return false }
        guard let key = publicKey?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else {
            return false
        }
        guard let feedURL, let url = URL(string: feedURL), url.scheme == "https", url.host != nil else {
            return false
        }
        return true
    }

    /// App ▸ Check for Updates…: Sparkle's own check, which shows what it finds.
    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
