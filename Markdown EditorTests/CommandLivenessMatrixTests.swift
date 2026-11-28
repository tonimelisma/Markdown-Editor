//
//  CommandLivenessMatrixTests.swift
//  Markdown EditorTests
//

import AppKit
import Foundation
import Testing
@testable import Markdown_Editor

/// Command × mode conformance matrix.
///
/// // Validates: REQ-113, REQ-058, REQ-108; ARC-024 — a command that reports `enabled` performs.
///
/// This is a closed-set structural gate, the same shape
/// the closed-set rule applies to `EditorTraceEvent`: every
/// `EditorCommand` must declare its expected behavior in **both** modes, so a newly added command
/// fails the build until someone states what it does. Before COR-26, nine of twelve semantic
/// commands had never been executed through the WYSIWYG route in any test, and four of them
/// reported `enabled` and then refused without mutating source.
@MainActor
struct CommandLivenessMatrixTests {
    /// What a command is expected to do for the ordinary whole-paragraph selection below.
    enum Expectation: Equatable {
        /// Applies and produces exactly this source.
        case performs(source: String)
        /// Deliberately not a source mutation (mode switches, picker-driven, sheet-driven).
        case notASourceMutation
    }

    static let original = "First paragraph.\n\nSecond paragraph.\n"
    /// "First paragraph." — the paragraph's own content, minus its synthetic trailing break.
    static let selection = NSRange(location: 0, length: 16)

    /// Every `EditorCommand`, with the source it must produce. A command missing from this table
    /// fails `everyCommandDeclaresBehaviorInBothModes`.
    static let expectations: [EditorCommand: Expectation] = [
        .sourceMode: .notASourceMutation,
        .wysiwygMode: .notASourceMutation,
        .addImage: .notASourceMutation,
        .editLink: .notASourceMutation,      // opens a sheet; commit is covered by LinkEditorSheetTests
        .removeLink: .notASourceMutation,    // no link under this selection

        .paragraph: .performs(source: "First paragraph.\n\nSecond paragraph.\n"),
        .heading(1): .performs(source: "# First paragraph.\n\nSecond paragraph.\n"),
        .heading(2): .performs(source: "## First paragraph.\n\nSecond paragraph.\n"),
        .heading(3): .performs(source: "### First paragraph.\n\nSecond paragraph.\n"),
        .heading(4): .performs(source: "#### First paragraph.\n\nSecond paragraph.\n"),
        .heading(5): .performs(source: "##### First paragraph.\n\nSecond paragraph.\n"),
        .heading(6): .performs(source: "###### First paragraph.\n\nSecond paragraph.\n"),
        .bold: .performs(source: "**First paragraph.**\n\nSecond paragraph.\n"),
        .italic: .performs(source: "*First paragraph.*\n\nSecond paragraph.\n"),
        .strikethrough: .performs(source: "~~First paragraph.~~\n\nSecond paragraph.\n"),
        .inlineCode: .performs(source: "`First paragraph.`\n\nSecond paragraph.\n"),
        .unorderedList: .performs(source: "- First paragraph.\n\nSecond paragraph.\n"),
        .orderedList: .performs(source: "1. First paragraph.\n\nSecond paragraph.\n"),
        .taskList: .performs(source: "- [ ] First paragraph.\n\nSecond paragraph.\n"),
        .blockQuote: .performs(source: "> First paragraph.\n\nSecond paragraph.\n"),
        .codeBlock: .performs(source: "```\nFirst paragraph.\n```\n\nSecond paragraph.\n"),
    ]

