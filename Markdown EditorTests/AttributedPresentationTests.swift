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

    // Verifies: REQ-107; COR-28 — the block and inline code treatments do not compose.
    //
    // Fenced content carried the same `.code` style tag as an inline span, so the inline run
    // background was drawn inside the block's own `NSTextBlock` container — the darker band
    // visible in the REQ-104 capture at 88b7bd3. ENGINEERING §7 states these are distinct
    // treatments; `codeBlockIsPaddedAdaptiveContainer` asserted the container exists and never
    // that the run background is absent.
    @Test func fencedCodeCarriesNoInlineRunBackground() throws {
        let model = try #require(makeModel("Some `inline` span.\n\n```\nlet a = 1\nlet b = 2\n```\n"))
        let built = AttributedPresentationBuilder.build(model: model, theme: MarkdownTheme())
        let text = built.attributed.string as NSString

        // Inline code keeps its run background.
        let inlineRange = text.range(of: "inline")
        try #require(inlineRange.location != NSNotFound)
        #expect(
            built.attributed.attribute(.backgroundColor, at: inlineRange.location, effectiveRange: nil) != nil,
            "inline code lost its run background"
        )

        // Fenced content keeps its container, and carries no run background inside it.
        let codeRange = text.range(of: "let a = 1")
        try #require(codeRange.location != NSNotFound)
        for offset in codeRange.location..<NSMaxRange(codeRange) {
            #expect(
                built.attributed.attribute(.backgroundColor, at: offset, effectiveRange: nil) == nil,
                "fenced code carries an inline run background at \(offset)"
            )
        }
        let codeStyle = built.attributed.attribute(
            .paragraphStyle, at: codeRange.location, effectiveRange: nil
        ) as? NSParagraphStyle
        #expect(codeStyle?.textBlocks.isEmpty == false, "fenced code lost its container")
        let codeFont = built.attributed.attribute(.font, at: codeRange.location, effectiveRange: nil) as? NSFont
        #expect(codeFont?.isFixedPitch == true, "fenced code is no longer monospaced")
    }

    // Verifies: REQ-107; COR-28 — an unresolved image gets an *intentional labeled* placeholder,
    // not a bare chip of the author's description and not a truncated one.
    //
    // Found by reviewing the REQ-104 capture after the fixture gained a deliberately broken
    // reference: the cell measured its label single-line but drew it with wrapping, so the last
    // word wrapped onto a second line the single-line cell height then clipped — the placeholder
    // for "deliberately missing" read "deliberately".
    @Test func missingImagePlaceholderIsLabelledAndNotTruncated() throws {
        let model = try #require(makeModel("![deliberately missing](assets/nope.png)\n"))
        let built = AttributedPresentationBuilder.build(model: model, theme: MarkdownTheme())
        let attachment = try #require(
            built.attributed.attribute(.attachment, at: 0, effectiveRange: nil) as? NSTextAttachment
        )
        let cell = try #require(attachment.attachmentCell as? MissingImageAttachmentCell)
        let label = try #require(cell.accessibilityLabel())
        #expect(label.hasPrefix("Missing image"), "placeholder does not say what it is: \(label)")
        #expect(label.contains("deliberately missing"), "placeholder dropped the description")

        // The cell must be wide enough for its whole label on one line, or drawing clips it.
        let measured = (label as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 11)])
        #expect(
            cell.cellSize().width >= measured.width,
            "cell width \(cell.cellSize().width) is narrower than its label \(measured.width)"
        )
    }

    // An image with no description still reads as a placeholder rather than an empty box.
    // Verifies: REQ-107 — the approved image treatment.
    @Test func missingImageWithoutDescriptionStillCarriesALabel() throws {
        let model = try #require(makeModel("![](assets/nope.png)\n"))
        let built = AttributedPresentationBuilder.build(model: model, theme: MarkdownTheme())
        let attachment = try #require(
            built.attributed.attribute(.attachment, at: 0, effectiveRange: nil) as? NSTextAttachment
        )
        let cell = try #require(attachment.attachmentCell as? MissingImageAttachmentCell)
        #expect(cell.accessibilityLabel() == "Missing image")
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

    // Verifies: REQ-107 — full-measure separator and non-executing literal HTML treatments.
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

    // Verifies: REQ-107 — bounded, aspect-preserving image treatment.
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

    // Verifies: REQ-105, REQ-107 — heading typography and the table treatment both keep the
    // inline traits a run already carries rather than flattening them.
    @Test func headingAndTableHeaderPreserveInlineFontTraits() throws {
        let heading = try #require(makeModel("# *italic* `code`\n"))
        let headingPresentation = AttributedPresentationBuilder.build(model: heading, theme: MarkdownTheme())
        let headingFonts = heading.runs.compactMap { run in
            headingPresentation.attributed.attribute(.font, at: run.utf16Range.location, effectiveRange: nil) as? NSFont
        }
        #expect(headingFonts.contains { $0.fontDescriptor.symbolicTraits.contains(.italic) })
        #expect(headingFonts.contains { $0.isFixedPitch })

        let table = try #require(makeModel("| *term* | `code` |\n| - | - |\n| value | value |\n"))
        let presentation = AttributedPresentationBuilder.build(model: table, theme: MarkdownTheme())
        let headers = table.tables.flatMap(\.cells).filter(\.isHeader)
        let fonts = headers.compactMap {
            presentation.attributed.attribute(.font, at: $0.utf16Range.location, effectiveRange: nil) as? NSFont
        }
        #expect(fonts.contains { $0.fontDescriptor.symbolicTraits.contains(.italic) })
        #expect(fonts.contains { $0.isFixedPitch })
    }

    // Verifies: REQ-107 — an image is bounded by the current reading measure, not a fixed width.
    @Test func resolvedImageUsesCurrentLineFragmentWidth() throws {
        let image = NSImage(size: NSSize(width: 400, height: 200))
        let cell = ResolvedImageAttachmentCell(image: image, description: "")
        let frame = cell.cellFrame(
            for: NSTextContainer(size: NSSize(width: 344, height: 1_000)),
            proposedLineFragment: NSRect(x: 0, y: 0, width: 344, height: 1_000),
            glyphPosition: .zero,
            characterIndex: 0
        )
        #expect(frame.width == 344)
        #expect(frame.height == 172)
    }

    private func makeModel(_ source: String) -> MarkdownProjectionModel? {
        let index = MarkdownSourceIndex(source: source, sourceVersion: 1)
        guard case .success(let tree) = MarkdownParser.parse(source, sourceVersion: 1) else { return nil }
        return MarkdownProjectionModel.build(tree: tree, index: index)
    }
}
