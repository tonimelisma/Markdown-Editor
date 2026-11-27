//
//  MacOSCitizenshipTests.swift
//  Markdown EditorTests
//
//  COR-82 / REQ-130, REQ-131: native printing, window behaviour, and one window-scoped
//  command surface.
//

import AppKit
import Synchronization
import Testing
@testable import Markdown_Editor

@MainActor
struct PrintingContractTests {

    private func documentWithPrintView(_ text: String) -> (MarkdownDocument, NSTextView) {
        let document = MarkdownDocument()
        document.installTextForTesting(text)
        let storage = NSTextStorage(string: text)
        let layoutManager = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 468, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = false
        storage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(container)
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 468, height: 200), textContainer: container)
        document.currentPrintView = textView
        return (document, textView)
    }

    // Verifies: REQ-130 — printing uses the native workflow. The app returns an
    // `NSPrintOperation` over the live editor view from `NSDocument.printOperation(withSettings:)`,
    // which is the override AppKit's Print menu item routes through; there is no custom print
    // window, no separate render path, and no second copy of the document to drift.
    @Test func printingReturnsANativeOperationOverTheEditorView() throws {
        let (document, textView) = documentWithPrintView("# Title\n\nBody paragraph.\n")

        let operation = try document.printOperation(withSettings: [:])

        #expect(operation.view === textView, "printing must paginate the live editor view")
        // Margins are set on a copy of the shared print info, so printing does not mutate the
        // user's system-wide defaults.
        #expect(operation.printInfo !== NSPrintInfo.shared)
        #expect(operation.printInfo.leftMargin == 36)
        #expect(operation.printInfo.rightMargin == 36)
    }

    // Verifies: REQ-096 — the print panel's load is AppKit's work, not the app's stall. Print
    // begins the sheet inside `AppModalSession.aroundAppKitWork`, so the first load (1.4 s in
    // probe 46007142113, 2 s in Release tour 46007567920) is bounded as a wait in AppKit's loop.
    @Test func printBeginsItsPanelWhileAppKitWorksForTheApp() {
        let (document, _) = documentWithPrintView("# Title\n\nBody paragraph.\n")
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: true)
        let controller = NSWindowController(window: window)
        document.addWindowController(controller)
        defer { document.removeWindowController(controller) }
        var presented: (operation: NSPrintOperation, window: NSWindow, appKitWorking: Bool)?
        document.presentPrintPanel = { operation, window in
            presented = (operation, window, AppModalSession.shared.isAppKitWorking)
        }

        document.printDocument(nil)

        #expect(presented?.window === window, "Print did not begin its sheet on the document's window")
        #expect(presented?.appKitWorking == true, "the print panel began outside AppKit's work")
        #expect(presented?.operation.showsPrintPanel == true)
        #expect(!AppModalSession.shared.isAppKitWorking)
    }

    // Verifies: REQ-130 — printing changes neither source nor history. A print is a read, and the
    // failure this guards against is a print path that re-lays-out through the document and marks
    // it edited, so the user is asked to save a file they only looked at.
    @Test func printingMutatesNeitherSourceNorHistory() throws {
        let (document, _) = documentWithPrintView("# Title\n\nBody paragraph.\n")
        let textBefore = document.text
        let versionBefore = document.sourceVersion
        let generationBefore = document.locationGeneration
        let couldUndoBefore = document.undoManager?.canUndo == true
        let editedBefore = document.isDocumentEdited

        _ = try document.printOperation(withSettings: [:])

        #expect(document.text == textBefore)
        #expect(document.sourceVersion == versionBefore)
        #expect(document.locationGeneration == generationBefore)
        #expect(document.undoManager?.canUndo == couldUndoBefore)
        #expect(document.isDocumentEdited == editedBefore)
    }

    // Verifies: REQ-130 — the presentation actually paginates. Forced layout, not attribute
    // inspection: the plan requires visible geometry where geometry is the contract, and a
    // document taller than one page must produce more than one page of laid-out content.
    @Test func longDocumentPaginatesAcrossMultiplePages() throws {
        let long = (1...400).map { "Paragraph number \($0) with enough text to occupy a line." }
            .joined(separator: "\n\n")
        let (document, textView) = documentWithPrintView(long)

        let operation = try document.printOperation(withSettings: [:])
        guard let layoutManager = textView.layoutManager, let container = textView.textContainer else {
            Issue.record("print view has no TextKit stack")
            return
        }
        // Force real layout rather than reading a declared size.
        layoutManager.ensureLayout(for: container)
        let usedHeight = layoutManager.usedRect(for: container).height

        let info = operation.printInfo
        let printableHeight = info.paperSize.height - info.topMargin - info.bottomMargin
        #expect(printableHeight > 0)
        #expect(
            usedHeight > printableHeight,
            "fixture is not taller than one page (\(usedHeight) vs \(printableHeight)); it cannot prove pagination"
        )
    }

    // Verifies: REQ-130 — printing with no visible editor is refused with a typed error rather
    // than crashing or silently printing an empty page.
    @Test func printingWithoutAnEditorIsRefused() {
        let document = MarkdownDocument()
        document.installTextForTesting("text")
        document.currentPrintView = nil

        #expect(throws: (any Error).self) {
            _ = try document.printOperation(withSettings: [:])
        }
    }
}

