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
                    NSApp.sendAction(Selector(("saveDocument:")), to: nil, from: nil)
                }
                .keyboardShortcut("s")
                Button("Save As…") {
                    NSApp.sendAction(Selector(("saveDocumentAs:")), to: nil, from: nil)
                }
                .keyboardShortcut("S")
                Button("Revert to Saved") {
                    NSApp.sendAction(Selector(("revertDocumentToSaved:")), to: nil, from: nil)
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

    override init() {
        // First NSDocumentController subclass instance becomes the shared controller.
        documentController = MarkdownDocumentController()
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = documentController
        ensureOpenRecentMenuItem()
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
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
