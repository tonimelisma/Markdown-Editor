//
//  EditorColorCatalog.swift
//  Markdown Editor
//

import AppKit

/// The one place production resolves a colour.
///
/// // REQ-139/141; ARC-Q21: every colour the editor paints is a *declared semantic role* backed by
/// // an appearance-and-contrast-aware AppKit system colour. Two things follow, and both are the
/// // point of the type existing rather than calling `NSColor.labelColor` at twenty sites:
/// //
/// // - Contrast can be *measured*. `ContrastConformanceTests` enumerates `allCases`, resolves each
/// //   role in Aqua, DarkAqua and Increase Contrast, and computes the WCAG 2.1 ratio against the
/// //   background it is actually drawn on. A role that cannot be enumerated cannot be measured.
/// // - A new colour literal is detectable. `DisplayPreferencePolicyTests` fails when production
/// //   names an `NSColor` outside this file, so "just this once" has somewhere to fail.
/// //
/// // Deliberately not a theme system. These are system colours, so Increase Contrast, Dark Mode
/// // and accent-colour changes are honoured by AppKit rather than reimplemented here.
nonisolated enum EditorColorRole: String, CaseIterable, Sendable {
    /// Ordinary body text and headings.
    case primaryText
    /// Block-quote text, table header text, list markers, and other de-emphasised content.
    ///
    /// Not `secondaryLabelColor`: that measures 3.95:1 against the window in Light, below the
    /// 4.5:1 bound for normal text, and it carries running block-quote prose. See COR-85.
    case secondaryText
    /// Link and image reference text.
    case link
    /// Code-block and inline-code backgrounds, and the task checkbox fill.
    case codeBackground
    /// Thematic breaks, table borders, and the block-quote bar.
    ///
    /// Named for what it draws rather than for `NSColor.separatorColor`, because all three are
    /// **content**: a thematic break is the rendering of `---`, a construct the reader is meant to
    /// perceive, and table borders carry the table's structure. `separatorColor` is designed as a
    /// decorative hairline and measures 1.25:1 in Light — invisible to many readers. See COR-85.
    case structuralRule
    /// The checked task checkbox mark.
    case accent

    /// Whether this role is used for text. Non-text roles are UI components under WCAG and carry
    /// the 3:1 bound rather than 4.5:1.
    var isTextRole: Bool {
        switch self {
        case .primaryText, .secondaryText, .link: return true
        case .codeBackground, .structuralRule, .accent: return false
        }
    }
}

@MainActor
enum EditorColorCatalog {
    static func color(_ role: EditorColorRole) -> NSColor {
        switch role {
        case .primaryText: return .labelColor
        // Measured: 5.74:1 Light, 6.77:1 Dark — clears the 4.5:1 text bound with margin while
        // staying clearly de-emphasised against full `labelColor` at 14.94:1. `secondaryLabelColor`
        // was 3.95:1 in Light. Alpha over the window background, so appearance still resolves it.
        case .secondaryText: return NSColor.labelColor.withAlphaComponent(0.6)
        case .link: return .linkColor
        case .codeBackground: return .quaternaryLabelColor
        // Measured: 3.26:1 Light, 5.81:1 Dark — clears the 3:1 component bound in both.
        case .structuralRule: return .systemGray
        case .accent: return .controlAccentColor
        }
    }

    /// The surface a role is drawn on. Text is measured against the window background; the code
    /// background is itself drawn on the window background.
    static var windowBackground: NSColor { .textBackgroundColor }
}
