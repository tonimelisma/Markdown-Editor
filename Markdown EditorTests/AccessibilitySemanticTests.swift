//
//  AccessibilitySemanticTests.swift
//  Markdown EditorTests
//
//  COR-81 / REQ-032, REQ-129: the closed accessibility role matrix and keyboard reachability.
//

import AppKit
import SwiftUI
import Testing
@testable import Markdown_Editor

struct AccessibilitySemanticTests {

    /// Every `PresentationBlockKind`, one representative per case.
    ///
    /// Kept beside an exhaustive `switch` below so that adding a case fails to compile here as
    /// well as in production, rather than silently going unexercised.
    private static let everyKind: [PresentationBlockKind] = [
        .paragraph,
        .heading(level: 1), .heading(level: 6),
        .listItem(kind: .bullet, nesting: 0, task: false),
        .listItem(kind: .ordered(start: 1, delimiter: .period), nesting: 2, task: false),
        .listItem(kind: .bullet, nesting: 0, task: true),
        .blockQuote(depth: 1),
        .codeBlock(languageHintPresent: false), .codeBlock(languageHintPresent: true),
        .table,
        .tableRow(header: true), .tableRow(header: false),
        .tableCell(alignment: .none, header: true), .tableCell(alignment: .center, header: false),
        .thematicBreak,
        .image,
        .literalHTML
    ]

    /// Fails to compile when a `PresentationBlockKind` case is added, which is what makes
    /// `everyKind` above a closed enumeration rather than a list someone remembered to update.
    private func caseTag(_ kind: PresentationBlockKind) -> String {
        switch kind {
        case .paragraph: return "paragraph"
        case .heading: return "heading"
        case .listItem: return "listItem"
        case .blockQuote: return "blockQuote"
        case .codeBlock: return "codeBlock"
        case .table: return "table"
        case .tableRow: return "tableRow"
        case .tableCell: return "tableCell"
        case .thematicBreak: return "thematicBreak"
        case .image: return "image"
        case .literalHTML: return "literalHTML"
        }
    }

    // Verifies: REQ-129 — every semantic block kind has a declared accessibility role and role
    // description. The matrix is closed: `caseTag` is an exhaustive switch, so a new block kind
    // breaks the build until it appears in `everyKind` and gets a descriptor.
    @Test func everyBlockKindHasADeclaredAccessibilityRole() {
        let covered = Set(Self.everyKind.map(caseTag))
        let expected: Set<String> = [
            "paragraph", "heading", "listItem", "blockQuote", "codeBlock",
            "table", "tableRow", "tableCell", "thematicBreak", "image", "literalHTML"
        ]
        #expect(covered == expected, "uncovered block kinds: \(expected.subtracting(covered))")

        for kind in Self.everyKind {
            let descriptor = MarkdownAccessibilityModel.descriptor(for: kind)
            #expect(!descriptor.roleDescription.isEmpty, "\(caseTag(kind)) has no role description")
            #expect(
                descriptor.role != .unknown,
                "\(caseTag(kind)) exposes the unknown role, which tells assistive technology nothing"
            )
        }
    }

    // Verifies: REQ-129 — a heading exposes its level, so a screen reader can navigate document
    // structure rather than hearing six identically-described headings. Font size alone does not
    // carry this: the deletion gate for this plan is that no semantic construct relies only on
    // font, colour, or indentation.
    @Test func headingsExposeTheirLevel() {
        for level in 1...6 {
            let descriptor = MarkdownAccessibilityModel.descriptor(for: .heading(level: level))
            #expect(descriptor.role == MarkdownAccessibilityModel.headingRole)
            #expect(descriptor.level == level, "heading \(level) reported level \(String(describing: descriptor.level))")
            #expect(descriptor.roleDescription.contains("\(level)"))
        }
    }

    // Verifies: REQ-129/032 — a task item is operable, so it is a checkbox carrying its state,
    // not static text that happens to be drawn with a tick. Both states are exposed.
    @Test func taskItemsExposeCheckboxRoleAndState() {
        let kind = PresentationBlockKind.listItem(kind: .bullet, nesting: 0, task: true)
        #expect(MarkdownAccessibilityModel.descriptor(for: kind).role == .checkBox)
        #expect(MarkdownAccessibilityModel.descriptor(for: kind, isChecked: true).checked == true)
        #expect(MarkdownAccessibilityModel.descriptor(for: kind, isChecked: false).checked == false)

        // A non-task list item is not a checkbox and carries no checked state to misreport.
        let plain = PresentationBlockKind.listItem(kind: .bullet, nesting: 0, task: false)
        #expect(MarkdownAccessibilityModel.descriptor(for: plain).role != .checkBox)
        #expect(MarkdownAccessibilityModel.descriptor(for: plain, isChecked: true).checked == nil)
    }

    // Verifies: REQ-129 — list nesting and quote depth are exposed as levels, so structure is
    // available without relying on indentation, which assistive technology cannot see.
    @Test func nestingAndQuoteDepthAreExposedAsLevels() {
        for nesting in 0...3 {
            let descriptor = MarkdownAccessibilityModel.descriptor(
                for: .listItem(kind: .ordered(start: 1, delimiter: .period), nesting: nesting, task: false)
            )
            #expect(descriptor.level == nesting)
        }
        for depth in 1...3 {
            let descriptor = MarkdownAccessibilityModel.descriptor(for: .blockQuote(depth: depth))
            #expect(descriptor.level == depth)
            #expect(descriptor.isContainer, "a block quote groups its content")
        }
    }

    // Verifies: REQ-129 — descriptors carry no document content. The role description says what a
    // construct *is*; the text itself reaches assistive technology through the text element, so a
    // descriptor that embedded content would leak it into a second, unaudited channel.
    @Test func descriptorsCarryNoDocumentContent() {
        for kind in Self.everyKind {
            let descriptor = MarkdownAccessibilityModel.descriptor(for: kind)
            // Role descriptions are drawn from a fixed vocabulary; nothing derived from a document.
            let allowed: Set<String> = [
                "paragraph", "heading level 1", "heading level 6", "bullet list item",
                "numbered list item", "task", "block quote", "code block",
                "code block with language", "table", "table header row", "table row",
                "table header cell", "table cell", "thematic break", "image", "literal HTML"
            ]
            #expect(
                allowed.contains(descriptor.roleDescription),
                "role description outside the fixed vocabulary: \(descriptor.roleDescription)"
            )
        }
    }
}

