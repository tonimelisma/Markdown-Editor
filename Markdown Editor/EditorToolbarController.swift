//
//  EditorToolbarController.swift
//  Markdown Editor
//

import AppKit
import Combine

/// Native per-window toolbar presentation of `EditorCommandController`.
@MainActor
final class EditorToolbarController: NSObject, NSToolbarDelegate, ObservableObject {
    weak var commandController: EditorCommandController?

    static let toolbarIdentifier = NSToolbar.Identifier("MarkdownEditor.toolbar")
    static let modeIdentifier = NSToolbarItem.Identifier("MarkdownEditor.mode")
    static let paragraphIdentifier = NSToolbarItem.Identifier("MarkdownEditor.paragraph")
    static let boldIdentifier = NSToolbarItem.Identifier("MarkdownEditor.bold")
    static let italicIdentifier = NSToolbarItem.Identifier("MarkdownEditor.italic")
    static let linkIdentifier = NSToolbarItem.Identifier("MarkdownEditor.link")
    static let structureIdentifier = NSToolbarItem.Identifier("MarkdownEditor.structure")
    static let addImageIdentifier = NSToolbarItem.Identifier("MarkdownEditor.addImage")
    /// Commands the default item set can invoke. The mode item is one segmented control, so it
    /// carries both mode commands.
    static let defaultCommands: [EditorCommand] = [
        .wysiwygMode, .sourceMode, .paragraph, .bold, .italic, .editLink, .unorderedList, .addImage
    ]

    func install(on window: NSWindow) {
        if window.toolbar?.identifier == Self.toolbarIdentifier { return }
        let toolbar = NSToolbar(identifier: Self.toolbarIdentifier)
        toolbar.delegate = self
        toolbar.allowsUserCustomization = true
        toolbar.autosavesConfiguration = true
        toolbar.displayMode = .default
        window.toolbar = toolbar
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            Self.modeIdentifier, Self.paragraphIdentifier, Self.boldIdentifier,
            Self.italicIdentifier, Self.linkIdentifier, Self.structureIdentifier,
            Self.addImageIdentifier, .flexibleSpace, .space
        ]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            Self.modeIdentifier, Self.paragraphIdentifier, Self.boldIdentifier,
            Self.italicIdentifier, Self.linkIdentifier, Self.structureIdentifier,
            .flexibleSpace, Self.addImageIdentifier
        ]
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch itemIdentifier {
        case Self.modeIdentifier:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            let segmented = NSSegmentedControl(labels: ["WYSIWYG", "Source"], trackingMode: .selectOne, target: self, action: #selector(modeChanged(_:)))
            segmented.selectedSegment = commandController?.session?.mode == .source ? 1 : 0
            segmented.setAccessibilityLabel("Editor mode")
            segmented.setAccessibilityHelp("Choose WYSIWYG or Source mode")
            item.view = segmented
            item.label = "Mode"
            item.paletteLabel = "Editor Mode"
            return item
        case Self.paragraphIdentifier:
            return menuItem(itemIdentifier, label: "Paragraph", command: .paragraph, menu: paragraphMenu())
        case Self.boldIdentifier:
            return menuItem(itemIdentifier, label: "Bold", command: .bold)
        case Self.italicIdentifier:
            return menuItem(itemIdentifier, label: "Italic", command: .italic)
        case Self.linkIdentifier:
            return menuItem(itemIdentifier, label: "Link", command: .editLink)
        case Self.structureIdentifier:
            return menuItem(itemIdentifier, label: "Structure", command: .unorderedList, menu: structureMenu())
        case Self.addImageIdentifier:
            return menuItem(itemIdentifier, label: "Add Image…", command: .addImage)
        default:
            return nil
        }
    }

    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        command(for: item.tag).map { commandController?.availability(for: $0).isEnabled ?? false } ?? true
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        command(for: menuItem.tag).map { commandController?.availability(for: $0).isEnabled ?? false } ?? true
    }

    private func menuItem(
        _ id: NSToolbarItem.Identifier,
        label: String,
        command: EditorCommand,
        menu: NSMenu? = nil
    ) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: id)
        item.label = label
        item.paletteLabel = label
        item.toolTip = label
        item.target = self
        item.action = #selector(commandInvoked(_:))
        item.tag = EditorCommand.allCases.firstIndex(of: command) ?? 0
        item.menuFormRepresentation = NSMenuItem(title: label, action: #selector(commandInvoked(_:)), keyEquivalent: "")
        item.menuFormRepresentation?.target = self
        item.menuFormRepresentation?.tag = item.tag
        item.menuFormRepresentation?.submenu = menu
        return item
    }

    private func paragraphMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(commandMenuItem("Paragraph", .paragraph))
        for level in 1...6 { menu.addItem(commandMenuItem("Heading \(level)", .heading(level))) }
        return menu
    }

    private func structureMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(commandMenuItem("Bulleted List", .unorderedList))
        menu.addItem(commandMenuItem("Numbered List", .orderedList))
        menu.addItem(commandMenuItem("Task List", .taskList))
        menu.addItem(commandMenuItem("Block Quote", .blockQuote))
        menu.addItem(commandMenuItem("Code Block", .codeBlock))
        return menu
    }

    private func commandMenuItem(_ title: String, _ command: EditorCommand) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(commandInvoked(_:)), keyEquivalent: "")
        item.target = self
        item.tag = EditorCommand.allCases.firstIndex(of: command) ?? 0
        return item
    }

    @objc private func commandInvoked(_ sender: Any?) {
        let tag: Int?
        if let item = sender as? NSMenuItem {
            tag = item.tag
        } else if let item = sender as? NSToolbarItem {
            tag = item.tag
        } else {
            tag = nil
        }
        guard let tag, tag >= 0, tag < EditorCommand.allCases.count else { return }
        _ = commandController?.perform(EditorCommand.allCases[tag])
    }

    @objc private func modeChanged(_ sender: NSSegmentedControl) {
        _ = commandController?.perform(sender.selectedSegment == 1 ? .sourceMode : .wysiwygMode)
    }

    private func command(for tag: Int) -> EditorCommand? {
        guard tag >= 0, tag < EditorCommand.allCases.count else { return nil }
        return EditorCommand.allCases[tag]
    }
}
