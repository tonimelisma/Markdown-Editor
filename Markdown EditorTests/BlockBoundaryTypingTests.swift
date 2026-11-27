//
//  BlockBoundaryTypingTests.swift
//  Markdown EditorTests
//
//  Typing a note in WYSIWYG from the keyboard, as the agent-drive tour does: words with spaces,
//  Return between paragraphs and list items, Backspace over the boundaries Return made. Each
//  keystroke goes through the real native delegate callback with the replacement AppKit sends:
//  Return is "\n" over the caret, Delete is "" over the character before it.
//
//  Agent-drive tour 45957180019 typed "Weekly notes", Return, a sentence, into a new window. The
//  space at the end of each word was refused as unprovable, Return as a mapping failure, and the
//  note read "WeeklynotesToday…" on one line.
//

import AppKit
import Foundation
import Testing
@testable import Markdown_Editor

@MainActor
@Suite(.serialized)
struct BlockBoundaryTypingTests {

    /// A person at the keyboard: each keystroke acts at the caret the last one left, as AppKit's
    /// does, never at a position the test computes.
    @MainActor
    final class Typist {
        let trace = InMemoryEditorTrace()
        let harness: PerformanceBoundaryTests.EditorHarness
        /// Whether each keystroke's parse lands before the next, or the keystrokes outrun them.
        let waitsForEachParse: Bool

        init(_ source: String, waitsForEachParse: Bool = false) async throws {
            harness = try PerformanceBoundaryTests.EditorHarness(source: source, trace: trace)
            self.waitsForEachParse = waitsForEachParse
            await harness.settle()
            harness.coordinator.applyProjectionIfNeeded(reason: .newSnapshot)
        }

        var text: String { harness.document.text }
        var rendered: NSString { (harness.session.presentation?.renderedString ?? "") as NSString }
        var caret: NSRange? { harness.session.wysiwygModeState.selection?.range.utf16 }

        /// Puts the caret after the first occurrence of `text` on the page, or at its start.
        func click(after text: String? = nil) throws {
            let location: Int
            if let text {
                let found = rendered.range(of: text)
                try #require(found.location != NSNotFound, "\(text.debugDescription) is not on the page \(rendered.debugDescription)")
                location = NSMaxRange(found)
            } else {
                location = 0
            }
            harness.captureNativeSelection(at: NSRange(location: location, length: 0))
        }

        func click(before text: String) throws {
            let found = rendered.range(of: text)
            try #require(found.location != NSNotFound, "\(text.debugDescription) is not on the page \(rendered.debugDescription)")
            harness.captureNativeSelection(at: NSRange(location: found.location, length: 0))
        }

        func type(_ text: String) async {
            for character in text { await send(String(character), over: caret) }
        }

        func pressReturn() async { await send("\n", over: caret) }

        /// A Format menu command, at the caret, as its shortcut sends it.
        @discardableResult
        func perform(_ command: EditorCommand) async -> EditorCommandResult {
            let result = commands.perform(command)
            if waitsForEachParse { await settle() }
            return result
        }

        private lazy var commands = harness.makeCommandController()

        func pressDelete() async {
            guard let caret, caret.length == 0, caret.location > 0 else {
                await send("", over: caret)
                return
            }
            await send("", over: rendered.rangeOfComposedCharacterSequence(at: caret.location - 1))
        }

        private func send(_ replacement: String, over range: NSRange?) async {
            guard let range else { return }
            harness.session.updateOrigin.with(.nativeUserInput) {
                _ = harness.coordinator.textView(
                    harness.textView,
                    shouldChangeTextIn: range,
                    replacementString: replacement
                )
            }
            if waitsForEachParse { await settle() }
        }

        /// What each recovered keystroke's provisional snapshot disagreed with the parse on.
        private(set) var disagreements: [String] = []