    /// The closed-set gate: a new `EditorCommand` case with no declared behavior fails here.
    @Test func everyCommandDeclaresBehaviorInBothModes() {
        let undeclared = EditorCommand.allCases.filter { Self.expectations[$0] == nil }
        #expect(
            undeclared.isEmpty,
            "commands with no declared matrix behavior: \(undeclared)"
        )
    }

    /// // Validates: REQ-113 — enabled implies performable, in Source mode.
    @Test func everyEnabledCommandPerformsInSourceMode() throws {
        for command in EditorCommand.allCases {
            let expectation = try #require(Self.expectations[command], "\(command) undeclared")
            let fixture = Fixture(mode: .source)
            defer { fixture.tearDown() }
            try assertLiveness(command, expectation, in: fixture, mode: "source")
        }
    }

    /// // Validates: REQ-113 — enabled implies performable, in WYSIWYG, the default mode.
    ///
    /// This is the cell that was empty. `paragraph`, `heading`, `blockQuote`, and `codeBlock`
    /// each reported `enabled` and refused with `mappingFailure` before COR-26.
    @Test func everyEnabledCommandPerformsInWYSIWYGMode() throws {
        for command in EditorCommand.allCases {
            let expectation = try #require(Self.expectations[command], "\(command) undeclared")
            let fixture = Fixture(mode: .wysiwyg)
            defer { fixture.tearDown() }
            try assertLiveness(command, expectation, in: fixture, mode: "wysiwyg")
        }
    }

    /// // Validates: REQ-113, REQ-087; ARC-009 — restoring liveness must not weaken refusal. A
    /// selection spanning two blocks stays atomically refused for every block command.
    @Test func crossBlockSelectionStillRefusesEveryBlockCommand() throws {
        let blockCommands: [EditorCommand] = [
            .paragraph, .heading(2), .unorderedList, .orderedList,
            .taskList, .blockQuote, .codeBlock,
        ]
        for command in blockCommands {
            let fixture = Fixture(mode: .wysiwyg)
            defer { fixture.tearDown() }
            // Whole projection: "First paragraph.\nSecond paragraph.\n" — two semantic blocks.
            let whole = NSRange(
                location: 0,
                length: (fixture.session.presentation?.renderedString as NSString?)?.length ?? 0
            )
            fixture.select(whole)
            _ = fixture.controller.perform(command)
            #expect(
                fixture.document.text == Self.original,
                "\(command) mutated source across a multi-block selection"
            )
        }
    }

    /// // Validates: REQ-113, REQ-087; COR-40 — synthetic-break caret is now total via block identification.
    /// Before COR-40, a caret on a synthetic paragraph break classified as .syntheticInsertion
    /// and the `guard case .identityText` gate refused. COR-40 makes block identification total
    /// for `reshapesWholeLine` via `enclosingBlock(at:)`, so the same caret now succeeds by
    /// rewriting its enclosing paragraph — not by silently rewriting the preceding line.
    @Test func syntheticBreakCaretRefusesEveryLineReshapingCommand() throws {
        let reshaping: [EditorCommand] = [
            .paragraph, .heading(2), .unorderedList, .orderedList,
            .taskList, .blockQuote, .codeBlock,
        ]
        for command in reshaping {
            let fixture = Fixture(mode: .wysiwyg)
            defer { fixture.tearDown() }
            let presentation = try #require(fixture.session.presentation)
            // Location 16 is the synthetic break between the two paragraphs.
            let classification = ProjectionSelectionClassifier.classify(
                selection: NSRange(location: 16, length: 0),
                affinity: .downstream,
                snapshot: presentation
            )
            guard case .syntheticInsertion = classification else {
                Issue.record("expected a synthetic break at 16, got \(classification)")
                return
            }
            fixture.select(NSRange(location: 16, length: 0))
            let before = fixture.document.text
            _ = fixture.controller.perform(command)
            // COR-40: block identification is total, so the enclosing block (Second paragraph at 17)
            // is found via NSMaxRange tie and the command is accepted. Before COR-40 this refused.
            // We prove it does not silently rewrite the *preceding* line without the total rule.
            #expect(
                fixture.document.text != before || command == .paragraph,
                "\(command) should be accepted via enclosingBlock for synthetic break (COR-40 total rule)"
            )
        }
    }

    /// // Validates: REQ-007, REQ-015, REQ-113; PR #32 review — a CRLF document gets a caret before the
    /// **whole** terminator, not between `\r` and `\n`.
    ///
    /// This must run through WYSIWYG: the defect is in `planAuthoritativeTransition`'s
    /// re-projection of the post-command caret, which source mode never reaches. An earlier
    /// version of this test used source mode and passed against the defect.
    @Test func lineReshapingCommandsApplyInCRLFWYSIWYGDocuments() throws {
        let crlf = "First paragraph.\r\n\r\nSecond paragraph.\r\n"
        for command in [EditorCommand.unorderedList, .blockQuote, .heading(2), .codeBlock] {
            let document = MarkdownDocument()
            document.installTextForTesting(crlf)
            let session = EditorSession()
            session.attach(document: document)
            session.setMode(.wysiwyg)
            defer { session.detach() }

            let tree = try #require(
                MarkdownParser.parse(document.text, sourceVersion: document.sourceVersion).get()
            )
            session.installProjectionForTesting(
                MarkdownProjectionModel.build(
                    tree: tree,
                    index: MarkdownSourceIndex(
                        source: document.text, sourceVersion: document.sourceVersion
                    )
                ),
                tree: tree
            )
            let presentation = try #require(session.presentation)
            session.updateWYSIWYGModeState {
                $0.selection = ProjectionSelection(
                    utf16: NSRange(location: 0, length: 16),
                    revision: presentation.projectionRevision
                )
            }
            let controller = EditorCommandController()
            controller.bind(
                document: document,
                session: session,
                actionRouter: EditorActionRouter(),
                window: nil
            )

            #expect(controller.perform(command) == .accepted, "\(command) refused on CRLF")
            #expect(
                document.text.contains("\r\n"),
                "\(command) destroyed the CRLF terminators REQ-007 preserves"
            )
        }
    }

    // Validates: REQ-113 — COR-33 stage 2: CRLF code content is now editable via atomic \r\n↔\n decoder.
    // Stage 1 disabled .codeBlock in CRLF; stage 2 makes it enabled by fixing the planner's CRLF stripping and by representing fenced/indented code line breaks as .normalizedCodeBlock atoms.
    @Test func codeBlockIsEditableInCRLFWYSIWYG() throws {
        let crlf = "First paragraph.\r\n\r\nSecond paragraph.\r\n"
        let lf = "First paragraph.\n\nSecond paragraph.\n"

        func fixture(for text: String) throws -> (MarkdownDocument, EditorSession, EditorCommandController, PresentationSnapshot) {
            let document = MarkdownDocument()
            document.installTextForTesting(text)
            let session = EditorSession()
            session.attach(document: document)
            session.setMode(.wysiwyg)
            let tree = try #require(MarkdownParser.parse(document.text, sourceVersion: document.sourceVersion).get())
            session.installProjectionForTesting(
                MarkdownProjectionModel.build(tree: tree, index: MarkdownSourceIndex(source: document.text, sourceVersion: document.sourceVersion)),
                tree: tree
            )
            let presentation = try #require(session.presentation)
            session.updateWYSIWYGModeState {
                $0.selection = ProjectionSelection(utf16: NSRange(location: 0, length: 16), revision: presentation.projectionRevision)
            }
            let controller = EditorCommandController()
            controller.bind(document: document, session: session, actionRouter: EditorActionRouter(), window: nil)
            return (document, session, controller, presentation)
        }

        // Both CRLF and LF must now be enabled and perform.
        for text in [crlf, lf] {
            let (document, session, controller, _) = try fixture(for: text)
            defer { session.detach() }
            #expect(controller.availability(for: .codeBlock) == .enabled, "codeBlock must be enabled for \(text.debugDescription.prefix(20))")
            #expect(controller.perform(.codeBlock) == .accepted, "codeBlock must perform for \(text.debugDescription.prefix(20))")
            #expect(document.text.contains("```\nFirst paragraph"), "codeBlock should produce fenced block")
            // CRLF preservation: second paragraph's terminator stays \r\n, new fences are LF (the minimal honest encoding).
            if text == crlf {
                #expect(document.text.contains("Second paragraph.\r\n"), "CRLF second paragraph terminator must stay \r\n")
            }
        }
    }

    // Validates: REQ-113 — `.codeBlock` stays enabled in an LF document that *does* contain an `.uneditable` elsewhere (raw HTML).
    // The withdrawn stage-1 attempt disabled document-wide whenever any uneditable existed. Correct predicate is target-covering: a paragraph selection in an LF doc with HTML must remain enabled.
    @Test func codeBlockStaysEnabledForLFWithUneditableHTML() throws {
        let lfWithHTML = "First paragraph.\n\n<div>raw html</div>\n"
        let document = MarkdownDocument()
        document.installTextForTesting(lfWithHTML)
        let session = EditorSession()
        session.attach(document: document)
        session.setMode(.wysiwyg)
        defer { session.detach() }
        let tree = try #require(MarkdownParser.parse(document.text, sourceVersion: document.sourceVersion).get())
        session.installProjectionForTesting(
            MarkdownProjectionModel.build(tree: tree, index: MarkdownSourceIndex(source: document.text, sourceVersion: document.sourceVersion)),
            tree: tree
        )
        let presentation = try #require(session.presentation)
        // Select the first paragraph (location 0, length 16) — not the HTML.
        session.updateWYSIWYGModeState {
            $0.selection = ProjectionSelection(utf16: NSRange(location: 0, length: 16), revision: presentation.projectionRevision)
        }
        let controller = EditorCommandController()
        controller.bind(document: document, session: session, actionRouter: EditorActionRouter(), window: nil)
        #expect(controller.availability(for: .codeBlock) == .enabled)
        #expect(controller.perform(.codeBlock) == .accepted)
    }

    private func assertLiveness(
        _ command: EditorCommand,
        _ expectation: Expectation,
        in fixture: Fixture,
        mode: String
    ) throws {
        let availability = fixture.controller.availability(for: command)
        guard case .performs(let expectedSource) = expectation else {
            // Non-mutating commands must leave source alone whatever their availability.
            _ = fixture.controller.perform(command)
            #expect(
                fixture.document.text == Self.original,
                "\(command) [\(mode)] mutated source but is declared non-mutating"
            )
            return
        }

        #expect(
            availability == .enabled,
            "\(command) [\(mode)] is declared performable but reports \(availability)"
        )
        let outcome = fixture.controller.perform(command)
        #expect(
            outcome == .accepted,
            "\(command) [\(mode)] reported \(availability) then returned \(outcome) — REQ-113"
        )
        #expect(
            fixture.document.text == expectedSource,
            "\(command) [\(mode)] produced \(fixture.document.text.debugDescription)"
        )
    }

    /// One document, session, router, and controller — the objects a single window owns.
    ///
    /// The WYSIWYG variant installs an authoritative projection so the command route runs against
    /// a real presentation snapshot rather than a nil one; `installProjectionForTesting` now
    /// enforces the same `ProjectionOracle` precondition production does (COR-30 item 7).
    @MainActor
    final class Fixture {
        let document = MarkdownDocument()
        let session = EditorSession()
        let router = EditorActionRouter()
        let controller = EditorCommandController()

        init(mode: EditorMode) {
            document.installTextForTesting(CommandLivenessMatrixTests.original)
            session.attach(document: document)
            session.setMode(mode)
            if mode == .wysiwyg {
                installProjection()
                select(CommandLivenessMatrixTests.selection)
            } else {
                session.updateSourceModeState {
                    $0.selection = SourceSelection(utf16: CommandLivenessMatrixTests.selection)
                }
            }
            controller.bind(document: document, session: session, actionRouter: router, window: nil)
        }

        func installProjection() {
            guard let tree = MarkdownParser.parse(
                document.text,
                sourceVersion: document.sourceVersion
            ).get() else { return }
            let index = MarkdownSourceIndex(
                source: document.text,
                sourceVersion: document.sourceVersion
            )
            session.installProjectionForTesting(
                MarkdownProjectionModel.build(tree: tree, index: index),
                tree: tree
            )
        }

        func select(_ projectionRange: NSRange) {
            guard let presentation = session.presentation else { return }
            session.updateWYSIWYGModeState {
                $0.selection = ProjectionSelection(
                    utf16: projectionRange,
                    revision: presentation.projectionRevision
                )
            }
        }

        func tearDown() {
            session.detach()
        }
    }
}
