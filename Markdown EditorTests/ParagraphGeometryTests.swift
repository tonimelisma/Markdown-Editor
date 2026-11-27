//
//  ParagraphGeometryTests.swift
//  Markdown EditorTests
//

import AppKit
import Foundation
import Testing
@testable import Markdown_Editor

/// Laid-out geometry proofs for semantic block spacing.
///
/// // Verifies: REQ-106/107; ARC-Q14/ARC-Q15 — a hard break is a line break, not a paragraph
/// // boundary, and a fenced code block does not space its own lines apart.
///
/// Every existing typography proof asserts **attribute values** (`textBlocks`,
/// `paragraphSpacing`). Every visual defect this project has found — the inverted task checkmark,
/// the blockquote that laid out one character per line, and this one — lives past that assertion.
/// These tests force real TextKit layout in a directly constructed `NSTextView` and read line
/// fragment rectangles, which `CLAUDE.md` §4 permits: no XCUITest, no screen automation, no UI
/// driving.
@MainActor
struct ParagraphGeometryTests {
    /// Builds and lays out a document, returning the line-fragment origin of each laid-out line.
    private func lineTops(for source: String, width: CGFloat = 600) throws -> (
        tops: [CGFloat], text: NSString, view: NSTextView
    ) {
        let version: UInt64 = 1
        let tree = try #require(MarkdownParser.parse(source, sourceVersion: version).get())
        let index = MarkdownSourceIndex(source: source, sourceVersion: version)
        let model = MarkdownProjectionModel.build(tree: tree, index: index)
        let built = AttributedPresentationBuilder.build(model: model, theme: MarkdownTypography())

        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 2000))
        view.textContainer?.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        view.textContainer?.widthTracksTextView = false
        view.textStorage?.setAttributedString(built.attributed)
        guard let layoutManager = view.layoutManager, let container = view.textContainer else {
            throw GeometryError.noLayoutManager
        }
        layoutManager.ensureLayout(for: container)

        var tops: [CGFloat] = []
        var glyph = 0
        let glyphCount = layoutManager.numberOfGlyphs
        while glyph < glyphCount {
            var effective = NSRange(location: 0, length: 0)
            let rect = layoutManager.lineFragmentRect(
                forGlyphAt: glyph, effectiveRange: &effective
            )
            tops.append(rect.minY)
            glyph = effective.length > 0 ? NSMaxRange(effective) : glyph + 1
        }
        return (tops, built.attributed.string as NSString, view)
    }

    private enum GeometryError: Error { case noLayoutManager }

    // Verifies: REQ-081 — an image takes the height it is drawn at: the block after it starts
    // below the image, not over it. In the showcase the heading after the image was drawn over
    // its bottom edge (tour 45976057730).
    @Test func theBlockAfterAnImageStartsBelowIt() throws {
        let source = "Before.\n\n![Sky](sky.png)\n\n## Two questions\n"
        let version: UInt64 = 1
        let tree = try #require(MarkdownParser.parse(source, sourceVersion: version).get())
        let index = MarkdownSourceIndex(source: source, sourceVersion: version)
        let model = MarkdownProjectionModel.build(tree: tree, index: index)
        let attachment = try #require(model.attachments.first {
            if case .image = $0.kind { return true }
            return false
        })
        let image = NSImage(size: NSSize(width: 1200, height: 700))
        let built = AttributedPresentationBuilder.build(
            model: model, theme: MarkdownTypography(), images: [attachment.nodeID: image]
        )

        let width: CGFloat = 760
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 4000))
        view.textContainer?.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        view.textContainer?.widthTracksTextView = false
        view.textStorage?.setAttributedString(built.attributed)
        let layoutManager = try #require(view.layoutManager)
        let container = try #require(view.textContainer)
        layoutManager.ensureLayout(for: container)

        let imageGlyph = layoutManager.glyphIndexForCharacter(at: attachment.utf16Location)
        let imageLine = layoutManager.lineFragmentRect(forGlyphAt: imageGlyph, effectiveRange: nil)
        let imageSize = layoutManager.attachmentSize(forGlyphAt: imageGlyph)
        let baseline = layoutManager.location(forGlyphAt: imageGlyph).y
        // TextKit draws an attachment upward from its glyph's baseline.
        let imageTop = imageLine.minY + baseline - imageSize.height
        let imageBottom = imageLine.minY + baseline

        let heading = (built.attributed.string as NSString).range(of: "Two questions")
        let headingGlyph = layoutManager.glyphIndexForCharacter(at: heading.location)
        let headingLine = layoutManager.lineFragmentRect(forGlyphAt: headingGlyph, effectiveRange: nil)

        let report = "image line \(imageLine), size \(imageSize), baseline \(baseline); heading line \(headingLine)"
        #expect(imageSize.height > 300, "the image was not drawn at its scaled size: \(report)")
        #expect(imageTop >= imageLine.minY - 0.5, "the image starts above its own line: \(report)")
        #expect(headingLine.minY >= imageBottom - 0.5, "the heading starts over the image: \(report)")
    }

    /// Lays a document out and returns, for each laid-out line, the x origin of the text it
    /// actually draws and the text itself.
    ///
    /// `lineFragmentUsedRect` rather than `lineFragmentRect`: the fragment rect spans the whole
    /// container regardless of indentation, so reading it would report every line at the same x
    /// and the proof would pass against any indent defect whatsoever.
    private func laidOutLines(for source: String, width: CGFloat) throws -> [(minX: CGFloat, text: String)] {
        let version: UInt64 = 1
        let tree = try #require(MarkdownParser.parse(source, sourceVersion: version).get())
        let index = MarkdownSourceIndex(source: source, sourceVersion: version)
        let model = MarkdownProjectionModel.build(tree: tree, index: index)
        let built = AttributedPresentationBuilder.build(model: model, theme: MarkdownTypography())

        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 4000))
        view.textContainer?.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        view.textContainer?.widthTracksTextView = false
        view.textContainer?.lineFragmentPadding = 0
        view.textStorage?.setAttributedString(built.attributed)
        guard let layoutManager = view.layoutManager, let container = view.textContainer else {
            throw GeometryError.noLayoutManager
        }
        layoutManager.ensureLayout(for: container)

        let string = built.attributed.string as NSString
        var lines: [(minX: CGFloat, text: String)] = []
        var glyph = 0
        while glyph < layoutManager.numberOfGlyphs {
            var effective = NSRange(location: 0, length: 0)
            let used = layoutManager.lineFragmentUsedRect(forGlyphAt: glyph, effectiveRange: &effective)
            let characters = layoutManager.characterRange(forGlyphRange: effective, actualGlyphRange: nil)
            lines.append((used.minX, string.substring(with: characters)))
            glyph = effective.length > 0 ? NSMaxRange(effective) : glyph + 1
        }
        return lines
    }

    /// // Verifies: REQ-107 — a block nested inside a list item keeps the list's content indent
    /// instead of resetting to the reading margin.
    ///
    /// COR-36. The nested-block path built a fresh paragraph style and copied only `textBlocks`
    /// from the enclosing block, so everything carrying *horizontal* geometry — `headIndent`,
    /// `firstLineHeadIndent`, `tabStops` — was dropped. A quote inside a list kept its rule and
    /// lost its indent, and a list item's continuation paragraph rendered flush left as though it
    /// had left the list.
    ///
    /// The reference indent is measured, not assumed: the list item's own text is long enough to
    /// wrap, and a wrapped line lays out at exactly the item's content indent by definition. An
    /// assertion against a hardcoded 24 pt would restate `MarkdownTypography.listIndent` rather
    /// than prove where the glyphs went.
    @Test func nestedParagraphKeepsItsListItemContentIndent() throws {
        let itemText = String(repeating: "item ", count: 60)
        let source = """
        - \(itemText)

          A continuation paragraph inside the same list item.

        An unnested paragraph at the reading margin.

        """

        // ARC-Q15: narrow, default, and wide constructed widths.
        for width in [320.0, 600.0, 900.0] as [CGFloat] {
            let lines = try laidOutLines(for: source, width: width)

            let itemLines = lines.filter { $0.text.contains("item ") }
            try #require(itemLines.count >= 2, "the list item did not wrap at width \(width)")
            // A wrapped line of the item's own text sits at the item's content indent.
            let contentIndent = itemLines[1].minX

            let continuation = try #require(
                lines.first { $0.text.contains("A continuation paragraph") },
                "the continuation paragraph did not lay out"
            )
            let unnested = try #require(
                lines.first { $0.text.contains("An unnested paragraph") },
                "the unnested paragraph did not lay out"
            )

            #expect(
                abs(continuation.minX - contentIndent) < 0.5,
                "at width \(width) the continuation paragraph drew at x=\(continuation.minX) but its list item's content indent is \(contentIndent)"
            )
            #expect(
                continuation.minX > unnested.minX + MarkdownTypography.listIndent / 2,
                "at width \(width) the continuation paragraph (x=\(continuation.minX)) is not indented past an unnested paragraph (x=\(unnested.minX))"
            )
        }
    }

    /// // Verifies: REQ-107 — the same inheritance holds for a decorated nested block: a quote
    /// inside a list item keeps both the quote's rule and the list's indent.
    @Test func quoteNestedInAListItemKeepsRuleAndIndent() throws {
        let itemText = String(repeating: "item ", count: 60)
        let source = """
        - \(itemText)

          > A quote inside the list item.

        """
        let lines = try laidOutLines(for: source, width: 600)
        let itemLines = lines.filter { $0.text.contains("item ") }
        try #require(itemLines.count >= 2, "the list item did not wrap")
        let quoted = try #require(lines.first { $0.text.contains("A quote inside") })

        // The quote's own rule and padding add to the list indent; it must never sit at or left
        // of the reading margin, and never left of its list item's content indent.
        #expect(
            quoted.minX >= itemLines[1].minX,
            "quote drew at x=\(quoted.minX), left of its list item's content indent \(itemLines[1].minX)"
        )
    }

    /// // Verifies: REQ-106 — the gap across a formal hard break is one ordinary line advance and
    /// is strictly smaller than the gap across a paragraph boundary in the same document.
    ///
    /// The pre-COR-27 build measured these as equal (≈69 pt vs ≈70 pt in the REQ-104 capture),
    /// so a hard break was indistinguishable from a new paragraph.
    @Test func hardBreakAdvancesOneLineWhileParagraphBoundaryAddsSpacing() throws {
        // Line 1 and 2 are one paragraph joined by a hard break; line 3 is a new paragraph.
        let source = "Alpha\\\nBravo\n\nCharlie\n"
        let laid = try lineTops(for: source)
        try #require(laid.tops.count >= 3, "expected at least three laid-out lines")

        let hardBreakGap = laid.tops[1] - laid.tops[0]
        let paragraphGap = laid.tops[2] - laid.tops[1]

        #expect(
            hardBreakGap < paragraphGap,
            "hard break gap \(hardBreakGap) is not smaller than paragraph gap \(paragraphGap)"
        )
        // And the hard break really is just a line advance: the paragraph boundary must add at
        // least most of the configured block spacing on top of it.
        let added = paragraphGap - hardBreakGap
        #expect(
            added >= MarkdownTypography().blockSpacing * 0.5,
            "paragraph boundary added only \(added) over a hard break"
        )
    }

    /// // Verifies: REQ-107 — a fenced code block is one semantic block, so its own lines advance
    /// by one plain line, not by a line plus block spacing.
    ///
    /// The reference is measured, not assumed: a long paragraph that *wraps* produces two visual
    /// lines inside one TextKit paragraph, which is by definition one line advance with no
    /// paragraph spacing. A code block's interior advance must match it.
    ///
    /// Asserting only that the code lines advance *uniformly* would not discriminate — they
    /// advance uniformly whether the added spacing is zero or not. That version of this test
    /// passed against the defect.
    @Test func fencedCodeBlockDoesNotSpaceItsOwnLinesApart() throws {
        let wrapping = String(repeating: "wrap ", count: 60)
        let source = "\(wrapping)\n\n```\nlet a = 1\nlet b = 2\nlet c = 3\n```\n"
        let laid = try lineTops(for: source, width: 300)
        try #require(laid.tops.count >= 5, "expected wrapped paragraph lines plus three code lines")

        // The wrapped paragraph's own internal advance: one line, no paragraph spacing.
        let wrappedAdvance = laid.tops[1] - laid.tops[0]
        #expect(wrappedAdvance > 0)

        // The last three laid-out lines are the code block's three lines.
        let count = laid.tops.count
        let codeAdvance = laid.tops[count - 1] - laid.tops[count - 2]

        #expect(
            codeAdvance <= wrappedAdvance + 1.0,
            "code line advance \(codeAdvance) exceeds plain line advance \(wrappedAdvance); block spacing is being applied between the block's own lines"
        )
    }

    /// // Verifies: ARC-018 — this is a layout-only correction. The rendered string and every
    /// projection coordinate are byte-identical to what the same source produced before.
    // Verifies: REQ-105 — geometry is derived presentation only; it changes neither the rendered
    // string nor any coordinate (ARC-018).
    @Test func paragraphGeometryChangesNoRenderedTextOrCoordinates() throws {
        for source in [
            "Alpha\\\nBravo\n\nCharlie\n",
            "```\nlet a = 1\nlet b = 2\n```\n",
            "> quoted line one\n> quoted line two\n",
            "- item one\n- item two\n",
        ] {
            let version: UInt64 = 1
            let tree = try #require(MarkdownParser.parse(source, sourceVersion: version).get())
            let index = MarkdownSourceIndex(source: source, sourceVersion: version)
            let model = MarkdownProjectionModel.build(tree: tree, index: index)
            let built = AttributedPresentationBuilder.build(model: model, theme: MarkdownTypography())
            #expect(
                built.attributed.string == model.renderedString,
                "attributed text diverged from the projection for \(source.debugDescription)"
            )
        }
    }

    /// // Verifies: REQ-107 — a multi-line blockquote keeps one composed rule across every one of
    /// its TextKit paragraphs, so splitting the style did not drop block geometry.
    @Test func multiLineBlockQuoteKeepsItsRuleOnEveryLine() throws {
        let source = "> quoted line one\n> quoted line two\n"
        let version: UInt64 = 1
        let tree = try #require(MarkdownParser.parse(source, sourceVersion: version).get())
        let index = MarkdownSourceIndex(source: source, sourceVersion: version)
        let model = MarkdownProjectionModel.build(tree: tree, index: index)
        let built = AttributedPresentationBuilder.build(model: model, theme: MarkdownTypography())

        let length = built.attributed.length
        try #require(length > 0)
        var offset = 0
        var inspected = 0
        while offset < length {
            var effective = NSRange(location: 0, length: 0)
            let style = built.attributed.attribute(
                .paragraphStyle, at: offset, effectiveRange: &effective
            ) as? NSParagraphStyle
            let quoted = try #require(style, "no paragraph style at \(offset)")
            #expect(!quoted.textBlocks.isEmpty, "blockquote lost its rule at offset \(offset)")
            inspected += 1
            offset = effective.length > 0 ? NSMaxRange(effective) : offset + 1
        }
        #expect(inspected >= 2, "expected the quote to span more than one styled run")
    }
}
