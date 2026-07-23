//
//  MarkdownTheme.swift
//  Markdown Editor
//

import AppKit

// REQ-041/042/043: maps a TokenStyle to display attributes. Uses system colors so it adapts
// to Light/Dark automatically (REQ-022). Applied on the main actor (ADR-0010).
@MainActor
struct MarkdownTheme {
    var baseFontSize: CGFloat = 14

    var baseFont: NSFont { .systemFont(ofSize: baseFontSize) }
    var monoFont: NSFont { .monospacedSystemFont(ofSize: baseFontSize, weight: .regular) }

    // Base attributes reset onto the whole document before per-token styling.
    var baseAttributes: [NSAttributedString.Key: Any] {
        [.font: baseFont, .foregroundColor: NSColor.labelColor]
    }

    func attributes(for style: TokenStyle) -> [NSAttributedString.Key: Any] {
        switch style {
        case .heading(let level):
            let bump = CGFloat(max(0, 7 - level)) * 2
            return [.font: NSFont.systemFont(ofSize: baseFontSize + bump, weight: .bold),
                    .foregroundColor: NSColor.labelColor]
        case .bold:
            return [.font: NSFont.systemFont(ofSize: baseFontSize, weight: .bold)]
        case .italic:
            return [.font: NSFontManager.shared.convert(baseFont, toHaveTrait: .italicFontMask)]
        case .inlineCode, .table:
            return [.font: monoFont, .foregroundColor: NSColor.systemPurple]
        case .codeBlock:
            return [.font: monoFont,
                    .foregroundColor: NSColor.systemPurple,
                    .backgroundColor: NSColor.systemPurple.withAlphaComponent(0.10)]
        case .link, .image:
            return [.foregroundColor: NSColor.linkColor]
        case .listMarker, .taskMarker, .thematicBreak, .blockquote:
            return [.foregroundColor: NSColor.secondaryLabelColor]
        case .strikethrough:
            return [.strikethroughStyle: NSUnderlineStyle.single.rawValue,
                    .foregroundColor: NSColor.secondaryLabelColor]
        case .highlight:
            return [.backgroundColor: NSColor.systemYellow.withAlphaComponent(0.3)]
        case .footnote:
            return [.foregroundColor: NSColor.systemTeal]
        case .superscript:
            return [.superscript: 1]
        case .subscriptStyle:
            return [.superscript: -1]
        }
    }
}
