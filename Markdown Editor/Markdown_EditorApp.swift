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
            EditorMenuCommands()
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

    /// REQ-098: true when launched for process-level smoke verification. Neither an XCUITest
    /// nor screen automation — it opens a fixture and reads only structured diagnostic records.
    nonisolated static var isSmokeRun: Bool {
        ProcessInfo.processInfo.arguments.contains("--diagnostic-smoke-exit")
    }

    /// Content height for a smoke run's window, when the screenshot verification asks for one.
    /// `nil` outside a smoke run, so ordinary launches always use the product default.
    nonisolated static var smokeWindowHeight: CGFloat? {
        guard isSmokeRun,
              let raw = ProcessInfo.processInfo.environment["MARKDOWN_EDITOR_SMOKE_WINDOW_HEIGHT"],
              let height = Double(raw), height >= 200, height <= 4000 else { return nil }
        return CGFloat(height)
    }

    /// How long a smoke run stays up before terminating itself.
    ///
    /// // REQ-104: overridable because the two verifications need different lifetimes. The log
    /// // smoke run only needs the records to settle. The screenshot run additionally needs the
    /// // window server to have composited and published the window — measured at ~2.5 s on this
    /// // hardware, i.e. *after* the 2 s default — so a fixed 2 s made the capture race the
    /// // application's own exit and lose.
    nonisolated static var smokeExitSeconds: Double {
        guard let raw = ProcessInfo.processInfo.environment["MARKDOWN_EDITOR_SMOKE_EXIT_SECONDS"],
              let seconds = Double(raw), seconds > 0, seconds <= 60 else {
            return 2
        }
        return seconds
    }

    /// The fixture path passed as a plain positional argument alongside the smoke-exit flag.
    /// Launching the built binary directly bypasses Launch Services, so this app must open the
    /// fixture itself rather than rely on `application(_:open:)`.
    ///
    /// Matched by existing-file rather than "does not start with a dash": AppKit's `-Key Value`
    /// user-default argument pairs (e.g. `-ApplePersistenceIgnoreState YES`, used to veto window
    /// restoration for this run) put a bare, non-dash-prefixed value token in `arguments` too, so
    /// a dash-based filter would misidentify that token as the fixture path.
    nonisolated static var smokeFixtureURL: URL? {
        let args = ProcessInfo.processInfo.arguments.dropFirst()
        guard let path = args.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            return nil
        }
        return URL(fileURLWithPath: path)
    }

    /// REQ-115: true when the smoke run should additionally exercise one accepted insertion and
    /// one accepted semantic command.
    ///
    /// // Opt-in rather than always-on because `Scripts/smoke-screenshot.sh` shares this launch
    /// // path and its capture must show the pristine fixture. `Scripts/smoke-test.sh` sets it.
    nonisolated static var smokeExercisesEdits: Bool {
        isSmokeRun && ProcessInfo.processInfo.environment["MARKDOWN_EDITOR_SMOKE_EXERCISE_EDITS"] == "1"
    }

    /// Detects an unresponsive main actor for the process lifetime (REQ-096).
    private var watchdog: MainActorWatchdog?
    private var responsivenessProbe: MainActorResponsivenessProbe?
    private var frameObserver: FrameObserver?
    private var applicationSampler: PerformanceSampler?

    override init() {
        // REQ-098: window-state restoration is vetoed for smoke runs by Scripts/smoke-test.sh
        // passing `-ApplePersistenceIgnoreState YES` as a process argument, not by app code.
        // `applicationSupportsSecureRestorableState` only selects secure vs. legacy *encoding*;
        // it does not disable restoration. Two in-process alternatives were tried and rejected:
        // `UserDefaults.standard.set(forKey:)` persists to the on-disk preferences domain, and
        // since Debug and Release share one bundle identifier, that would silently disable
        // window restoration for every future ordinary launch of the real app, not just this
        // verification run (confirmed — it already had). `register(defaults:)` avoids that, but
        // registers into the lowest-priority domain: if the persistent domain already holds any
        // explicit value for this key (from a prior toggle, on any machine), the veto is
        // silently overridden and restoration proceeds anyway. A `-Key Value` process argument
        // is parsed into the argument domain, which outranks the persistent domain, is never
        // written to disk, and cannot be shadowed by any prior on-disk state.

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
        // The reporter writes through the serialized diagnostic sink directly because the main
        // actor may be the thing that is stalled.
        let report: MainActorWatchdog.Report
        if let log = DiagnosticLog.shared {
            report = log.makeProcessFaultReporter()
        } else {
            report = { _ in }
        }
        let watchdog = MainActorWatchdog(report: report)
        watchdog.start()
        self.watchdog = watchdog
        if let log = DiagnosticLog.shared {
            let trace = JSONLinesEditorTrace(log: log)
            let sampler = PerformanceSampler(trace: trace)
            applicationSampler = sampler
            let probe = MainActorResponsivenessProbe(sampler: sampler)
            probe.start()
            responsivenessProbe = probe
            let observer = FrameObserver(sampler: sampler, trace: trace)
            observer.start()
            frameObserver = observer
        }

        if BenchmarkDriver.runIfRequested() {
            if let fixture = Self.smokeFixtureURL {
                NSDocumentController.shared.openDocument(withContentsOf: fixture, display: true) { _, _, _ in }
            }
            Task { @MainActor in await BenchmarkDriver.run() }
            return
        }

        if Self.isSmokeRun {
            if let fixture = Self.smokeFixtureURL {
                NSDocumentController.shared.openDocument(withContentsOf: fixture, display: true) { _, _, _ in }
            }
            // REQ-098: settle within a bounded number of host updates, then close the log and
            // exit cleanly so the smoke script can assert on the terminating record.
            Task { @MainActor in
                if Self.smokeExercisesEdits {
                    // Let the first authoritative projection land before editing.
                    try? await Task.sleep(for: .seconds(min(2, Self.smokeExitSeconds / 3)))
                    Self.exerciseSmokeEdits()
                }
                try? await Task.sleep(for: .seconds(Self.smokeExitSeconds))
                DiagnosticRunCoordinator.shared.flushAndInvalidateAll()
                DiagnosticLog.shared?.finishSynchronously()
                NSApp.terminate(nil)
            }
        }
    }

    /// Drives one accepted insertion and one accepted semantic command through the ordinary
    /// production routes (REQ-115).
    ///
    /// // Before this, both process-level verifications only opened a fixture and idled. That
    /// // meant `editRefused` — the record that would have surfaced COR-25 and the four commands
    /// // COR-26 fixed — could never fire in a smoke run, and `nativeInputCallback` always had
    /// // zero samples.
    /// //
    /// // The window's own toolbar delegate is the handle: it already holds the window-scoped
    /// // `EditorCommandController` (ARC-024), so this reaches the session the same way a toolbar
    /// // click does. Nothing here drives, reads, or asserts on any UI — no synthetic events, no
    /// // accessibility, no screen automation — so `CLAUDE.md` §4's carve-out still holds.
    @MainActor
    private static func exerciseSmokeEdits() {
        guard let controller = NSApp.windows
            .compactMap({ ($0.toolbar?.delegate as? EditorToolbarController)?.commandController })
            .first,
            let session = controller.session,
            let document = controller.document
        else { return }

        // Source mode is deterministic: it does not depend on a projection having landed.
        session.setMode(.source)
        let caret = SourceSelection(utf16: NSRange(location: 0, length: 0))
        session.updateSourceModeState { $0.selection = caret }
        session.perform(
            .insertText("x"),
            selection: .source(caret),
            expectedSourceRevision: SourceRevision(value: document.sourceVersion)
        )

        // One semantic command over the character just inserted.
        let inserted = SourceSelection(utf16: NSRange(location: 0, length: 1))
        session.updateSourceModeState { $0.selection = inserted }
        _ = controller.perform(.bold)
    }

    func applicationWillTerminate(_ notification: Notification) {
        DiagnosticRunCoordinator.shared.flushAndInvalidateAll()
        responsivenessProbe?.stop()
        frameObserver?.stop()
        applicationSampler?.invalidate()
        responsivenessProbe = nil
        frameObserver = nil
        applicationSampler = nil
        watchdog?.stop()
        // REQ-095: the terminating record distinguishes a clean exit from a crash.
        DiagnosticLog.shared?.finishSynchronously()
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        // Unit tests host the app binary; opening an untitled document hangs the suite.
        if Self.isRunningUnitTests { return false }
        // REQ-098: a smoke run opens exactly its fixture; a second untitled document would
        // change the host-update count the smoke script asserts on.
        if Self.isSmokeRun { return false }
        if BenchmarkDriver.isRequested { return false }
        return true
    }

    func applicationOpenUntitledFile(_ sender: NSApplication) -> Bool {
        // Implementing this delegate method makes the app responsible for creating
        // the untitled document — returning true alone does not open one.
        if Self.isRunningUnitTests { return false }
        if Self.isSmokeRun { return false }
        do {
            _ = try NSDocumentController.shared.openUntitledDocumentAndDisplay(true)
            return true
        } catch {
            return false
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        if Self.isRunningUnitTests { return false }
        // Note: this selects secure vs. legacy state *encoding* only; it does not itself
        // disable restoration. The actual smoke-run veto is `ApplePersistenceIgnoreState`,
        // set in `init()` before AppKit's launch/restoration sequencing begins.
        if Self.isSmokeRun { return false }
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
