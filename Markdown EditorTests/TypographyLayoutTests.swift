//
//  TypographyLayoutTests.swift
//  Markdown EditorTests
//

import AppKit
import Foundation
import Testing
@testable import Markdown_Editor

@MainActor
struct TypographyLayoutTests {
    @Test func readingColumnUsesMinimumInsetsAndMaximumMeasure() {
        let textView = MarkdownWYSIWYGTextView(frame: NSRect(x: 0, y: 0, width: 1_200, height: 600))
        textView.layout()
        #expect(textView.textContainerInset.width == 240)
        #expect(textView.textContainerInset.height == 20)
        #expect(textView.textContainer?.containerSize.width == 720)

        textView.setFrameSize(NSSize(width: 400, height: 600))
        textView.layout()
        #expect(textView.textContainerInset.width == 28)
        #expect(textView.textContainer?.containerSize.width == 344)
    }

    // Verifies: REQ-107 — the quote has a real 3 pt leading rule and content inset, so color is
    // not its only distinction.
    @Test func blockQuoteUsesLeadingRuleAndContentInset() throws {
        let built = try build("> Quoted line\n")
        let quote = try #require(model(for: "> Quoted line\n").blocks.first {
            if case .blockQuote = $0.kind { return true }
            return false
        })
        let style = try #require(
            built.attributed.attribute(.paragraphStyle, at: quote.projectionRange.location, effectiveRange: nil) as? NSParagraphStyle
        )
        let block = try #require(style.textBlocks.first)
        #expect(block.width(for: .border, edge: .minX) == 3)
        #expect(block.width(for: .padding, edge: .minX) == 14)
        // Rule plus padding is the approved 16–18 pt content inset.
        let inset = block.width(for: .border, edge: .minX) + block.width(for: .padding, edge: .minX)
        #expect(inset >= 16 && inset <= 18)
        #expect(block.borderColor(for: .minX) != nil)
    }

    // Verifies: REQ-107 — nesting composes through the block geometry, not a second mechanism.
    @Test func nestedBlockQuotesComposeTheirRules() throws {
        let source = "> outer\n>\n> > inner\n"
        let built = try build(source)
        let quotes = model(for: source).blocks.compactMap { block -> (NSRange, Int)? in
            guard case .blockQuote(let depth) = block.kind else { return nil }
            return (block.projectionRange, depth)
        }
        #expect(quotes.contains { $0.1 >= 2 })
        for (range, depth) in quotes {
            let style = try #require(
                built.attributed.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle
            )
            #expect(style.textBlocks.count == max(1, depth))
        }
    }

    // Verifies: REQ-107 — the code block is a padded adaptive container, not just tinted text.
    @Test func codeBlockIsPaddedAdaptiveContainer() throws {
        let source = "```swift\nlet x = 1\n```\n"
        let built = try build(source)
        let code = try #require(model(for: source).blocks.first {
            if case .codeBlock = $0.kind { return true }
            return false
        })
        let style = try #require(
            built.attributed.attribute(.paragraphStyle, at: code.projectionRange.location, effectiveRange: nil) as? NSParagraphStyle
        )
        let block = try #require(style.textBlocks.first)
        #expect(block.width(for: .padding, edge: .minX) == MarkdownTypography.codeBlockPadding)
        #expect(block.backgroundColor != nil)
        let font = built.attributed.attribute(.font, at: code.projectionRange.location, effectiveRange: nil) as? NSFont
        #expect(font?.isFixedPitch == true)
    }

    // Verifies: REQ-105 — heading spacing binds a heading to what follows it.
    @Test func headingSpacingIsLargerBeforeThanAfter() throws {
        let typography = MarkdownTypography()
        for level in 1...6 {
            let spacing = typography.headingSpacing(for: level)
            #expect(spacing.before > spacing.after, "H\(level) spacing is not front-weighted")
        }
        #expect(typography.headingSpacing(for: 1).before == 30)
        #expect(typography.headingSpacing(for: 1).after == 30 * 0.35)
        #expect(typography.headingSpacing(for: 2).before == 24 * 0.9)
    }

    // Verifies: REQ-107 — adaptive colors resolve in both appearances, and the semantic
    // distinction is not carried by color alone.
    @Test func semanticTreatmentsResolveInLightAndDark() throws {
        let source = "> Quoted line\n"
        for appearance in [NSAppearance(named: .aqua), NSAppearance(named: .darkAqua)] {
            let resolved = try #require(appearance)
            var borderLight: NSColor?
            resolved.performAsCurrentDrawingAppearance {
                borderLight = MarkdownTypography().quoteBlock().borderColor(for: .minX)
            }
            #expect(borderLight != nil)
        }
        // Structure, not color: the rule and inset exist independently of appearance.
        let built = try build(source)
        let quote = try #require(model(for: source).blocks.first {
            if case .blockQuote = $0.kind { return true }
            return false
        })
        let style = try #require(
            built.attributed.attribute(.paragraphStyle, at: quote.projectionRange.location, effectiveRange: nil) as? NSParagraphStyle
        )
        #expect(!style.textBlocks.isEmpty)
    }

    private func model(for source: String) -> MarkdownProjectionModel {
        let index = MarkdownSourceIndex(source: source, sourceVersion: 1)
        guard case .success(let tree) = MarkdownParser.parse(source, sourceVersion: 1) else {
            return MarkdownProjectionModel(
                sourceVersion: 1,
                renderedString: "",
                runs: [],
                attachments: [],
                tables: [],
                segments: [],
                listMarkers: [],
                sourceUTF16Count: 0
            )
        }
        return MarkdownProjectionModel.build(tree: tree, index: index)
    }

    private func build(_ source: String) throws -> AttributedPresentation {
        AttributedPresentationBuilder.build(model: model(for: source), theme: MarkdownTheme())
    }

    // Verifies: REQ-107 — cumulative hanging indentation for nested lists.
    @Test func listParagraphStyleUsesCumulativeHangingIndentation() throws {
        let source = "- outer\n  - inner\n"
        let index = MarkdownSourceIndex(source: source, sourceVersion: 1)
        guard case .success(let tree) = MarkdownParser.parse(source, sourceVersion: 1) else {
            Issue.record("fixture did not parse")
            return
        }
        let model = MarkdownProjectionModel.build(tree: tree, index: index)
        let built = AttributedPresentationBuilder.build(model: model, theme: MarkdownTheme())
        let lists = model.blocks.compactMap { block -> (NSRange, Int)? in
            guard case .listItem(_, let nesting, _) = block.kind else { return nil }
            return (block.projectionRange, nesting)
        }
        #expect(lists.count >= 2)
        for (range, nesting) in lists {
            let style = try #require(built.attributed.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle)
            #expect(style.headIndent == CGFloat(nesting + 1) * 24)
            #expect(style.firstLineHeadIndent == CGFloat(nesting) * 24)
        }
    }
}
