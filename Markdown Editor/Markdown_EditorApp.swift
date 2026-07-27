//
//  Markdown_EditorApp.swift
//  Markdown Editor
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

// REQ-014: AppKit document stack owns New/Open/Save/autosave/Versions/tabs/Recents.

@main
struct Markdown_EditorApp: App {
    @NSApplicationDelegateAdaptor(MarkdownAppDelegate.self) private var appDelegate

    var body: some Scene {
        // Document windows are created by MarkdownDocument.makeWindowControllers().
        // Settings satisfies SwiftUI's Scene requirement without a DocumentGroup.
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Document") {
                    NSDocumentController.shared.newDocument(nil)
                }
                .keyboardShortcut("n")
            }
            CommandGroup(after: .newItem) {
                Button("Open…") {
                    NSDocumentController.shared.openDocument(nil)
                }
                .keyboardShortcut("o")
            }
            // REQ-014: restore standard document File actions removed with DocumentGroup.
            CommandGroup(replacing: .saveItem) {
                Button("Save") {
                    NSApp.sendAction(#selector(NSDocument.save(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("s")
                Button("Save As…") {
                    NSApp.sendAction(#selector(NSDocument.saveAs(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("S")
                Button("Revert to Saved") {
                    NSApp.sendAction(#selector(NSDocument.revertToSaved(_:)), to: nil, from: nil)
                }
            }
        }
    }
}

@MainActor
final class MarkdownAppDelegate: NSObject, NSApplicationDelegate {
    private let documentController: MarkdownDocumentController

    /// Document File-menu selectors that must remain reachable via First Responder.
    static let requiredDocumentSelectors: [String] = [
        "saveDocument:",
        "saveDocumentAs:",
        "revertDocumentToSaved:",
    ]

    /// True when the app binary is hosted by XCTest / Swift Testing.
    nonisolated static var isRunningUnitTests: Bool {
        let env = ProcessInfo.processInfo.environment
        if env["XCTestConfigurationFilePath"] != nil { return true }
        if env["XCTestBundlePath"] != nil { return true }
        if env["XCTestSessionIdentifier"] != nil { return true }
        if NSClassFromString("XCTestCase") != nil { return true }
        if ProcessInfo.processInfo.arguments.contains(where: { $0.contains("xctest") }) {
            return true
        }
        return false
    }

    /// Detects an unresponsive main actor for the process lifetime (REQ-096).
    private var watchdog: MainActorWatchdog?

    override init() {
        // First NSDocumentController subclass instance becomes the shared controller.
        // REQ-095: the run log must exist before the first document is constructed, because
        // each document wires its trace sink at init.
        DiagnosticLog.startShared(
            hostKind: Self.isRunningUnitTests ? .unitTest : .production
        )
        documentController = MarkdownDocumentController()
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = documentController
        guard !Self.isRunningUnitTests else { return }
        ensureOpenRecentMenuItem()
        // The report fires from a background task precisely because the main actor may be
        // stalled, so the record is queued rather than awaited.
        let watchdog = MainActorWatchdog { millis in
            Task { @MainActor in
                DiagnosticLog.shared?.record(
                    .mainActorStall,
                    level: .fault,
                    category: .lifecycle,
                    data: [(.millis, .uint(millis))]
                )
            }
        }
        watchdog.start()
        self.watchdog = watchdog
    }

    func applicationWillTerminate(_ notification: Notification) {
        watchdog?.stop()
        // REQ-095: the terminating record distinguishes a clean exit from a crash.
        DiagnosticLog.shared?.finishSynchronously()
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        // Unit tests host the app binary; opening an untitled document hangs the suite.
        if Self.isRunningUnitTests { return false }
        return true
    }

    func applicationOpenUntitledFile(_ sender: NSApplication) -> Bool {
        // Implementing this delegate method makes the app responsible for creating
        // the untitled document — returning true alone does not open one.
        if Self.isRunningUnitTests { return false }
        do {
            _ = try NSDocumentController.shared.openUntitledDocumentAndDisplay(true)
            return true
        } catch {
            return false
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        if Self.isRunningUnitTests { return false }
        return true
    }

    /// NSDocumentController populates Open Recent when a standard menu item exists.
    private func ensureOpenRecentMenuItem() {
        guard let mainMenu = NSApp.mainMenu else { return }
        guard let fileMenu = mainMenu.item(withTitle: "File")?.submenu else { return }
        if fileMenu.items.contains(where: { $0.title == "Open Recent" }) { return }
        let recent = fileMenu.insertItem(
            withTitle: "Open Recent",
            action: nil,
            keyEquivalent: "",
            at: min(2, fileMenu.numberOfItems)
        )
        let recentMenu = NSMenu(title: "Open Recent")
        recent.submenu = recentMenu
        recentMenu.addItem(
            withTitle: "Clear Menu",
            action: #selector(NSDocumentController.clearRecentDocuments(_:)),
            keyEquivalent: ""
        )
    }
}

/// Ensures MarkdownDocument is the shared controller's document class.
@MainActor
final class MarkdownDocumentController: NSDocumentController {
    override func documentClass(forType typeName: String) -> AnyClass? {
        if typeName == MarkdownContentType.identifier
            || typeName == "Markdown Document"
            || typeName.lowercased().contains("markdown") {
            return MarkdownDocument.self
        }
        return super.documentClass(forType: typeName) ?? MarkdownDocument.self
    }

}
