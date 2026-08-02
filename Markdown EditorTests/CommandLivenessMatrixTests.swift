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
/// // Verifies: REQ-113/058/108; ARC-024 — a command that reports `enabled` performs.
///
/// This is a closed-set structural gate, the same shape
/// `Scripts/check-instrumentation-coverage.sh` applies to `EditorTraceEvent`: every
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

    /// // Verifies: REQ-113 — enabled implies performable, in Source mode.
    @Test func everyEnabledCommandPerformsInSourceMode() throws {
        for command in EditorCommand.allCases {
            let expectation = try #require(Self.expectations[command], "\(command) undeclared")
            let fixture = Fixture(mode: .source)
            defer { fixture.tearDown() }
            try assertLiveness(command, expectation, in: fixture, mode: "source")
        }
    }

    /// // Verifies: REQ-113 — enabled implies performable, in WYSIWYG, the default mode.
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

    /// // Verifies: REQ-113/087; ARC-009 — restoring liveness must not weaken refusal. A
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

    /// // Verifies: REQ-113/087; ARC-009; PR #32 review — a caret on a synthetic paragraph break
    /// is not an identity paragraph, so a line-reshaping command refuses instead of silently
    /// rewriting the preceding line.
    ///
    /// Before this, the mutation *was* planned and only rescued by an unmappable post-edit
    /// selection. COR-25/COR-26 gave every planner a projectable caret, which removed that
    /// accident — so the refusal now has to be stated rather than emerge from a mapping failure.
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
            _ = fixture.controller.perform(command)
            #expect(
                fixture.document.text == Self.original,
                "\(command) rewrote source from a synthetic-break caret"
            )
        }
    }

    /// // Verifies: REQ-007/015/113; PR #32 review — a CRLF document gets a caret before the
    /// **whole** terminator, not between `\r` and `\n`.
    ///
    /// This must run through WYSIWYG: the defect is in `planAuthoritativeTransition`'s
    /// re-projection of the post-command caret, which source mode never reaches. An earlier
    /// version of this test used source mode and passed against the defect.
    @Test func lineReshapingCommandsApplyInCRLFWYSIWYGDocuments() throws {
        let crlf = "First paragraph.\r\n\r\nSecond paragraph.\r\n"
        // `.codeBlock` is deliberately excluded and tracked as COR-33: cmark normalises CRLF to
        // LF, so fenced content is not an identity mapping in a CRLF document. That is a
        // projection defect, not a caret one, and this fix does not claim it.
        for command in [EditorCommand.unorderedList, .blockQuote, .heading(2)] {
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
