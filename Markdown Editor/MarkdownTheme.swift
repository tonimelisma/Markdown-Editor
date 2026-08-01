//
//  MarkdownTheme.swift
//  Markdown Editor
//

import AppKit

/// Compatibility facade for source-mode highlighting and older call sites. Approved WYSIWYG
/// tokens live only in `MarkdownTypography`.
@MainActor
struct MarkdownTheme {
    private let typography = MarkdownTypography()

    var baseFontSize: CGFloat { MarkdownTypography.bodyPointSize }
    var baseFont: NSFont { typography.bodyFont }
    var monoFont: NSFont { typography.monoFont }

    var baseAttributes: [NSAttributedString.Key: Any] {
        [
            .font: typography.bodyFont,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: typography.paragraphStyle()
        ]
    }

    func attributes(for style: TokenStyle) -> [NSAttributedString.Key: Any] {
        switch style {
        case .heading(let level):
            return [.font: typography.font(for: level), .foregroundColor: NSColor.labelColor]
        case .bold:
            return [.font: NSFont.systemFont(ofSize: baseFontSize, weight: .bold)]
        case .italic:
            return [.font: NSFontManager.shared.convert(baseFont, toHaveTrait: .italicFontMask)]
        case .inlineCode, .table:
            return [.font: typography.inlineCodeFont(), .foregroundColor: NSColor.secondaryLabelColor]
        case .codeBlock:
            return [
                .font: typography.monoFont,
                .foregroundColor: NSColor.labelColor,
                .backgroundColor: NSColor.quaternaryLabelColor.withAlphaComponent(0.18)
            ]
        case .link, .image:
            return [.foregroundColor: NSColor.linkColor]
        case .listMarker, .taskMarker, .thematicBreak, .blockquote:
            return [.foregroundColor: NSColor.secondaryLabelColor]
        case .strikethrough:
            return [.strikethroughStyle: NSUnderlineStyle.single.rawValue,
                    .foregroundColor: NSColor.secondaryLabelColor]
        }
    }
}
