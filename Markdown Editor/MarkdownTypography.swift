//
//  MarkdownTypography.swift
//  Markdown Editor
//

import AppKit

final class QuoteTextBlock: NSTextBlock {}
final class CodeTextBlock: NSTextBlock {}

/// The single source of truth for the approved native reading typography.
///
/// // REQ-105/107; ARC-018/ARC-Q14/ARC-Q15: semantic builders consume these tokens rather than
/// embedding independent font, spacing, or measure constants.
@MainActor
struct MarkdownTypography {
    nonisolated static let bodyPointSize: CGFloat = 15
    nonisolated static let lineHeightMultiple: CGFloat = 1.35
    nonisolated static let maximumReadingMeasure: CGFloat = 720
    nonisolated static let minimumHorizontalInset: CGFloat = 28
    nonisolated static let minimumVerticalInset: CGFloat = 20
    nonisolated static let paragraphSpacingEm: CGFloat = 0.7
    nonisolated static let listIndent: CGFloat = 24
    nonisolated static let listMarkerGlyphs = ["•", "◦", "▪"]
    nonisolated static let quoteRuleWidth: CGFloat = 3
    nonisolated static let inlineCodeScale: CGFloat = 0.93
    nonisolated static let codeBlockPadding: CGFloat = 12
    nonisolated static let separatorHeight: CGFloat = 14

    nonisolated static let headingPointSizes: [CGFloat] = [30, 24, 20, 17, 15, 13]
    /// Heading spacing in em of the effective heading size, H1…H6. More before than after, so a heading
    /// binds to the content it introduces.
    nonisolated static let headingSpacingBeforeEm: [CGFloat] = [1.0, 0.9, 0.8, 0.7, 0.6, 0.5]
    nonisolated static let headingSpacingAfterEm: [CGFloat] = [0.35, 0.3, 0.3, 0.25, 0.25, 0.25]
    /// Spacing after a non-paragraph block (list item, quote line, image, code block).
    nonisolated static let blockSpacingEm: CGFloat = 0.35
    /// Left padding inside the blockquote rule. Rule plus padding is the content inset.
    nonisolated static let quoteRulePadding: CGFloat = 14

    var bodyFont: NSFont { .systemFont(ofSize: Self.bodyPointSize, weight: .regular) }
    var monoFont: NSFont { .monospacedSystemFont(ofSize: Self.bodyPointSize, weight: .regular) }
    var baseFontSize: CGFloat { Self.bodyPointSize }
    var baseFont: NSFont { bodyFont }

    var baseAttributes: [NSAttributedString.Key: Any] {
        [.font: bodyFont, .foregroundColor: EditorColorCatalog.color(.primaryText), .paragraphStyle: paragraphStyle()]
    }

    func attributes(for style: TokenStyle) -> [NSAttributedString.Key: Any] {
        switch style {
        case .heading(let level): return [.font: font(for: level), .foregroundColor: EditorColorCatalog.color(.primaryText)]
        case .bold: return [.font: NSFont.systemFont(ofSize: baseFontSize, weight: .bold)]
        case .italic: return [.font: NSFontManager.shared.convert(baseFont, toHaveTrait: .italicFontMask)]
        case .inlineCode, .table: return [.font: inlineCodeFont(), .foregroundColor: EditorColorCatalog.color(.secondaryText)]
        case .codeBlock: return [.font: monoFont, .foregroundColor: EditorColorCatalog.color(.primaryText),
                                  .backgroundColor: EditorColorCatalog.color(.codeBackground).withAlphaComponent(0.18)]
        case .link, .image: return [.foregroundColor: EditorColorCatalog.color(.link)]
        case .listMarker, .taskMarker, .thematicBreak, .blockquote:
            return [.foregroundColor: EditorColorCatalog.color(.secondaryText)]
        case .strikethrough:
            return [.strikethroughStyle: NSUnderlineStyle.single.rawValue,
                    .foregroundColor: EditorColorCatalog.color(.secondaryText)]
        }
    }

    func font(for headingLevel: Int) -> NSFont {
        let index = max(0, min(headingLevel - 1, Self.headingPointSizes.count - 1))
        return .systemFont(ofSize: Self.headingPointSizes[index], weight: .semibold)
    }

    func inlineCodeFont(for bodySize: CGFloat = Self.bodyPointSize) -> NSFont {
        .monospacedSystemFont(ofSize: bodySize * Self.inlineCodeScale, weight: .regular)
    }

    func paragraphStyle() -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = Self.lineHeightMultiple
        style.paragraphSpacing = Self.bodyPointSize * Self.paragraphSpacingEm
        style.paragraphSpacingBefore = 0
        return style
    }

    func headingSpacing(for level: Int) -> (before: CGFloat, after: CGFloat) {
        let index = max(0, min(level - 1, Self.headingSpacingBeforeEm.count - 1))
        let pointSize = font(for: level).pointSize
        return (
            pointSize * Self.headingSpacingBeforeEm[index],
            pointSize * Self.headingSpacingAfterEm[index]
        )
    }

    var blockSpacing: CGFloat { Self.bodyPointSize * Self.blockSpacingEm }

    /// One nesting level of the blockquote decoration: an adaptive leading rule plus content
    /// padding, expressed as a native `NSTextBlock` so AppKit lays out and draws it.
    func quoteBlock() -> NSTextBlock {
        let block = QuoteTextBlock()
        // Without an explicit content width the block lays out at effectively zero width and
        // wraps one character per line. The screenshot review caught this; attribute-level tests
        // could not, because the border and padding values were correct all along.
        block.setContentWidth(100, type: .percentageValueType)
        block.setWidth(Self.quoteRuleWidth, type: .absoluteValueType, for: .border, edge: .minX)
        block.setWidth(Self.quoteRulePadding, type: .absoluteValueType, for: .padding, edge: .minX)
        block.setBorderColor(EditorColorCatalog.color(.structuralRule), for: .minX)
        return block
    }

    /// The padded adaptive code-block container.
    func codeBlock() -> NSTextBlock {
        let block = CodeTextBlock()
        block.setContentWidth(100, type: .percentageValueType)
        block.setWidth(Self.codeBlockPadding, type: .absoluteValueType, for: .padding)
        block.backgroundColor = EditorColorCatalog.color(.codeBackground).withAlphaComponent(0.18)
        return block
    }
}