        /// Waits until the current revision's parse has landed and is on the page.
        func settle() async {
            let revision = harness.document.sourceVersion
            let provisional = harness.session.presentation
            let recovered = recoveries.count
            for _ in 0..<2_000 where !reconciled(revision) {
                await Task.yield()
                try? await Task.sleep(for: .milliseconds(5))
            }
            if recoveries.count > recovered, let provisional, let authoritative = harness.session.presentation {
                disagreements.append("revision \(revision): " + PresentationRecoveryTests.differences(provisional, authoritative).joined(separator: "; "))
            }
            harness.coordinator.applyProjectionIfNeeded(reason: .newSnapshot)
        }

        private func reconciled(_ revision: UInt64) -> Bool {
            !trace.eventsMatching {
                if case .reconciliationApplied(_, let applied, _, _) = $0 { return applied == revision }
                return false
            }.isEmpty
        }

        var refusals: [EditorTraceEvent] {
            trace.eventsMatching {
                if case .editRefused = $0 { return true }
                return false
            }
        }

        var recoveries: [EditorTraceEvent] {
            trace.eventsMatching {
                if case .presentationRecovered = $0 { return true }
                return false
            }
        }

        /// The verdict on a finished passage: what the file says, and that nothing was refused
        /// or recovered on the way.
        func expect(_ source: String, sourceLocation: SourceLocation = #_sourceLocation) async {
            await settle()
            #expect(text == source, "the document reads \(text.debugDescription)", sourceLocation: sourceLocation)
            #expect(refusals.isEmpty, "keystrokes were refused: \(refusals)", sourceLocation: sourceLocation)
            #expect(recoveries.isEmpty, "keystrokes were recovered: \(recoveries); \(disagreements)", sourceLocation: sourceLocation)
        }
    }

    // MARK: - Spaces and Return

    // Verifies: REQ-152 — a space typed at the end of a line is kept, where the next word follows it.
    @Test(arguments: [false, true])
    func aSpaceAtTheEndOfALineIsKept(waitingForEachParse: Bool) async throws {
        let typist = try await Typist("Hello", waitsForEachParse: waitingForEachParse)
        try typist.click(after: "Hello")
        await typist.type(" brave new world")
        await typist.expect("Hello brave new world")
    }

    // Verifies: REQ-152 — Return in a new document starts a new paragraph, and the text typed
    // after it is that paragraph's.
    @Test(arguments: [false, true])
    func returnStartsANewParagraphInANewDocument(waitingForEachParse: Bool) async throws {
        let typist = try await Typist("", waitsForEachParse: waitingForEachParse)
        try typist.click()
        await typist.type("Weekly notes")
        await typist.pressReturn()
        await typist.type("Today I fixed the printer.")
        await typist.expect("Weekly notes\n\nToday I fixed the printer.")
    }

    // Verifies: REQ-152 — Return twice leaves an empty paragraph, which shows as an empty line
    // and takes the text typed into it.
    @Test func returnTwiceLeavesAnEmptyParagraphThatTakesText() async throws {
        let typist = try await Typist("One")
        try typist.click(after: "One")
        await typist.pressReturn()
        await typist.pressReturn()
        await typist.type("Three")
        await typist.expect("One\n\n\n\nThree")
        // One, an empty paragraph, Three: three lines on the page.
        #expect(typist.rendered.components(separatedBy: "\n").filter { !$0.isEmpty } == ["One", "Three"])
        #expect(typist.rendered.hasPrefix("One\n\nThree"), "the page reads \(typist.rendered.debugDescription)")
    }

    // Verifies: REQ-152 — Return after a heading starts a paragraph below it, not a second heading line.
    @Test func returnAfterAHeadingStartsAParagraph() async throws {
        let typist = try await Typist("# Weekly notes")
        try typist.click(after: "Weekly notes")
        await typist.pressReturn()
        await typist.type("Body")
        await typist.expect("# Weekly notes\n\nBody")
    }

    // Verifies: REQ-152 — a key pressed right after a formatting command, before the page shows
    // the command's result, is typed, not lost. The tour typed "Weekly notes", ⌘1 and Return, and
    // Return was refused as stale because SwiftUI had not yet applied Heading 1 to the page.
    @Test func aKeyPressedRightAfterACommandIsTyped() async throws {
        let typist = try await Typist("")
        try typist.click()
        await typist.type("Weekly notes")
        let heading = await typist.perform(.heading(1))
        #expect(heading == .accepted, "Heading 1 was \(heading)")
        // No view update between the command and the key, as when the key comes first.
        await typist.pressReturn()
        await typist.type("Body")
        await typist.expect("# Weekly notes\n\nBody")
    }

