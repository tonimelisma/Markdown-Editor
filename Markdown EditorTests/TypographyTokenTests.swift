//
//  TypographyTokenTests.swift
//  Markdown EditorTests
//

import AppKit
import Foundation
import Testing
@testable import Markdown_Editor

@MainActor
struct TypographyTokenTests {
    @Test func approvedTypographyTokensAreStable() {
        #expect(MarkdownTypography.bodyPointSize == 15)
        #expect(MarkdownTypography.lineHeightMultiple == 1.35)
        #expect(MarkdownTypography.maximumReadingMeasure == 720)
        #expect(MarkdownTypography.minimumHorizontalInset == 28)
        #expect(MarkdownTypography.minimumVerticalInset == 20)
        #expect(MarkdownTypography.paragraphSpacingEm == 0.7)
        #expect(MarkdownTypography.listIndent == 24)
        #expect(MarkdownTypography.headingPointSizes == [30, 24, 20, 17, 15, 13])
        // Not a VISION-approved figure like the others, but a visual token all the same: it was a
        // bare 0.18 at three sites until COR-92 named it, and an unpinned token can drift silently.
        #expect(MarkdownTypography.codeBackgroundAlpha == 0.18)
    }

    @Test func typographyUsesAdaptiveSystemValues() {
        let typography = MarkdownTypography()
        #expect(typography.bodyFont.familyName != nil)
        #expect(typography.monoFont.isFixedPitch)
        #expect(typography.paragraphStyle().lineHeightMultiple == 1.35)
        #expect(typography.paragraphStyle().paragraphSpacing == 10.5)
    }
}
