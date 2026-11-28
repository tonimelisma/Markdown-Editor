//
//  ScreenshotSceneTests.swift
//  Markdown EditorTests
//

import AppKit
import Foundation
import Testing
@testable import Markdown_Editor

/// The screenshot gallery's scene selector.
///
/// // Validates: REQ-144, REQ-151 — `Scripts/screenshots.sh` photographs screens an ordinary launch
/// // does not reach, and CLAUDE.md §4 forbids reaching them by driving the UI. The application
/// // therefore presents the named screen itself, through the same window-scoped command route a
/// // toolbar click uses. These prove that route works, that it cannot change a document, and
/// // that the enum and the script's scene table cannot drift apart.
@MainActor
struct ScreenshotSceneTests {

    private static func scriptText() throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Scripts/screenshots.sh")
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// Scene names in the script's `scenes=(…)` table, read from field 3 of each row.
    private static func scriptSceneNames() throws -> Set<String> {
        let text = try scriptText()
        guard let table = text.range(of: "scenes=(") else { return [] }
        let rest = text[table.upperBound...]
        guard let close = rest.range(of: "\n)") else { return [] }
        var names: Set<String> = []
        for line in rest[..<close.lowerBound].split(separator: "\n") {
            let row = line.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            let fields = row.split(separator: "|", omittingEmptySubsequences: false)
            guard fields.count >= 3 else { continue }
            names.insert(String(fields[2]))
        }
        return names
    }

    // The set is closed on both sides: a new `SmokeScene` case is unphotographed until the
    // script gains a row, and a script row naming a scene the app cannot present would fail
    // silently at capture time instead of here.
    // Validates: REQ-151 — every declared scene is in the gallery, and every gallery row is a
    // declared scene.
    @Test func galleryScriptAndSceneEnumAgree() throws {
        let script = try Self.scriptSceneNames()
        #expect(!script.isEmpty, "no scene table found in Scripts/screenshots.sh; this would pass vacuously")
        let declared = Set(MarkdownAppDelegate.SmokeScene.allCases.map(\.rawValue))
        #expect(declared.subtracting(script).isEmpty, "scenes never photographed: \(declared.subtracting(script).sorted())")
        #expect(script.subtracting(declared).isEmpty, "script names unknown scenes: \(script.subtracting(declared).sorted())")
    }

    // The variable alone changes nothing outside a smoke launch, like every other smoke
    // affordance (REQ-144). The test host is not a smoke run, so this is the real gate.
    // Validates: REQ-144 — the scene selector is gated on the smoke argument.
    @Test func sceneSelectionRequiresTheSmokeArgument() {
        setenv("MARKDOWN_EDITOR_SMOKE_SCENE", "source", 1)
        defer { unsetenv("MARKDOWN_EDITOR_SMOKE_SCENE") }
        #expect(MarkdownAppDelegate.isSmokeRun == false, "the test host is not a smoke run")
        #expect(
            MarkdownAppDelegate.smokeScene == nil,
            "an environment variable alone selected a scene outside a smoke run"
        )
    }

    // Validates: REQ-151 — the Source scene is presented through the ordinary command route.
    @Test func sourceSceneSelectsSourceModeWithoutChangingTheDocument() throws {
        let fixture = try SceneFixture(text: "# Title\n\nBody with a [link](https://example.com).\n")
        defer { fixture.tearDown() }
        fixture.session.setMode(.wysiwyg)

        #expect(MarkdownAppDelegate.presentSmokeScene(.source, using: fixture.controller))
        #expect(fixture.session.mode == .source)
        #expect(fixture.document.text == fixture.originalText)
        #expect(fixture.document.sourceVersion == fixture.originalVersion)
    }

    // Validates: REQ-151 — the WYSIWYG scene is the rendered reading surface.
    @Test func wysiwygSceneSelectsTheReadingSurface() throws {
        let fixture = try SceneFixture(text: "# Title\n\nBody.\n")
        defer { fixture.tearDown() }
        fixture.session.setMode(.source)

        #expect(MarkdownAppDelegate.presentSmokeScene(.wysiwyg, using: fixture.controller))
        #expect(fixture.session.mode == .wysiwyg)
        #expect(fixture.document.text == fixture.originalText)
    }

    // The sheet must show a real destination: a capture of an empty field would document
    // nothing about link editing. It is opened, never committed, so source is untouched.
    // Validates: REQ-151, REQ-108 — the link scene opens the sheet prefilled from a selected link.
    @Test func linkSceneOpensTheSheetPrefilledFromTheSelectedLink() throws {
        let fixture = try SceneFixture(text: "Body with a [link](https://example.com) inside.\n")
        defer { fixture.tearDown() }
        try fixture.installProjection()

        #expect(MarkdownAppDelegate.presentSmokeScene(.linkSheet, using: fixture.controller))
        #expect(fixture.session.mode == .wysiwyg)
        #expect(fixture.controller.linkSheetPresented)
        #expect(fixture.controller.linkDestination == "https://example.com")
        #expect(fixture.document.text == fixture.originalText)
        #expect(fixture.document.sourceVersion == fixture.originalVersion)
    }

    // Without a current presentation there is nothing to select and nothing valid to photograph,
    // so the scene refuses rather than capturing a sheet over stale or empty content (ARC-004).
    // Validates: REQ-151, REQ-093 — an unpresentable scene is refused, not faked.
    @Test func linkSceneRefusesWithoutACurrentPresentation() throws {
        let fixture = try SceneFixture(text: "Body with a [link](https://example.com) inside.\n")
        defer { fixture.tearDown() }
        fixture.session.setMode(.wysiwyg)
        #expect(fixture.session.presentation == nil)

        #expect(MarkdownAppDelegate.presentSmokeScene(.linkSheet, using: fixture.controller) == false)
        #expect(!fixture.controller.linkSheetPresented)
        #expect(fixture.document.text == fixture.originalText)
    }

    /// One document, session, router, and controller — the objects a single window owns.
    @MainActor
    private final class SceneFixture {
        let document = MarkdownDocument()
        let session = EditorSession()
        let router = EditorActionRouter()
        let controller = EditorCommandController()
        let originalText: String
        let originalVersion: UInt64

        init(text: String) throws {
            document.installTextForTesting(text)
            session.attach(document: document)
            // Source mode is the deterministic starting point: WYSIWYG availability otherwise
            // depends on an asynchronous authoritative parse a synchronous test must not race.
            session.setMode(.source)
            controller.bind(document: document, session: session, actionRouter: router, window: nil)
            originalText = document.text
            originalVersion = document.sourceVersion
        }

        /// Installs the authoritative presentation the running application would have built by
        /// the time the gallery script captures a frame.
        func installProjection() throws {
            let tree = try #require(
                MarkdownParser.parse(document.text, sourceVersion: document.sourceVersion).get()
            )
            let model = MarkdownProjectionModel.build(
                tree: tree,
                index: MarkdownSourceIndex(source: document.text, sourceVersion: document.sourceVersion)
            )
            session.setMode(.wysiwyg)
            session.installProjectionForTesting(model, tree: tree)
        }

        func tearDown() {
            session.detach()
        }
    }
}