    // Verifies: REQ-152 — Return before a paragraph's text opens an empty paragraph above it,
    // and the caret stays with the paragraph, as in TextEdit.
    @Test func returnBeforeAParagraphOpensOneAboveIt() async throws {
        let typist = try await Typist("# Title\n\nBody")
        try typist.click(before: "Body")
        await typist.pressReturn()
        await typist.type("The ")
        await typist.expect("# Title\n\n\n\nThe Body")
        #expect(typist.rendered.hasPrefix("Title\n\nThe Body"), "the page reads \(typist.rendered.debugDescription)")
    }

    // Verifies: REQ-152 — Return in a list starts the next item; Return in the empty item ends
    // the list, as in Notes and TextEdit.
    @Test(arguments: [false, true])
    func returnContinuesAListAndAnEmptyItemEndsIt(waitingForEachParse: Bool) async throws {
        let typist = try await Typist("- Milk", waitsForEachParse: waitingForEachParse)
        try typist.click(after: "Milk")
        await typist.pressReturn()
        await typist.type("Eggs")
        await typist.pressReturn()
        await typist.type("Bread")
        await typist.pressReturn()
        await typist.pressReturn()
        await typist.type("Call the plumber")
        await typist.expect("- Milk\n- Eggs\n- Bread\n\nCall the plumber")
    }

    // Verifies: REQ-152 — in a loose list, Return starts the next item after a blank line, and
    // Return in the empty item ends the list. Tour 45965585963 typed a task after a list and a
    // blank line, which joined it to the list and made it loose; the second Return left the
    // blank line behind, and the paragraph typed next went into the task.
    @Test func returnContinuesAndEndsALooseList() async throws {
        let typist = try await Typist("- Milk\n\n- [ ] Call the plumber")
        try typist.click(after: "Call the plumber")
        await typist.pressReturn()
        await typist.type("Pay")
        await typist.pressReturn()
        await typist.pressReturn()
        await typist.type("Simplicity.")
        await typist.expect("- Milk\n\n- [ ] Call the plumber\n\n- [ ] Pay\n\nSimplicity.")
    }

    // Verifies: REQ-152 — the next item of a numbered list is numbered one higher, and the next
    // item of a task list is an unchecked task.
    @Test func returnContinuesNumberedAndTaskLists() async throws {
        let numbered = try await Typist("1. One")
        try numbered.click(after: "One")
        await numbered.pressReturn()
        await numbered.type("Two")
        await numbered.expect("1. One\n2. Two")

        let tasks = try await Typist("- [x] Done")
        try tasks.click(after: "Done")
        await tasks.pressReturn()
        await tasks.type("Next")
        await tasks.expect("- [x] Done\n- [ ] Next")
    }

    // Verifies: REQ-152 — Return in a quote ends it: the new paragraph follows the quote.
    @Test func returnInAQuoteEndsIt() async throws {
        let typist = try await Typist("> Simplicity is prerequisite for reliability.")
        try typist.click(after: "reliability.")
        await typist.pressReturn()
        await typist.type("After")
        await typist.expect("> Simplicity is prerequisite for reliability.\n\nAfter")
    }

    // Verifies: REQ-152 — Return in a code block is a line of code.
    @Test func returnInACodeBlockIsALineOfCode() async throws {
        let typist = try await Typist("```\nlet a = 1\n```\n")
        try typist.click(after: "let a = 1")
        await typist.pressReturn()
        await typist.type("b")
        await typist.expect("```\nlet a = 1\nb\n```\n")
    }

    // MARK: - Backspace

    // Verifies: REQ-153 — Delete inside a word deletes the character before the caret. AppKit
    // names that character, not the caret, and the mismatch refused every Backspace.
    @Test func deleteRemovesTheCharacterBeforeTheCaret() async throws {
        let typist = try await Typist("Hello world.")
        try typist.click(after: "Hello")
        await typist.pressDelete()
        await typist.pressDelete()
        await typist.expect("Hel world.")
    }

