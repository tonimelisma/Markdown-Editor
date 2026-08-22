//
//  MarkdownAccessibilityModel.swift
//  Markdown Editor
//

import AppKit

/// What assistive technology is told about one semantic block.
///
/// // REQ-032/129; ARC-Q23: derived from the *immutable presentation snapshot*, never by reading
/// // live AppKit state during reconciliation, so a stale snapshot describes nothing rather than
/// // describing the wrong document.
nonisolated struct MarkdownAccessibilityDescriptor: Sendable, Equatable {
    let role: NSAccessibility.Role
    /// What the construct *is*. Never the document's text — see `announcedText`.
    let roleDescription: String
    /// Heading level, or list nesting depth, or block-quote depth. `nil` where the construct has
    /// no natural level.
    let level: Int?
    /// Checkbox state for a task item; `nil` for everything else.
    let checked: Bool?
    /// True when the element groups other elements rather than carrying text itself.
    let isContainer: Bool
}

nonisolated enum MarkdownAccessibilityModel {

    /// macOS does not vend a `heading` constant on `NSAccessibility.Role`; `AXHeading` is the
    /// accessibility role string used for headings, and `NSAccessibility.Role` is
    /// `RawRepresentable` precisely so a role the framework has no constant for can still be
    /// named exactly rather than approximated as `.staticText`.
    static let headingRole = NSAccessibility.Role(rawValue: "AXHeading")

    /// The closed role matrix.
    ///
    /// The `switch` is exhaustive with no `default`, so adding a `PresentationBlockKind` fails to
    /// compile here until its accessibility behaviour is declared. That compile failure *is* the
    /// coverage guarantee — a hand-written list of examples in a test would silently omit the new
    /// case, which is the failure mode `CLAUDE.md` §3 records for closed sets.
    static func descriptor(for kind: PresentationBlockKind) -> MarkdownAccessibilityDescriptor {
        switch kind {
        case .paragraph:
            return .init(role: .staticText, roleDescription: "paragraph", level: nil, checked: nil, isContainer: false)

        case .heading(let level):
            return .init(role: Self.headingRole, roleDescription: "heading level \(level)", level: level, checked: nil, isContainer: false)

        case .listItem(let listKind, let nesting, let task):
            if task {
                // A task item is operable, so it is a checkbox rather than a list item. Its
                // checked state is filled in by `descriptor(for:isChecked:)`.
                return .init(role: .checkBox, roleDescription: "task", level: nesting, checked: false, isContainer: false)
            }
            let description: String
            switch listKind {
            case .bullet: description = "bullet list item"
            case .ordered: description = "numbered list item"
            }
            return .init(role: .staticText, roleDescription: description, level: nesting, checked: nil, isContainer: false)

        case .blockQuote(let depth):
            return .init(role: .group, roleDescription: "block quote", level: depth, checked: nil, isContainer: true)

        case .codeBlock(let languageHintPresent):
            return .init(
                role: .staticText,
                roleDescription: languageHintPresent ? "code block with language" : "code block",
                level: nil, checked: nil, isContainer: false
            )

        case .table:
            return .init(role: .table, roleDescription: "table", level: nil, checked: nil, isContainer: true)

        case .tableRow(let header):
            return .init(role: .row, roleDescription: header ? "table header row" : "table row", level: nil, checked: nil, isContainer: true)

        case .tableCell(_, let header):
            return .init(role: .cell, roleDescription: header ? "table header cell" : "table cell", level: nil, checked: nil, isContainer: false)

        case .thematicBreak:
            // Content, not decoration: `---` is a construct the reader is meant to perceive, and
            // it is invisible to a reader who cannot see the rule (see COR-81 contrast research).
            return .init(role: .splitter, roleDescription: "thematic break", level: nil, checked: nil, isContainer: false)

        case .image:
            return .init(role: .image, roleDescription: "image", level: nil, checked: nil, isContainer: false)

        case .literalHTML:
            return .init(role: .staticText, roleDescription: "literal HTML", level: nil, checked: nil, isContainer: false)
        }
    }

    static func descriptor(for kind: PresentationBlockKind, isChecked: Bool) -> MarkdownAccessibilityDescriptor {
        let base = descriptor(for: kind)
        guard base.role == .checkBox else { return base }
        return .init(
            role: base.role,
            roleDescription: base.roleDescription,
            level: base.level,
            checked: isChecked,
            isContainer: base.isContainer
        )
    }
}