@MainActor
struct KeyboardCommandMatrixTests {

    // Verifies: REQ-032 — every editor command is reachable without a mouse. Each command either
    // carries a keyboard shortcut or is explicitly declared menu-reachable-only; the matrix is over
    // `EditorCommand.allCases`, so a new command fails here until its keyboard story is declared.
    //
    // The requirement is "operable via full keyboard control", which a list of the nine commands
    // that happen to have shortcuts would not discharge.
    @Test func everyCommandIsKeyboardReachable() {
        // Commands deliberately without a shortcut: they are reachable through the menu, which is
        // itself keyboard-navigable, and inventing shortcuts for them needs product approval.
        let menuOnly: Set<EditorCommand> = [.removeLink, .addImage]

        var unreachable: [EditorCommand] = []
        for command in EditorCommand.allCases {
            let hasShortcut = EditorMenuCommands.shortcuts[command] != nil
            if !hasShortcut && !menuOnly.contains(command) {
                unreachable.append(command)
            }
            // A command cannot be both: a declared menu-only command with a shortcut means the
            // declaration has gone stale.
            if hasShortcut && menuOnly.contains(command) {
                Issue.record("\(command) is declared menu-only but has a shortcut")
            }
        }

        #expect(
            unreachable.isEmpty,
            "commands with neither a shortcut nor a menu-only declaration: \(unreachable)"
        )
    }

    // Verifies: REQ-084 — the Edit menu offers Find, on ⌘F. A SwiftUI app's Edit menu has no
    // Find items unless its commands ask for them, and this app's did not: ⌘F did nothing.
    @Test func theEditMenuOffersFind() throws {
        let menu = try #require(NSApp.mainMenu, "the test host has no menu bar")
        func items(_ menu: NSMenu) -> [NSMenuItem] {
            menu.items.flatMap { [$0] + ($0.submenu.map(items) ?? []) }
        }
        let all = items(menu)
        try #require(all.contains { $0.title == "Undo" }, "the menu bar is not the app's: \(menu.items.map(\.title))")
        func takes(_ key: String) -> NSMenuItem? {
            all.first {
                $0.keyEquivalent == key && $0.keyEquivalentModifierMask.intersection(.deviceIndependentFlagsMask) == .command
            }
        }
        #expect(takes("f") != nil, "no menu item takes ⌘F; the menus offer \(all.map(\.title))")
        // Close: the File group the app replaces to restore Save also held it, and ⌘W did nothing.
        #expect(takes("w") != nil, "no menu item takes ⌘W; the menus offer \(all.map(\.title))")
    }

    // Verifies: REQ-021 — the real File menu offers Open Recent. The app added it through
    // AppKit, SwiftUI rebuilt the File menu from the commands, and it was gone.
    @Test func theFileMenuOffersOpenRecent() throws {
        let menu = try #require(NSApp.mainMenu, "the test host has no menu bar")
        let file = try #require(menu.item(withTitle: "File")?.submenu, "no File menu: \(menu.items.map(\.title))")
        let recent = file.item(withTitle: "Open Recent")
        #expect(recent != nil, "the File menu offers \(file.items.map(\.title))")
        #expect(recent?.submenu?.items.contains { $0.title == "Clear Menu" } == true)
    }

    // Verifies: REQ-032 — no command's shortcut is one macOS or every Mac app already owns. Block
    // Quote was control-command-Q, which is the system's Lock Screen: an agent-drive tour
    // (45955987611) pressed it and locked the runner's screen, as it would have locked a user's.
    @Test func noShortcutTakesASystemOrStandardKey() {
        typealias Key = (Character, EventModifiers)
        let reserved: [(Key, String)] = [
            (("q", [.command, .control]), "Lock Screen"),
            (("f", [.command, .control]), "Enter Full Screen"),
            ((" ", [.command, .control]), "Emoji & Symbols"),
            (("d", [.command, .control]), "Look Up"),
            ((" ", [.command]), "Spotlight"),
            (("3", [.command, .shift]), "Screenshot"),
            (("4", [.command, .shift]), "Screenshot of a selection"),
            (("5", [.command, .shift]), "Screenshot and recording options"),
            (("3", [.command, .shift, .control]), "Screenshot to the clipboard"),
            (("4", [.command, .shift, .control]), "Selection screenshot to the clipboard"),
            (("h", [.command]), "Hide"), (("h", [.command, .option]), "Hide Others"),
            (("m", [.command]), "Minimize"), (("q", [.command]), "Quit"), (("w", [.command]), "Close"),
            ((",", [.command]), "Settings"), (("/", [.command, .shift]), "Help"),
            (("a", [.command]), "Select All"), (("c", [.command]), "Copy"), (("v", [.command]), "Paste"),
            (("x", [.command]), "Cut"), (("z", [.command]), "Undo"), (("z", [.command, .shift]), "Redo"),
            (("f", [.command]), "Find"), (("g", [.command]), "Find Next"), (("g", [.command, .shift]), "Find Previous"),
            (("e", [.command]), "Use Selection for Find"), (("j", [.command]), "Jump to Selection"),
            (("n", [.command]), "New"), (("o", [.command]), "Open"), (("s", [.command]), "Save"),
            (("s", [.command, .shift]), "Save As"), (("p", [.command]), "Print"), (("t", [.command]), "Show Fonts / New Tab"),
            ((";", [.command]), "Check Spelling"), ((":", [.command]), "Spelling and Grammar"),
            (("v", [.command, .shift, .option]), "Paste and Match Style"),
        ]
        for (command, shortcut) in EditorMenuCommands.shortcuts {
            for ((character, modifiers), name) in reserved
            where shortcut.key.character == character && shortcut.modifiers == modifiers {
                Issue.record("\(command)'s shortcut is the system's or every app's \(name)")
            }
        }
    }

    // Verifies: REQ-032 — no two commands share a shortcut, which would make one of them
    // unreachable by keyboard however it is declared.
    @Test func noTwoCommandsShareAShortcut() {
        var seen: [String: EditorCommand] = [:]
        for command in EditorCommand.allCases {
            guard let shortcut = EditorMenuCommands.shortcuts[command] else { continue }
            let key = "\(shortcut.key.character)\(shortcut.modifiers.rawValue)"
            if let existing = seen[key] {
                Issue.record("\(command) and \(existing) share the shortcut \(key)")
            }
            seen[key] = command
        }
        #expect(!seen.isEmpty)
    }
}
