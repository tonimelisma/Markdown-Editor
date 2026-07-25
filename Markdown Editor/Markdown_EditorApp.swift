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
        }
    }
}

@MainActor
final class MarkdownAppDelegate: NSObject, NSApplicationDelegate {
    private let documentController: MarkdownDocumentController

    override init() {
        // First NSDocumentController subclass instance becomes the shared controller.
        documentController = MarkdownDocumentController()
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = documentController
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
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
