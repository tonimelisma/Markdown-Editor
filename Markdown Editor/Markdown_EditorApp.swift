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
            // REQ-033: offered only by a build that updates itself (AppUpdater).
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    appDelegate.checkForUpdates()
                }
                .disabled(!AppUpdater.isEnabledForThisProcess)
            }
            EditorMenuCommands()
            // REQ-084: Find, Spelling and Grammar, Substitutions, Transformations and Speech, which
            // a SwiftUI app's Edit menu has only when asked. Without them ⌘F did nothing in either
            // editor, though both use the find bar (agent-drive probe 45969842167).
            TextEditingCommands()
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
                OpenRecentMenu(recents: RecentDocuments.shared)
            }
            // REQ-014: restore standard document File actions removed with DocumentGroup. The
            // group replaced also held Close: without it ⌘W did nothing (tour 45968755636).
            CommandGroup(replacing: .saveItem) {
                Button("Close") {
                    NSApp.sendAction(#selector(NSWindow.performClose(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("w")
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

    /// Every launch argument and environment variable this application reads.
    ///
    /// // COR-90: the diagnostic and benchmark entry points are real product surface — the
    /// // shipping binary honours all of them — and until this list existed no requirement
    /// // described them and nothing enumerated them. They are deliberately *not* compiled out
    /// // of Release: `Scripts/benchmark.sh` builds Release, so REQ-090's evidence comes from
    /// // the configuration that ships, which is the point.
    /// //
    /// // The safety property is not that these are absent but that none of them can mutate a
    /// // document without `--diagnostic-smoke-exit`, an argument no ordinary launch supplies.
    /// // `LaunchSurfaceTests` proves the list is complete and that property holds.
    /// // REQ-144.
    enum LaunchSurface {
        /// Arguments that select a non-editing mode of operation.
        static let arguments = [
            "--benchmark",
            "--benchmark-manifest",
            "--corpus",
            "--duration",
            "--interval-ms",
            "--size",
            "--diagnostic-smoke-exit",
        ]

        /// Environment variables read anywhere in the application.
        static let environmentVariables = [
            "MARKDOWN_EDITOR_BENCHMARK",
            "MARKDOWN_EDITOR_DIAGNOSTICS_DIR",
            "MARKDOWN_EDITOR_FRAME_OBSERVER",
            "MARKDOWN_EDITOR_SMOKE_EXERCISE_EDITS",
            "MARKDOWN_EDITOR_SMOKE_EXIT_SECONDS",
            "MARKDOWN_EDITOR_SMOKE_SCENE",
            "MARKDOWN_EDITOR_SMOKE_WINDOW_HEIGHT",
        ]

        /// The subset that can cause the application to modify document content on its own.
        /// Each is additionally gated on `isSmokeRun`.
        static let documentMutating = ["MARKDOWN_EDITOR_SMOKE_EXERCISE_EDITS"]
    }

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
        var args = Array(ProcessInfo.processInfo.arguments.dropFirst())
        if let manifestIndex = args.firstIndex(of: "--benchmark-manifest") {
            let end = min(args.count, manifestIndex + 2)
            args.removeSubrange(manifestIndex..<end)
        }
        guard let path = args.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            return nil
        }
        return URL(fileURLWithPath: path)
    }

    /// A screen a screenshot run can ask a smoke launch to present (REQ-151).
    ///
    /// // `Scripts/screenshots.sh` publishes a committed gallery of the product's important
    /// // screens. Source mode and the link sheet are not reachable by a launch alone, and
    /// // CLAUDE.md §4 forbids reaching them by driving the UI. Naming the screen at launch and
    /// // applying it through the ordinary window-scoped command routes — the same handle
    /// // `exerciseSmokeEdits` uses — keeps the capture passive: no synthetic events, no
    /// // accessibility, no screen automation.
    /// //
    /// // Closed and `CaseIterable` so a new screen cannot be added without the gallery script's
    /// // scene list and this enum being compared by a test.
    nonisolated enum SmokeScene: String, CaseIterable, Sendable {
        /// The rendered reading surface, which is also the ordinary launch state.
        case wysiwyg
        /// The Markdown source, syntax highlighted.
        case source
        /// The window-attached link sheet, over a selected link in the rendered surface.
        case linkSheet = "link-sheet"
    }

    /// The screen this run was asked to present, or `nil` for the ordinary launch state.
    ///
    /// // Gated on `isSmokeRun` like every other smoke affordance: the variable alone changes
    /// // nothing in a launch the user performs (REQ-144).
    nonisolated static var smokeScene: SmokeScene? {
        guard isSmokeRun,
              let raw = ProcessInfo.processInfo.environment["MARKDOWN_EDITOR_SMOKE_SCENE"],
              !raw.isEmpty else { return nil }
        return SmokeScene(rawValue: raw)
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
    /// REQ-033: `nil` unless this build updates itself.
    private var updater: AppUpdater?

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
        RecentDocuments.shared.refresh()
        guard !Self.isRunningUnitTests else { return }
        // REQ-033: never in a smoke or benchmark run (AppUpdater.isEnabledForThisProcess).
        updater = AppUpdater.startIfEnabled()
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
            // Process-wide sampler and frame records have no document owner. Keeping them
            // documentless prevents a single opened fixture from appearing as two documents in
            // process-level verification; MarkdownDocument allocates the real document handle.
            let trace = JSONLinesEditorTrace(log: log, documentHandle: nil)
            let sampler = PerformanceSampler(trace: trace)
            applicationSampler = sampler
            let probe = MainActorResponsivenessProbe(sampler: sampler)
            probe.start()
            responsivenessProbe = probe
            let observer = FrameObserver(sampler: sampler)
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
                if let scene = Self.smokeScene {
                    // Same wait, and for the same reason: the link scene selects a run of the
                    // authoritative presentation, which does not exist at launch.
                    try? await Task.sleep(for: .seconds(min(2, Self.smokeExitSeconds / 3)))
                    Self.presentSmokeScene(scene)
                }
                try? await Task.sleep(for: .seconds(Self.smokeExitSeconds))
                // NSDocument can keep NSApp.terminate(nil) pending when this verifier has
                // intentionally exercised an unsaved edit. Perform the same cleanup that
                // applicationWillTerminate would have performed before closing the log, then
                // leave the throwaway verifier process directly. Waiting for AppKit's document
                // close negotiation here otherwise leaves the process alive until the script's
                // timeout and loses the performance summaries that cleanup emits.
                self.stopRuntimeDiagnostics()
                DiagnosticLog.shared?.finishSynchronously()
                Foundation.exit(EXIT_SUCCESS)
            }
        }

        // REQ-002/REQ-131: a plain launch shows an untitled document, as TextEdit does. AppKit
        // asks `applicationShouldOpenUntitledFile` only of the application's own delegate, which
        // in a SwiftUI-lifecycle app is SwiftUI's: launched from the Dock the app opened no window
        // at all (owner, 2026-11-27). `launchIsDefaultUserInfoKey` is false for a launch that
        // opens a file or restores windows, so neither gets an extra untitled one, and a document
        // AppKit did open by then is seen on the next turn.
        let isDefaultLaunch = (notification.userInfo?[NSApplication.launchIsDefaultUserInfoKey] as? Bool) ?? false
        Task { @MainActor in
            Self.openUntitledIfNeeded(isDefaultLaunch: isDefaultLaunch)
        }
    }

    /// Whether a launch or a Dock click with no windows should show a new untitled document.
    nonisolated static func shouldOpenUntitled(
        isDefaultLaunch: Bool,
        openDocuments: Int,
        isRunningUnitTests: Bool,
        isSmokeRun: Bool,
        isBenchmark: Bool
    ) -> Bool {
        isDefaultLaunch && openDocuments == 0 && !isRunningUnitTests && !isSmokeRun && !isBenchmark
    }

    @MainActor
    private static func openUntitledIfNeeded(isDefaultLaunch: Bool) {
        guard shouldOpenUntitled(
            isDefaultLaunch: isDefaultLaunch,
            openDocuments: NSDocumentController.shared.documents.count,
            isRunningUnitTests: isRunningUnitTests,
            isSmokeRun: isSmokeRun,
            isBenchmark: BenchmarkDriver.isRequested
        ) else { return }
        _ = try? NSDocumentController.shared.openUntitledDocumentAndDisplay(true)
    }

    /// A click on the Dock icon with no window open shows an untitled document, as TextEdit does.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !flag, NSDocumentController.shared.documents.isEmpty else { return true }
        Self.openUntitledIfNeeded(isDefaultLaunch: true)
        return false
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
            .first
        else { return }

        exerciseSmokeEdits(using: controller)
    }

    /// The same window-scoped route used by the process smoke run, exposed to component tests so
    /// REQ-115 can be falsified without making a test depend on a window server or a timing race.
    @MainActor
    static func exerciseSmokeEdits(using controller: EditorCommandController) {
        guard let session = controller.session, let document = controller.document else { return }

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

    /// Presents one gallery screen through the window-scoped command routes (REQ-151).
    @MainActor
    private static func presentSmokeScene(_ scene: SmokeScene) {
        guard let controller = NSApp.windows
            .compactMap({ ($0.toolbar?.delegate as? EditorToolbarController)?.commandController })
            .first
        else { return }

        presentSmokeScene(scene, using: controller)
    }

    /// The same route, exposed to component tests so REQ-151 can be falsified without a window
    /// server or a timing race.
    ///
    /// // Every branch goes through `EditorCommandController.perform`, so a screen the product
    /// // would refuse to show is refused here too, and nothing here can change document content:
    /// // `.editLink` only opens the sheet — committing it is a separate route this never calls.
    @MainActor
    @discardableResult
    static func presentSmokeScene(
        _ scene: SmokeScene,
        using controller: EditorCommandController
    ) -> Bool {
        guard let session = controller.session else { return false }
        switch scene {
        case .wysiwyg:
            return controller.perform(.wysiwygMode) == .accepted
        case .source:
            return controller.perform(.sourceMode) == .accepted
        case .linkSheet:
            guard controller.perform(.wysiwygMode) == .accepted,
                  let presentation = session.presentation,
                  case .editable(let id) = session.wysiwygModeState.availability,
                  id == presentation.id
            else { return false }
            // Select an existing link so the sheet shows a real destination rather than an
            // empty field. Falls back to the first word, which keeps the screen reachable on a
            // fixture that happens to carry no link.
            let range = presentation.runs.first { $0.linkDestination != nil }?.utf16Range
                ?? NSRange(location: 0, length: min(12, (presentation.renderedString as NSString).length))
            guard range.length > 0 else { return false }
            session.updateWYSIWYGModeState {
                $0.selection = ProjectionSelection(
                    utf16: range,
                    revision: presentation.projectionRevision
                )
            }
            return controller.perform(.editLink) == .started
        }
    }

    /// App ▸ Check for Updates… (REQ-033).
    func checkForUpdates() {
        updater?.checkForUpdates()
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopRuntimeDiagnostics()
        DiagnosticLog.shared?.finishSynchronously()
    }

    /// Stops process-wide diagnostic producers and flushes every live editor sampler. Smoke
    /// verification calls this explicitly because its fixture may be dirty and AppKit's normal
    /// document-close negotiation can therefore refuse or defer `NSApp.terminate(nil)`.
    @MainActor
    private func stopRuntimeDiagnostics() {
        DiagnosticRunCoordinator.shared.flushAndInvalidateAll()
        responsivenessProbe?.stop()
        frameObserver?.stop()
        applicationSampler?.invalidate()
        responsivenessProbe = nil
        frameObserver = nil
        applicationSampler = nil
        watchdog?.stop()
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

    /// REQ-021: every document opened or saved is noted here; Open Recent follows.
    override func noteNewRecentDocumentURL(_ url: URL) {
        super.noteNewRecentDocumentURL(url)
        RecentDocuments.shared.refresh()
    }

    override func clearRecentDocuments(_ sender: Any?) {
        super.clearRecentDocuments(sender)
        RecentDocuments.shared.refresh()
    }

    /// The app-modal alert for a document that could not be opened. It holds the main thread's
    /// modal session until the person dismisses it, which the watchdog must not take for a stall.
    override func presentError(_ error: Error) -> Bool {
        AppModalSession.around { super.presentError(error) }
    }

}


/// REQ-021: the documents File › Open Recent lists, as the document controller records them.
///
/// Part of the app's SwiftUI commands. An Open Recent item added to the File menu through AppKit
/// was dropped whenever SwiftUI rebuilt that menu from the commands, after launch and as it
/// opened, so the File menu had none (tours 45976057730, 45977189566).
@MainActor
final class RecentDocuments: ObservableObject {
    static let shared = RecentDocuments()

    @Published private(set) var urls: [URL] = []

    func refresh() {
        let current = NSDocumentController.shared.recentDocumentURLs
        if current != urls { urls = current }
    }
}

struct OpenRecentMenu: View {
    @ObservedObject var recents: RecentDocuments

    var body: some View {
        Menu("Open Recent") {
            ForEach(recents.urls, id: \.self) { url in
                Button(url.lastPathComponent) {
                    NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
                }
            }
            Divider()
            Button("Clear Menu") {
                NSDocumentController.shared.clearRecentDocuments(nil)
            }
            .disabled(recents.urls.isEmpty)
        }
    }
}