@MainActor
struct WindowCitizenshipTests {

    // Verifies: REQ-131 — window restoration, cascading and tabbing are AppKit's, not
    // reimplemented. The app sets only the standard metadata; there is no custom frame store or
    // tab manager, which `lifecycleOwnerHasNoDuplicateDocumentSubsystem` also guards.
    @Test func windowsUseStandardRestorationCascadingAndTabbing() throws {
        let document = MarkdownDocument()
        document.makeWindowControllers()
        defer { document.close() }
        let window = try #require(document.windowControllers.first?.window)

        #expect(window.tabbingIdentifier == "MarkdownDocument")
        #expect(window.tabbingMode == .automatic, "tabbing overrides the person's Prefer tabs setting")
        // A frame autosave name is what makes AppKit restore and cascade; an empty one means the
        // app is silently not participating.
        // Both signals asserted separately rather than with `||`: either one alone passing would
        // hide the other silently opting out. Observed values are "MarkdownDocumentWindow" / true.
        #expect(window.frameAutosaveName == MarkdownDocument.frameAutosaveName, "no frame autosave name, so AppKit cannot restore or cascade")
        // Tests run inside the app and share its defaults: they must never save the frame the
        // real app restores (a test-shrunk frame left the owner's copy opening stamp-sized).
        #expect(MarkdownDocument.frameAutosaveName != "MarkdownDocumentWindow")
        #expect(window.isRestorable, "window opts out of state restoration")
    }

    // Verifies: REQ-131 — a document window is laid out at its final size only. Creating it at
    // another size, or restyling and resizing it afterwards, laid out the whole window again —
    // SwiftUI's first render, both editors and the toolbar — which on a CI runner was a third of
    // what the first window cost (DECISIONS.md, 2026-11-27). `makeWindowControllers` runs
    // synchronously on the main actor, so every resize it causes is posted inside this call and
    // nothing else's can be.
    @Test func theDocumentWindowIsCreatedAtItsFinalSize() throws {
        // A frame AppKit saved under the autosave name is restored onto the next window, and that
        // restoration is a legitimate resize this test is not about. `toolbarRemainsUsableAtTheMinimumWindowSize`
        // leaves one at the minimum size: without this, the falsification run (CI 45936808313) saw
        // 320×208 after five resizes, which said as much about test order as about layout.
        UserDefaults.standard.removeObject(forKey: "NSWindow Frame \(MarkdownDocument.frameAutosaveName)")
        let document = MarkdownDocument()
        let resizes = Mutex<[String]>([])
        let observer = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification, object: nil, queue: nil
        ) { note in
            let size = (note.object as? NSWindow).map { $0.contentRect(forFrameRect: $0.frame).size }
            resizes.withLock { $0.append(size.map { "\($0.width)×\($0.height)" } ?? "?") }
        }
        document.makeWindowControllers()
        NotificationCenter.default.removeObserver(observer)
        defer { document.close() }
        let window = try #require(document.windowControllers.first?.window)