    // Verifies: REQ-153 — Delete undoes Return: the empty paragraph goes, then the paragraph
    // joins the one before it.
    @Test(arguments: [false, true])
    func deleteUndoesReturn(waitingForEachParse: Bool) async throws {
        let typist = try await Typist("Hello", waitsForEachParse: waitingForEachParse)
        try typist.click(after: "Hello")
        await typist.pressReturn()
        await typist.pressReturn()
        await typist.pressDelete()
        await typist.expect("Hello\n\n")
        await typist.pressDelete()
        await typist.type(" again")
        await typist.expect("Hello again")
    }

    // Verifies: REQ-153 — Delete at the start of a paragraph joins it to the one before.
    @Test func deleteAtAParagraphsStartJoinsItToThePreviousOne() async throws {
        let typist = try await Typist("# Title\n\nFirst.\n\nSecond.\n")
        try typist.click(before: "Second.")
        await typist.pressDelete()
        await typist.expect("# Title\n\nFirst.Second.\n")
    }

    // Verifies: REQ-153 — Delete at the start of a heading's text makes it a paragraph.
    @Test func deleteAtAHeadingsStartMakesItAParagraph() async throws {
        let typist = try await Typist("Intro\n\n## Title\n")
        try typist.click(before: "Title")
        await typist.pressDelete()
        await typist.expect("Intro\n\nTitle\n")
    }

    // Verifies: REQ-153 — Delete at the start of a list item's text takes its marker away, and
    // the text becomes a paragraph after the list.
    @Test func deleteAtAListItemsStartTakesItsMarkerAway() async throws {
        let typist = try await Typist("- Milk\n- Eggs\n")
        try typist.click(before: "Eggs")
        await typist.pressDelete()
        await typist.expect("- Milk\n\nEggs\n")
    }

    // Verifies: REQ-152 — the whole tour passage, as one person types it: a heading, a
    // paragraph, a list that ends, and a corrected typo.
    @Test(arguments: [false, true])
    func theTourNoteTypesAsWritten(waitingForEachParse: Bool) async throws {
        let typist = try await Typist("", waitsForEachParse: waitingForEachParse)
        try typist.click()
        await typist.type("Weekly notes")
        await typist.pressReturn()
        await typist.type("Today I fixed the printerr")
        await typist.pressDelete()
        await typist.type(".")
        await typist.pressReturn()
        await typist.type("Milk")
        let list = await typist.perform(.unorderedList)
        #expect(list == .accepted, "Bulleted List was \(list)")
        await typist.pressReturn()
        await typist.type("Eggs")
        await typist.pressReturn()
        await typist.pressReturn()
        await typist.type("Done.")
        await typist.expect("Weekly notes\n\nToday I fixed the printer.\n\n- Milk\n- Eggs\n\nDone.")
    }

    // MARK: - Layout

    // Verifies: REQ-152 — the empty paragraphs the page shows are the ones the source holds:
    // none for one blank line, one for each further pair, before, between and after blocks.
    @Test func emptyParagraphsAreCountedFromTheSourcesBlankLines() {
        func count(_ source: String) -> Int {
            let ns = source as NSString
            guard let tree = try? MarkdownParser.parse(source, sourceVersion: 1).get() else { return -1 }
            let index = MarkdownSourceIndex(source: source, sourceVersion: 1)
            let blocks = tree.root.children.compactMap { try? index.utf16Range(for: $0.position).get() }
            return EmptyParagraphLayout.documentSlots(in: ns, blocks: blocks).count
        }
        #expect(count("") == 0)
        #expect(count("\n\n") == 1)
        #expect(count("A\n\nB") == 0)
        #expect(count("A\n\nB\n") == 0)
        #expect(count("A\n\n\n\nB") == 1)
        #expect(count("A\n\n\n\n\n\nB") == 2)
        #expect(count("\n\nA") == 1)
        #expect(count("A\n\n") == 1)
        #expect(count("A\n\n\n") == 1)
        #expect(count("- a\n- b\n\n\n\nC\n") == 1)
    }
}
