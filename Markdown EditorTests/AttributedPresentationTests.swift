//
//  AttributedPresentationTests.swift
//  Markdown EditorTests
//

import AppKit
import Foundation
import Testing
@testable import Markdown_Editor

@MainActor
struct AttributedPresentationTests {
    @Test func semanticBlocksAndTypographyDoNotChangeRenderedSource() throws {
        let source = "# Title\n\nBody *emphasis*.\n\n> Quote\n\n```swift\nlet x = 1\n```\n"
        let model = try #require(makeModel(source))
        let built = AttributedPresentationBuilder.build(model: model, theme: MarkdownTheme())

        #expect(built.attributed.string == model.renderedString)
        #expect(model.blocks.contains { if case .heading(level: 1) = $0.kind { return true }; return false })
        #expect(model.blocks.contains { if case .paragraph = $0.kind { return true }; return false })
        #expect(model.blocks.contains { if case .blockQuote = $0.kind { return true }; return false })
        #expect(model.blocks.contains { if case .codeBlock = $0.kind { return true }; return false })

        let headingRange = try #require(model.blocks.first {
            if case .heading = $0.kind { return true }
            return false
        }?.projectionRange)
        let headingFont = built.attributed.attribute(.font, at: headingRange.location, effectiveRange: nil) as? NSFont
        #expect(headingFont?.pointSize == 30)
    }

    @Test func softAndHardBreaksHaveDistinctPresentationText() throws {
        let soft = try #require(makeModel("one\ntwo\n"))
        let hard = try #require(makeModel("one  \ntwo\n"))
        #expect(soft.renderedString == "one two\n")
        #expect(hard.renderedString == "one\ntwo\n")
        #expect(soft.segments.contains { segment in
            if case .synthetic(_, .softLineBreak, _) = segment { return true }
            return false
        })
        #expect(hard.segments.contains { segment in
            if case .synthetic(_, .hardLineBreak, _) = segment { return true }
            return false
        })
    }

    @Test func taskPresentationHasCheckboxWithoutDuplicateBullet() throws {
        let model = try #require(makeModel("- [ ] task\n"))
        let built = AttributedPresentationBuilder.build(model: model, theme: MarkdownTheme())
        #expect(!built.attributed.string.hasPrefix("-"))
        #expect(model.attachments.contains { if case .task = $0.kind { return true }; return false })
        let task = try #require(model.attachments.first { if case .task = $0.kind { return true }; return false })
        let attachment = built.attributed.attribute(.attachment, at: task.utf16Location, effectiveRange: nil) as? NSTextAttachment
        #expect(attachment?.attachmentCell is TaskCheckboxAttachmentCell)
    }

    @Test func thematicBreakAndLiteralHTMLUseSemanticAttachments() throws {
        let model = try #require(makeModel("---\n\n<div>literal</div>\n"))
        let built = AttributedPresentationBuilder.build(model: model, theme: MarkdownTheme())
        let thematic = try #require(model.attachments.first { if case .thematicBreak = $0.kind { return true }; return false })
        let attachment = built.attributed.attribute(.attachment, at: thematic.utf16Location, effectiveRange: nil) as? NSTextAttachment
        #expect(attachment?.attachmentCell is ThematicRuleAttachmentCell)
        let html = try #require(model.blocks.first { if case .literalHTML = $0.kind { return true }; return false })
        let htmlFont = built.attributed.attribute(.font, at: html.projectionRange.location, effectiveRange: nil) as? NSFont
        #expect(htmlFont?.isFixedPitch == true)
    }

    @Test func resolvedImageIsAspectPreservingAndBoundedByReadingMeasure() throws {
        let model = try #require(makeModel("![wide](image.png)\n"))
        let image = NSImage(size: NSSize(width: 1_440, height: 720))
        let attachment = try #require(model.attachments.first)
        let built = AttributedPresentationBuilder.build(
            model: model,
            theme: MarkdownTheme(),
            images: [attachment.nodeID: image]
        )
        let value = built.attributed.attribute(.attachment, at: attachment.utf16Location, effectiveRange: nil) as? NSTextAttachment
        #expect(value?.bounds.size.width == 720)
        #expect(value?.bounds.size.height == 360)
        #expect((value?.attachmentCell as? ResolvedImageAttachmentCell) != nil)
    }

    private func makeModel(_ source: String) -> MarkdownProjectionModel? {
        let index = MarkdownSourceIndex(source: source, sourceVersion: 1)
        guard case .success(let tree) = MarkdownParser.parse(source, sourceVersion: 1) else { return nil }
        return MarkdownProjectionModel.build(tree: tree, index: index)
    }
}