        let contentSize = window.contentRect(forFrameRect: window.frame).size
        let expected = MarkdownDocument.defaultContentSize(visibleFrame: NSScreen.main?.visibleFrame)
        #expect(contentSize == expected, "the window's content is \(contentSize), not its default size")
        // Sizing a new window to its content is the one layout it needs. Any resize to another
        // size lays the whole window out again: the restyle-then-resize this replaced went
        // 720×560 → 720×592 → 720×560 (CI 45937955461).
        let sizes = resizes.withLock { $0 }
        let final = "\(expected.width)×\(expected.height)"
        #expect(sizes.allSatisfy { $0 == final }, "the window passed through other sizes, each laid out: \(sizes)")
    }

    // Verifies: REQ-131 — a new window is big enough to read a document and to show the whole
    // toolbar. It opened at 720×560, at which the toolbar already overflowed, and the owner saw
    // windows "stamp-sized".
    @Test func aNewWindowIsBigEnoughToRead() {
        let roomy = MarkdownDocument.defaultContentSize(visibleFrame: NSRect(x: 0, y: 0, width: 1728, height: 1079))
        #expect(roomy.width >= 860 && roomy.height >= 680, "a new window on a laptop screen is only \(roomy)")
        let small = MarkdownDocument.defaultContentSize(visibleFrame: NSRect(x: 0, y: 0, width: 800, height: 560))
        #expect(small.width <= 720 && small.height <= 440, "a new window does not fit a small screen: \(small)")
        #expect(small.width >= MarkdownDocument.minimumContentSize.width)
    }

    // Verifies: REQ-131 — a saved frame too small to read in is not restored. Unit tests run
    // inside the app and shared its defaults, and one of them shrank a window to its minimum:
    // the owner's copy then opened stamp-sized. A frame like that is replaced by the default.
    @Test func aStampSizedSavedFrameIsNotRestored() throws {
        let key = "NSWindow Frame \(MarkdownDocument.frameAutosaveName)"
        UserDefaults.standard.set("100 100 320 240 0 0 1440 875 ", forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }
        let document = MarkdownDocument()
        document.makeWindowControllers()
        defer { document.close() }
        let window = try #require(document.windowControllers.first?.window)

        let size = window.contentRect(forFrameRect: window.frame).size
        #expect(
            size.width >= MarkdownDocument.smallestRestorableContentSize.width
                && size.height >= MarkdownDocument.smallestRestorableContentSize.height,
            "a stamp-sized saved frame was restored: \(size)"
        )
    }

    // Verifies: REQ-002 — a plain launch shows an untitled document, as TextEdit does, and only a
    // plain launch: not one that opens a file or restores windows, and not a verification run.
    @Test func onlyAPlainLaunchWithNoDocumentOpensAnUntitledOne() {
        func decide(_ isDefault: Bool, _ documents: Int, tests: Bool = false, smoke: Bool = false, bench: Bool = false) -> Bool {
            MarkdownAppDelegate.shouldOpenUntitled(
                isDefaultLaunch: isDefault, openDocuments: documents,
                isRunningUnitTests: tests, isSmokeRun: smoke, isBenchmark: bench
            )
        }
        #expect(decide(true, 0))
        #expect(!decide(false, 0), "a launch that opened a file or restored windows got an untitled one too")
        #expect(!decide(true, 1), "a second, untitled window beside a document AppKit already opened")
        #expect(!decide(true, 0, tests: true) && !decide(true, 0, smoke: true) && !decide(true, 0, bench: true))
    }

    // Verifies: REQ-131 — the command surface stays usable at the minimum window size. A toolbar
    // that cannot compress clips its items, and a clipped command is unreachable by mouse however
    // well it validates.
    @Test func toolbarRemainsUsableAtTheMinimumWindowSize() throws {
        let document = MarkdownDocument()
        document.makeWindowControllers()
        defer { document.close() }
        let window = try #require(document.windowControllers.first?.window)

        window.setContentSize(window.contentMinSize)
        #expect(window.contentMinSize.width > 0, "no minimum size is declared, so nothing bounds compression")

        // `#require` rather than `if let`: an absent toolbar would skip every assertion below and
        // report a pass, which is the shape this repository keeps having to unlearn.
        let toolbar = try #require(window.toolbar, "the document window has no toolbar to compress")
        let items = Set(toolbar.items.map(\.itemIdentifier))
        #expect(!items.isEmpty)
        #expect(toolbar.displayMode != .labelOnly, "label-only mode clips first at narrow widths")
    }

    // Verifies: REQ-131 — command validation is window-scoped. Two documents, two controllers:
    // performing a command through one must not reach the other, which is the failure a global
    // command controller or a broadcast notification produces.
    @Test func commandValidationStaysWindowScoped() throws {
        let first = MarkdownDocument()
        first.installTextForTesting("first document\n")
        let second = MarkdownDocument()
        second.installTextForTesting("second document\n")

        let firstSession = EditorSession()
        firstSession.attach(document: first)
        let secondSession = EditorSession()
        secondSession.attach(document: second)

        let firstController = EditorCommandController()
        firstController.bind(
            document: first,
            session: firstSession,
            actionRouter: EditorActionRouter(),
            window: nil
        )

        let secondTextBefore = second.text
        let secondVersionBefore = second.sourceVersion

        // Drive every command through the first controller; the second document must be untouched.
        for command in EditorCommand.allCases {
            _ = firstController.perform(command)
        }

        #expect(second.text == secondTextBefore, "a command reached a document it was not bound to")
        #expect(second.sourceVersion == secondVersionBefore)
    }
}
