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
