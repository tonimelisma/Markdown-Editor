//
//  PrivacyBoundaryTests.swift
//  Markdown EditorTests
//

import Foundation
import Testing
@testable import Markdown_Editor

struct PrivacyBoundaryTests {
    // Verifies: REQ-030/031 — production source and project configuration contain no network,
    // account, authentication, analytics, telemetry, or tracking capability.
    @Test func productionBoundaryRejectsNetworkAccountAndAnalyticsCapabilities() throws {
        let root = sourceURL("")
        let productionFiles = (FileManager.default.enumerator(at: root.appendingPathComponent("Markdown Editor"), includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL } ?? []).filter { $0.pathExtension == "swift" || $0.pathExtension == "plist" }
        let forbidden = [
            "import Network", "import AuthenticationServices", "import CloudKit", "import WebKit",
            "URLSession", "URLSessionWebSocketTask", "NWConnection", "NWPathMonitor",
            "ASAuthorization", "AuthenticationServices", "OAuth", "Firebase", "Mixpanel",
            "Sentry", "CKContainer", "CloudKit", "SecItem", "Keychain", "TelemetryClient",
            "AnalyticsClient", "NSUserTrackingUsageDescription"
        ]
        for file in productionFiles {
            let contents = try String(contentsOf: file, encoding: .utf8)
            for token in forbidden { #expect(!contents.contains(token), "Forbidden privacy capability \(token) in \(file.path)") }
        }

        let project = try String(contentsOf: root.appendingPathComponent("Markdown Editor.xcodeproj/project.pbxproj"), encoding: .utf8)
        #expect(!project.contains("CODE_SIGN_ENTITLEMENTS"))
        #expect(project.contains("cmark-gfm"))
        #expect(project.contains("cmark-gfm-extensions"))
        #expect(!project.contains("Firebase"))
        #expect(!project.contains("Analytics"))
        #expect(!project.contains("AuthenticationServices"))

        let entitlements = (FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL } ?? []).filter { $0.pathExtension == "entitlements" }
        #expect(entitlements.isEmpty)
    }

    // Verifies: REQ-031 — diagnostic payloads are a closed, local-safe value set and cannot carry
    // URLs, arbitrary data, or secret/account values.
    @Test func diagnosticPayloadsAreClosedAndPrivacySafe() throws {
        let source = try String(contentsOf: sourceURL("Markdown Editor/DiagnosticValue.swift"), encoding: .utf8)
        #expect(source.contains("enum DiagnosticValue"))
        #expect(source.contains("case int("))
        #expect(source.contains("case bool("))
        #expect(!source.contains("case string("))
        #expect(!source.contains("case url("))
        #expect(!source.contains("case data("))
    }

    private func sourceURL(_ relativePath: String) -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(relativePath)
    }
}
