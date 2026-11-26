//
//  PrivacyBoundaryTests.swift
//  Markdown EditorTests
//

import Foundation
import Testing
@testable import Markdown_Editor

struct PrivacyBoundaryTests {
    // Verifies: REQ-030/031 — production source and project configuration contain no network,
    // account, authentication, analytics, telemetry, or tracking capability of their own (the
    // update check, REQ-033, is Sparkle's and is bounded by `onlyTheUpdaterImportsSparkle`).
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
        #expect(!hasForbiddenLinkedFramework(project))
        let injectedForbiddenFramework = project.replacingOccurrences(
            of: "A1B2C3D43010892B00668304 /* cmark-gfm in Frameworks */",
            with: "A1B2C3D43010892B00668304 /* cmark-gfm in Frameworks */, Network.framework"
        )
        #expect(hasForbiddenLinkedFramework(injectedForbiddenFramework))
        #expect(!project.contains("Firebase"))
        #expect(!project.contains("Analytics"))
        #expect(!project.contains("AuthenticationServices"))

        // The repository's own files, not build output: hidden folders (`.build`, `.git`) are
        // skipped, because a package checkout under `.build` carries its own entitlements (Sparkle's
        // does) and none of them is this app's. The walk proves it saw the project by finding its
        // Info.plist, so an empty walk cannot pass for "no entitlements".
        let repositoryFiles = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        )?.compactMap { $0 as? URL } ?? []
        #expect(repositoryFiles.contains { $0.path.hasSuffix("Markdown Editor/Info.plist") }, "the walk did not reach the project")
        let entitlements = repositoryFiles.filter { $0.pathExtension == "entitlements" }
        #expect(entitlements.isEmpty, "entitlements files: \(entitlements.map(\.path))")
    }

    // Verifies: REQ-030/033 — Sparkle, the application's only network access, is imported by one
    // production file, so no other code can reach the network through it. The detector proves
    // itself by finding that one file.
    @Test func onlyTheUpdaterImportsSparkle() throws {
        let importers = try productionSourceFiles().filter { file in
            let text = try String(contentsOf: file, encoding: .utf8)
            return text.range(of: #"(?m)^\s*(@preconcurrency\s+)?import\s+Sparkle\b"#, options: .regularExpression) != nil
        }.map(\.lastPathComponent)
        #expect(importers == ["AppUpdater.swift"], "Sparkle importers: \(importers)")
    }

    // Verifies: REQ-031/089; ARC-016 — diagnostic payloads are a closed, local-safe value set and
    // cannot carry document text, URLs, paths, or arbitrary data.
    //
    // // COR-90 replaced a source grep (`!source.contains("case string(")`) with this. The grep
    // // asserted the *text* of DiagnosticValue.swift, so it proved nothing about behaviour, had
    // // no self-check on its own needles, and would have passed had the needle been misspelled.
    // // The switch below is compiler-enforced: adding a case to `DiagnosticValue` makes it
    // // non-exhaustive and the test target stops building until someone declares what the new
    // // case may carry.
    @Test func diagnosticPayloadsCannotCarryFreeText() {
        /// What a value is allowed to contribute to a payload.
        enum Admissible { case numeric, closedVocabulary }

        func classify(_ value: DiagnosticValue) -> Admissible {
            switch value {
            case .int, .uint, .double, .bool: return .numeric
            case .symbol: return .closedVocabulary
            }
        }

        // One representative of every case, so the classification above is exercised rather than
        // merely compiled.
        let samples: [DiagnosticValue] = [
            .int(-1), .uint(2), .double(3.5), .bool(true), .symbol(.documentOpen),
        ]
        for sample in samples where classify(sample) == .numeric {
            #expect(
                !sample.jsonFragment.contains("\""),
                "a numeric diagnostic value emitted a quoted fragment: \(sample.jsonFragment)"
            )
        }

        // The only case that emits quoted text draws it from a closed enum, so the emitted text
        // cannot originate from a document. Proved over the whole vocabulary, not one member.
        #expect(!DiagnosticSymbol.allCases.isEmpty)
        for symbol in DiagnosticSymbol.allCases {
            let raw = symbol.rawValue
            #expect(
                !raw.isEmpty
                    && raw.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" },
                "DiagnosticSymbol.\(raw) is not a plain identifier and could smuggle text"
            )
        }
    }

    private func sourceURL(_ relativePath: String) -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(relativePath)
    }

    private func hasForbiddenLinkedFramework(_ project: String) -> Bool {
        let linkedFrameworkPhase = project.components(
            separatedBy: "/* Begin PBXFrameworksBuildPhase section */"
        ).dropFirst().first ?? ""
        return [
            "Network.framework", "AuthenticationServices.framework", "CloudKit.framework", "WebKit.framework"
        ].contains { linkedFrameworkPhase.contains($0) }
    }
}
