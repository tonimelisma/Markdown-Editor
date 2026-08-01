//
//  MarkdownTypography.swift
//  Markdown Editor
//

import AppKit

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
    nonisolated static let quoteRuleWidth: CGFloat = 3
    nonisolated static let quoteInset: CGFloat = 17
    nonisolated static let inlineCodeScale: CGFloat = 0.93
    nonisolated static let codeBlockPadding: CGFloat = 12
    nonisolated static let separatorHeight: CGFloat = 14

    nonisolated static let headingPointSizes: [CGFloat] = [30, 24, 20, 17, 15, 13]

    var bodyFont: NSFont { .systemFont(ofSize: Self.bodyPointSize, weight: .regular) }
    var monoFont: NSFont { .monospacedSystemFont(ofSize: Self.bodyPointSize, weight: .regular) }

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
}
