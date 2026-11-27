//
//  EditorMenuCommands.swift
//  Markdown Editor
//

import AppKit
import Combine
import SwiftUI

/// The command controller of the key document window, for the menu bar.
///
/// Document windows are AppKit windows (`MarkdownDocument.makeWindowControllers`), not SwiftUI
/// scenes, and a `@FocusedValue` published from their content never reached these commands: every
/// View and Format item stayed disabled and every formatting shortcut did nothing (agent-drive
/// run 45944610103: "WYSIWYG Mode" disabled with its menu open, cmd-I routed nothing). The window's
/// controller is found the way the smoke scenes find it, through the toolbar delegate the window
/// owns, and republished whenever the key window changes.
@MainActor
final class KeyWindowCommands: ObservableObject {
    static let shared = KeyWindowCommands()

    @Published private(set) var controller: EditorCommandController?
    /// The key window's enabled commands, recomputed after every change to its session's state.
    /// A menu item's `.disabled` is decided when the menu's body is evaluated, and the body was
    /// evaluated when the key window changed: at a window's set-up, before its first parse, when
    /// formatting is unavailable. Cmd-I stayed refused after the document was ready (agent-drive
    /// run 45945859891).
    @Published private(set) var enabled: Set<EditorCommand> = []
    private var observers: [NSObjectProtocol] = []
    private var stateSubscription: AnyCancellable?

    /// `observingKeyWindow` false is for a test: an instance that only its own `refresh` calls
    /// change. The shared one is refreshed by every window's toolbar, in every test running.
    init(observingKeyWindow: Bool = true) {
        guard observingKeyWindow else { return }
        let center = NotificationCenter.default
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }
        observers.append(center.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { [weak self] note in
            let closing = (note.object as AnyObject?).map(ObjectIdentifier.init)
            MainActor.assumeIsolated {
                let key = NSApp.keyWindow
                self?.refresh(keyWindow: key.map(ObjectIdentifier.init) == closing ? nil : key)
            }
        })
    }

    func refresh(keyWindow: NSWindow? = NSApp.keyWindow) {
        let next = Self.controller(of: keyWindow)
        if next !== controller {
            controller = next
            stateSubscription = nil // FALSIFY
            _ = next?.session.map { session in
                session.objectWillChange.map { _ in () }
                    .merge(with: session.commandStateChanges)
                    .receive(on: RunLoop.main)
                    .sink { [weak self] in MainActor.assumeIsolated { self?.recomputeEnabled() } }
            }
        }
        recomputeEnabled()
    }

    func recomputeEnabled() {
        let next = Set(EditorCommand.allCases.filter { controller?.availability(for: $0).isEnabled == true })
        if next != enabled { enabled = next }
    }

    static func controller(of window: NSWindow?) -> EditorCommandController? {
        (window?.toolbar?.delegate as? EditorToolbarController)?.commandController
    }
}

@MainActor
struct EditorMenuCommands: Commands {
    struct Item: Identifiable {
        let title: String
        let command: EditorCommand
        var id: String { title }
    }

    /// Every item the menu bar presents, in order: the View menu's modes, then the Format menu's
    /// sections. Built by one function (`menuButton`), so no item can be written without its
    /// shortcut or its availability. Hand-written buttons had dropped them: of the nineteen
    /// approved shortcuts, the menu carried three.
    static let viewItems: [Item] = [
        Item(title: "WYSIWYG Mode", command: .wysiwygMode),
        Item(title: "Source Mode", command: .sourceMode),
    ]
    static let formatSections: [[Item]] = [
        [
            Item(title: "Bold", command: .bold),
            Item(title: "Italic", command: .italic),
            Item(title: "Strikethrough", command: .strikethrough),
            Item(title: "Inline Code", command: .inlineCode),
            Item(title: "Edit Link…", command: .editLink),
            Item(title: "Remove Link", command: .removeLink),
        ],
        [Item(title: "Paragraph", command: .paragraph)]
            + (1...6).map { Item(title: "Heading \($0)", command: .heading($0)) },
        [
            Item(title: "Bulleted List", command: .unorderedList),
            Item(title: "Numbered List", command: .orderedList),
            Item(title: "Task List", command: .taskList),
            Item(title: "Block Quote", command: .blockQuote),
            Item(title: "Code Block", command: .codeBlock),
            Item(title: "Add Image…", command: .addImage),
        ],
    ]

    /// Every command the menu bar presents. Mode lives in View, formatting in Format, but both
    /// are presentations of the one command model — so this list must cover the toolbar's.
    static var commandOrder: [EditorCommand] {
        (viewItems + formatSections.flatMap { $0 }).map(\.command)
    }

    /// The approved shortcuts. Declared once so menu construction and the conformance test read
    /// the same table, and so an added shortcut cannot silently shadow a standard AppKit key.
    static let shortcuts: [EditorCommand: KeyboardShortcut] = [
        .sourceMode: KeyboardShortcut("2", modifiers: [.command, .control]),
        .wysiwygMode: KeyboardShortcut("1", modifiers: [.command, .control]),
        .paragraph: KeyboardShortcut("0"),
        .heading(1): KeyboardShortcut("1"),
        .heading(2): KeyboardShortcut("2"),
        .heading(3): KeyboardShortcut("3"),
        .heading(4): KeyboardShortcut("4"),
        .heading(5): KeyboardShortcut("5"),
        .heading(6): KeyboardShortcut("6"),
        .bold: KeyboardShortcut("b"),
        .italic: KeyboardShortcut("i"),
        .strikethrough: KeyboardShortcut("x", modifiers: [.command, .shift]),
        .inlineCode: KeyboardShortcut("c", modifiers: [.command, .control]),
        .editLink: KeyboardShortcut("k"),
        .unorderedList: KeyboardShortcut("7", modifiers: [.command, .shift]),
        .orderedList: KeyboardShortcut("8", modifiers: [.command, .shift]),
        .taskList: KeyboardShortcut("9", modifiers: [.command, .shift]),
        .blockQuote: KeyboardShortcut("q", modifiers: [.command, .control]),
        .codeBlock: KeyboardShortcut("c", modifiers: [.command, .control, .shift])
    ]

    @ObservedObject private var keyWindow = KeyWindowCommands.shared

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            ForEach(Self.viewItems) { menuButton($0) }
            Divider()
        }
        CommandMenu("Format") {
            ForEach(Self.formatSections.indices, id: \.self) { index in
                if index > 0 { Divider() }
                ForEach(Self.formatSections[index]) { menuButton($0) }
            }
        }
    }

    private func isEnabled(_ command: EditorCommand) -> Bool {
        keyWindow.enabled.contains(command)
    }

    @ViewBuilder
    private func menuButton(_ item: Item) -> some View {
        let controller = keyWindow.controller
        let button = Button(item.title) { _ = controller?.perform(item.command) }
            .disabled(!isEnabled(item.command))
        if let shortcut = Self.shortcuts[item.command] {
            button.keyboardShortcut(shortcut)
        } else {
            button
        }
    }
}
