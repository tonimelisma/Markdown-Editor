//
//  NativeSourceContractTests.swift
//  Markdown EditorTests
//

import AppKit
import Foundation
import Testing
@testable import Markdown_Editor

@MainActor
struct NativeSourceContractTests {
    // Validates: REQ-010, REQ-011 — native NSTextView replacement uses the production coordinator,
    // advances the document once, preserves Unicode UTF-16 ranges, and registers document-owned
    // undo/redo for source and selection.
    @Test func nativeReplacementPreservesUnicodeAndDocumentUndoRoute() throws {
        let fixture = try makeFixture(source: "a🐙b")
        let emojiRange = NSRange(location: 1, length: 2)
        fixture.session.updateSourceModeState { $0.selection = SourceSelection(utf16: emojiRange) }
        fixture.textView.setSelectedRange(emojiRange)
        let beforeRevision = fixture.document.sourceVersion

        #expect(fixture.coordinator.textView(
            fixture.textView,
            shouldChangeTextIn: emojiRange,
            replacementString: "é"
        ))
        fixture.storage.replaceCharacters(in: emojiRange, with: "é")
        let afterRange = NSRange(location: 2, length: 0)
        fixture.textView.setSelectedRange(afterRange)
        fixture.coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: fixture.textView))

        #expect(fixture.document.text == "aéb")
        #expect(fixture.storage.string == "aéb")
        #expect(fixture.document.sourceVersion == beforeRevision + 1)
        #expect(fixture.session.sourceModeState.selection.range.utf16 == afterRange)
        #expect(fixture.document.undoManager?.canUndo == true)

        fixture.document.undoManager?.undo()
        #expect(fixture.document.text == "a🐙b")
        #expect(fixture.session.sourceModeState.selection.range.utf16 == emojiRange)
        fixture.document.undoManager?.redo()
        #expect(fixture.document.text == "aéb")
        #expect(fixture.session.sourceModeState.selection.range.utf16 == afterRange)
    }

    // Validates: REQ-010 — native paste chooses plain text and routes the discrete edit through the
    // same coordinator/document owner as typing.
    @Test func nativePasteUsesPlainTextAndDiscreteUndo() throws {
        let fixture = try makeFixture(source: "prefix")
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        defer { pasteboard.clearContents() }
        let rich = try NSAttributedString(
            string: "RICH",
            attributes: [.foregroundColor: NSColor.systemRed]
        ).data(
            from: NSRange(location: 0, length: 4),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
        #expect(pasteboard.setData(rich, forType: .rtf))
        #expect(pasteboard.setString("é 🐙\n", forType: .string))
        let insertion = NSRange(location: (fixture.textView.string as NSString).length, length: 0)
        fixture.session.updateSourceModeState { $0.selection = SourceSelection(utf16: insertion) }
        fixture.textView.setSelectedRange(insertion)

        fixture.textView.paste(nil)

        #expect(fixture.document.text == "prefixé 🐙\n")
        #expect(fixture.document.undoManager?.canUndo == true)
        fixture.document.undoManager?.undo()
        #expect(fixture.document.text == "prefix")
    }

    // Validates: REQ-012, REQ-046 — production source configuration opts into AppKit spell checking
    // and standard find-bar/incremental-search routing without an app-owned substitute.
    @Test func productionSourceEditorUsesNativeSpellAndFindServices() throws {
        let document = MarkdownDocument()
        document.installTextForTesting("needle needle")
        let session = EditorSession()
        session.attach(document: document)
        let placement = ImagePlacementController()
        let router = EditorActionRouter()
        let host = EditorHostView.HostCoordinator(
            document: document,
            session: session,
            placementController: placement,
            actionRouter: router
        )
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 480))
        host.buildEditors(in: root)
        let source = try #require(host.sourceText)

        #expect(source.isRichText == false)
        #expect(source.isContinuousSpellCheckingEnabled == true)
        #expect(source.usesFindBar == true)
        #expect(source.isIncrementalSearchingEnabled == true)
        #expect(source.responds(to: #selector(NSTextView.performFindPanelAction(_:))))

        let findPasteboard = NSPasteboard(name: .find)
        findPasteboard.clearContents()
        defer { findPasteboard.clearContents() }
        #expect(findPasteboard.setString("needle", forType: .string))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [],
            backing: .buffered,
            defer: false
        )
        window.contentView = root
        defer { window.orderOut(nil) }
        #expect(window.makeFirstResponder(source))
        source.setSelectedRange(NSRange(location: 0, length: 0))
        let findNext = NSMenuItem()
        findNext.tag = 2 // NSFindPanelActionNext
        source.setSelectedRange(NSRange(location: 0, length: 6))
        let setSearchString = NSMenuItem()
        setSearchString.tag = 7 // NSTextFinderActionSetSearchString
        source.performTextFinderAction(setSearchString)
        source.setSelectedRange(NSRange(location: 0, length: 0))
        source.performFindPanelAction(findNext)
        #expect(source.selectedRange() == NSRange(location: 0, length: 6))

        // The production view delegates Find to AppKit. Exercise the framework's finder client
        // directly as the headless component proof; a hidden window cannot provide the find-bar
        // geometry that NSTextView uses to paint its selection feedback.
        let finderClient = FinderClient(string: "needle needle")
        let finder = NSTextFinder()
        finder.client = finderClient
        finderClient.selectedRanges = [NSValue(range: NSRange(location: 0, length: 6))]
        finder.performAction(.setSearchString)
        finderClient.selectedRanges = [NSValue(range: NSRange(location: 0, length: 0))]
        finder.performAction(.nextMatch)
        #expect(finderClient.firstSelectedRange == NSRange(location: 0, length: 6))

        let replacementRange = NSRange(location: 0, length: 6)
        session.updateSourceModeState { $0.selection = SourceSelection(utf16: replacementRange) }
        source.setSelectedRange(replacementRange)
        let beforeRevision = document.sourceVersion
        #expect(source.performValidatedReplacement(
            in: source.selectedRange(),
            with: NSAttributedString(string: "found")
        ))
        #expect(document.text == "found needle")
        #expect(document.sourceVersion == beforeRevision + 1)
        #expect(source.string == "found needle")
    }

    // Validates: REQ-022 — semantic typography resolves under both system appearances and never
    // enters canonical source or document undo state.
    @Test func semanticAppearanceDoesNotMutateSource() throws {
        let document = MarkdownDocument()
        document.installTextForTesting("# heading")
        let before = document.text
        let beforeRevision = document.sourceVersion
        let beforeUndo = document.undoManager?.canUndo == true
        let typography = MarkdownTypography()

        for appearance in [NSAppearance(named: .aqua), NSAppearance(named: .darkAqua)] {
            let resolved = try #require(appearance)
            resolved.performAsCurrentDrawingAppearance {
                let baseColor = typography.baseAttributes[.foregroundColor] as? NSColor
                let headingFont = typography.attributes(for: .heading(level: 1))[.font] as? NSFont
                #expect(baseColor != nil)
                #expect(baseColor?.cgColor.components?.last ?? 0 > 0)
                #expect(headingFont != nil)
            }
        }

        #expect(document.text == before)
        #expect(document.sourceVersion == beforeRevision)
        #expect(document.undoManager?.canUndo == beforeUndo)
    }

    // Validates: REQ-044 — the production count owner computes Unicode word/character results off
    // the main actor and ContentView applies only the current source revision's result.
    @Test func liveCountOwnerEnumeratesUnicodeAndRevisionRoute() async throws {
        let computer = TextStatsComputer()
        #expect(await computer.counts(for: "two words 🐙") == .init(words: 3, characters: 11))
        let owner = LiveCountOwner()
        await owner.update(snapshot: "two words 🐙", revision: 1)
        #expect(owner.displayLabel == "3 words · 11 characters")
        await owner.update(snapshot: "one", revision: 2)
        #expect(owner.displayLabel == "1 words · 3 characters")
        let delayedOwner = LiveCountOwner { snapshot in
            if snapshot == "old" { try? await Task.sleep(for: .milliseconds(50)) }
            return TextStats.counts(snapshot)
        }
        let oldRevision = Task { @MainActor in
            await delayedOwner.update(snapshot: "old", revision: 1)
        }
        await Task.yield()
        await delayedOwner.update(snapshot: "new", revision: 2)
        await oldRevision.value
        #expect(delayedOwner.displayLabel == "1 words · 3 characters")
    }

    // Validates: REQ-010, REQ-011, REQ-022 — programmatic display styling is attribute-only and creates no
    // source edit, revision, or document undo item.
    @Test func programmaticSourceStylingCannotCreateAnEdit() async throws {
        let fixture = try makeFixture(source: "# Heading\nplain\n")
        let beforeText = fixture.document.text
        let beforeRevision = fixture.document.sourceVersion
        let beforeUndo = fixture.document.undoManager?.canUndo == true
        let task = try #require(fixture.coordinator.highlight(debounced: false))
        await task.value

        #expect(fixture.storage.string == beforeText)
        #expect(fixture.document.text == beforeText)
        #expect(fixture.document.sourceVersion == beforeRevision)
        #expect(fixture.document.undoManager?.canUndo == beforeUndo)
        #expect(fixture.storage.attributes(at: 0, effectiveRange: nil)[.font] as? NSFont != nil)
    }

    // Validates: REQ-044, REQ-045 — cancelled derived count work produces no result.
    @Test func staleCountWorkReturnsNothing() async {
        let cancelled = TextStats.counts(String(repeating: "word ", count: 10_000)) { true }
        #expect(cancelled == nil)
    }

    private struct Fixture {
        let document: MarkdownDocument
        let session: EditorSession
        let coordinator: SourceEditor.Coordinator
        let storage: NSTextStorage
        let textView: MarkdownSourceTextView
    }

    private final class FinderClient: NSObject, NSTextFinderClient {
        let string: String
        var selectedRanges: [NSValue]

        init(string: String) {
            self.string = string
            self.selectedRanges = [NSValue(range: NSRange(location: 0, length: 0))]
        }

        var firstSelectedRange: NSRange { selectedRanges.first?.rangeValue ?? NSRange(location: 0, length: 0) }

        func scrollRangeToVisible(_ range: NSRange) {}
    }

    // Validates: REQ-093 — while no valid WYSIWYG presentation exists, Source stays *available*.
    //
    // REQ-093 promises three things: WYSIWYG becomes unavailable, no stale rich content is exposed,
    // and Source keeps working. The first two were proved
    // (`projectionMappingRefusesWithoutPresentation`, `repeatedLoadsNeverReuseRevisionOrOldPresentation`)
    // and the third — the only one that is a capability rather than a refusal — was not. A build in
    // which losing the projection also froze the Source editor would have satisfied every cited
    // proof, which is the REQ-058 shape CLAUDE.md section 3 records.
    @Test func sourceStaysEditableWhileWYSIWYGHasNoPresentation() throws {
        let fixture = try makeFixture(source: "alpha bravo\n")
        fixture.session.clearProjectionForTesting()

        // Precondition: WYSIWYG really is unavailable, so this is the state the requirement is about.
        if case .waitingForCurrentProjection = fixture.session.wysiwygModeState.availability {
            // expected
        } else {
            Issue.record("expected WYSIWYG to be unavailable, got \(fixture.session.wysiwygModeState.availability)")
        }

        let insertAt = NSRange(location: 5, length: 0)
        fixture.session.updateSourceModeState { $0.selection = SourceSelection(utf16: insertAt) }
        fixture.textView.setSelectedRange(insertAt)
        let beforeRevision = fixture.document.sourceVersion

        #expect(fixture.coordinator.textView(
            fixture.textView,
            shouldChangeTextIn: insertAt,
            replacementString: "X"
        ), "the Source editor refused an ordinary edit while WYSIWYG was unavailable")
        fixture.storage.replaceCharacters(in: insertAt, with: "X")
        fixture.textView.setSelectedRange(NSRange(location: 6, length: 0))
        fixture.coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: fixture.textView))

        // The edit reached canonical source through the ordinary route, and history still works.
        #expect(fixture.document.text == "alphaX bravo\n")
        #expect(fixture.document.sourceVersion == beforeRevision + 1)
        #expect(fixture.document.undoManager?.canUndo == true)

        fixture.document.undoManager?.undo()
        #expect(fixture.document.text == "alpha bravo\n")
    }

    private func makeFixture(source: String) throws -> Fixture {
        let document = MarkdownDocument()
        document.installTextForTesting(source)
        let session = EditorSession()
        session.attach(document: document)
        let placement = ImagePlacementController()
        placement.attach(actions: document)
        let coordinator = SourceEditor.Coordinator(document: document, placementController: placement, session: session)
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 640, height: CGFloat.greatestFiniteMagnitude))
        storage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(container)
        storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: source)
        let textView = MarkdownSourceTextView(frame: NSRect(x: 0, y: 0, width: 640, height: 400), textContainer: container)
        textView.allowsUndo = false
        textView.documentActions = document
        textView.delegate = coordinator
        coordinator.textView = textView
        return Fixture(document: document, session: session, coordinator: coordinator, storage: storage, textView: textView)
    }

}
