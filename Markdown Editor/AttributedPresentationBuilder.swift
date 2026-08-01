//
//  AttributedPresentationBuilder.swift
//  Markdown Editor
//

import AppKit

/// Main-actor conversion of an immutable semantic projection into editable TextKit storage.
///
/// // REQ-105–107; ARC-018/ARC-Q14: semantic blocks determine paragraph geometry and decoration;
/// source text and coordinate meaning are never changed here.
@MainActor
enum AttributedPresentationBuilder {
    static func build(
        model: MarkdownProjectionModel,
        theme: MarkdownTheme,
        images: [MarkdownNodeID: NSImage] = [:],
        openURL: ((URL) -> Void)? = nil,
        onTaskPress: ((MarkdownNodeID) -> Void)? = nil
    ) -> AttributedPresentation {
        let typography = MarkdownTypography()
        let storage = NSMutableAttributedString(string: model.renderedString)
        let full = NSRange(location: 0, length: storage.length)
        if full.length > 0 {
            storage.setAttributes(theme.baseAttributes, range: full)
        }

        for run in model.runs {
            guard run.utf16Range.location >= 0,
                  NSMaxRange(run.utf16Range) <= storage.length,
                  run.utf16Range.length > 0 else { continue }
            var attrs: [NSAttributedString.Key: Any] = theme.baseAttributes
            for style in run.styles {
                switch style {
                case .heading(let level):
                    attrs.merge([.font: typography.font(for: level)]) { _, new in new }
                case .emphasis:
                    attrs[.obliqueness] = 0.15
                case .strong:
                    if let font = attrs[.font] as? NSFont {
                        attrs[.font] = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
                    }
                case .strikethrough:
                    attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                case .code:
                    attrs[.font] = typography.inlineCodeFont()
                    attrs[.backgroundColor] = NSColor.quaternaryLabelColor.withAlphaComponent(0.18)
                case .link:
                    break
                case .blockQuote:
                    attrs[.foregroundColor] = NSColor.secondaryLabelColor
                case .literalFallback:
                    attrs[.foregroundColor] = NSColor.secondaryLabelColor
                    attrs[.font] = typography.monoFont
                }
            }
            if let destination = run.linkDestination, let url = URL(string: destination) {
                attrs[.link] = url
                attrs[.foregroundColor] = NSColor.linkColor
                attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
            }
            storage.addAttributes(attrs, range: run.utf16Range)
        }

        var decorations: [PresentationDecoration] = []
        // Apply containing blocks first; nested list/quote blocks then refine their own
        // paragraph geometry instead of being overwritten by an outer block.
        for block in model.blocks.sorted(by: { $0.projectionRange.length > $1.projectionRange.length }) {
            guard block.projectionRange.location >= 0,
                  NSMaxRange(block.projectionRange) <= storage.length,
                  block.projectionRange.length > 0 else { continue }
            apply(block: block, to: storage, typography: typography, decorations: &decorations)
        }

        var attachmentNodes: [Int: MarkdownNodeID] = [:]
        for attachment in model.attachments {
            guard attachment.utf16Location >= 0, attachment.utf16Location < storage.length else { continue }
            let range = NSRange(location: attachment.utf16Location, length: 1)
            let nsAttachment = NSTextAttachment()
            switch attachment.kind {
            case .task(let checked, let label):
                let cell = TaskCheckboxAttachmentCell(checked: checked, label: label)
                let nodeID = attachment.nodeID
                cell.onPress = { onTaskPress?(nodeID) }
                nsAttachment.attachmentCell = cell
            case .image(let destination, let description):
                if let image = images[attachment.nodeID] {
                    let cell = ResolvedImageAttachmentCell(image: image, description: description)
                    nsAttachment.attachmentCell = cell
                    let maxWidth = MarkdownTypography.maximumReadingMeasure
                    if image.size.width > maxWidth, image.size.width > 0 {
                        let scale = maxWidth / image.size.width
                        nsAttachment.bounds = CGRect(
                            x: 0,
                            y: 0,
                            width: maxWidth,
                            height: image.size.height * scale
                        )
                    }
                } else {
                    nsAttachment.attachmentCell = MissingImageAttachmentCell(
                        text: description.isEmpty ? "Missing image: \(destination)" : description
                    )
                }
            case .thematicBreak:
                nsAttachment.attachmentCell = ThematicRuleAttachmentCell()
            }
            storage.replaceCharacters(in: range, with: NSAttributedString(attachment: nsAttachment))
            attachmentNodes[attachment.utf16Location] = attachment.nodeID
        }

        for table in model.tables {
            applyTable(table, to: storage, theme: theme)
        }

        _ = openURL
        return AttributedPresentation(
            attributed: storage,
            attachmentNodes: attachmentNodes,
            decorations: decorations
        )
    }

    private static func apply(
        block: PresentationBlock,
        to storage: NSMutableAttributedString,
        typography: MarkdownTypography,
        decorations: inout [PresentationDecoration]
    ) {
        let range = block.projectionRange
        let style = typography.paragraphStyle()
        switch block.kind {
        case .paragraph:
            break
        case .heading(let level):
            let before = level == 1 ? typography.bodyFont.pointSize : typography.bodyFont.pointSize * 0.8
            style.paragraphSpacingBefore = before
            style.paragraphSpacing = typography.bodyFont.pointSize * 0.35
            storage.addAttribute(.font, value: typography.font(for: level), range: range)
        case .listItem(_, let nesting, _):
            let depth = CGFloat(nesting)
            style.firstLineHeadIndent = depth * MarkdownTypography.listIndent
            style.headIndent = (depth + 1) * MarkdownTypography.listIndent
            style.tabStops = [NSTextTab(textAlignment: .left, location: style.headIndent)]
            style.paragraphSpacing = typography.bodyFont.pointSize * 0.35
        case .blockQuote(let depth):
            let inset = CGFloat(depth) * MarkdownTypography.quoteInset
            style.firstLineHeadIndent = inset
            style.headIndent = inset
            style.paragraphSpacing = typography.bodyFont.pointSize * 0.35
            decorations.append(PresentationDecoration(range: range, kind: .blockQuoteRule))
        case .codeBlock:
            style.paragraphSpacing = MarkdownTypography.codeBlockPadding
            storage.addAttribute(.font, value: typography.monoFont, range: range)
            storage.addAttribute(
                .backgroundColor,
                value: NSColor.quaternaryLabelColor.withAlphaComponent(0.18),
                range: range
            )
            decorations.append(PresentationDecoration(range: range, kind: .codeBlockBackground))
        case .table, .tableRow, .tableCell:
            break
        case .thematicBreak:
            style.paragraphSpacing = 0
            decorations.append(PresentationDecoration(range: range, kind: .thematicSeparator))
        case .image:
            style.paragraphSpacing = typography.bodyFont.pointSize * 0.35
        case .literalHTML:
            storage.addAttribute(.font, value: typography.monoFont, range: range)
            storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: range)
        }
        // Paragraph styles are copied per block and installed only after all values are set.
        storage.addAttribute(.paragraphStyle, value: style.copy() as! NSParagraphStyle, range: range)
    }

    private static func applyTable(
        _ table: ProjectionTable,
        to storage: NSMutableAttributedString,
        theme: MarkdownTheme
    ) {
        let nsTable = NSTextTable()
        nsTable.numberOfColumns = max(table.columnCount, 1)
        nsTable.layoutAlgorithm = .automatic
        nsTable.collapsesBorders = true
        for cell in table.cells {
            guard NSMaxRange(cell.utf16Range) <= storage.length, cell.utf16Range.length > 0 else { continue }
            let block = NSTextTableBlock(
                table: nsTable,
                startingRow: cell.row,
                rowSpan: 1,
                startingColumn: cell.column,
                columnSpan: 1
            )
            block.setBorderColor(NSColor.separatorColor)
            block.setWidth(0.5, type: .absoluteValueType, for: .border)
            block.setWidth(4, type: .absoluteValueType, for: .padding)
            let paragraph = NSMutableParagraphStyle()
            paragraph.textBlocks = [block]
            switch cell.alignment {
            case .left, .none: paragraph.alignment = .left
            case .center: paragraph.alignment = .center
            case .right: paragraph.alignment = .right
            }
            storage.addAttribute(.paragraphStyle, value: paragraph.copy() as! NSParagraphStyle, range: cell.utf16Range)
            if cell.isHeader {
                storage.addAttribute(
                    .font,
                    value: NSFont.systemFont(ofSize: MarkdownTypography.bodyPointSize, weight: .semibold),
                    range: cell.utf16Range
                )
            }
        }
        _ = theme
    }
}

// MARK: - Attachment cells

@MainActor
final class ThematicRuleAttachmentCell: NSTextAttachmentCell {
    override init() { super.init() }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    nonisolated override func cellSize() -> NSSize {
        NSSize(width: MarkdownTypography.maximumReadingMeasure, height: MarkdownTypography.separatorHeight)
    }

    nonisolated override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
        MainActor.assumeIsolated {
            NSColor.separatorColor.setStroke()
            let line = NSBezierPath()
            line.move(to: NSPoint(x: cellFrame.minX, y: cellFrame.midY))
            line.line(to: NSPoint(x: cellFrame.maxX, y: cellFrame.midY))
            line.lineWidth = 1
            line.stroke()
        }
    }

    nonisolated override func accessibilityRole() -> NSAccessibility.Role? { .staticText }
    nonisolated override func accessibilityLabel() -> String? { "Thematic break" }
}

@MainActor
final class MissingImageAttachmentCell: NSTextAttachmentCell {
    private let text: String

    init(text: String) {
        self.text = text
        super.init()
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    nonisolated override func cellSize() -> NSSize {
        MainActor.assumeIsolated {
            let size = (text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 11)])
            return NSSize(width: size.width + 8, height: max(size.height + 4, 16))
        }
    }

    nonisolated override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
        MainActor.assumeIsolated {
            NSColor.quaternaryLabelColor.setFill()
            NSBezierPath(roundedRect: cellFrame, xRadius: 3, yRadius: 3).fill()
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
            (text as NSString).draw(in: cellFrame.insetBy(dx: 4, dy: 2), withAttributes: attrs)
        }
    }

    nonisolated override func accessibilityLabel() -> String? { text }
}

@MainActor
final class TaskCheckboxAttachmentCell: NSTextAttachmentCell {
    private let checked: Bool
    private let label: String
    var onPress: (() -> Void)?

    init(checked: Bool, label: String) {
        self.checked = checked
        self.label = label
        super.init()
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    nonisolated override func cellSize() -> NSSize { NSSize(width: 16, height: 16) }

    nonisolated override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
        MainActor.assumeIsolated {
            let box = NSBezierPath(roundedRect: cellFrame.insetBy(dx: 1, dy: 1), xRadius: 2, yRadius: 2)
            NSColor.controlAccentColor.setStroke()
            box.lineWidth = 1.2
            box.stroke()
            if checked {
                let check = NSBezierPath()
                check.move(to: NSPoint(x: cellFrame.minX + 3, y: cellFrame.midY))
                check.line(to: NSPoint(x: cellFrame.midX - 1, y: cellFrame.minY + 3))
                check.line(to: NSPoint(x: cellFrame.maxX - 3, y: cellFrame.maxY - 3))
                check.lineWidth = 1.5
                check.stroke()
            }
        }
    }

    nonisolated override func accessibilityRole() -> NSAccessibility.Role? { .checkBox }
    nonisolated override func accessibilityLabel() -> String? { label.isEmpty ? "Task" : label }
    nonisolated override func accessibilityValue() -> Any? { checked ? 1 : 0 }

    nonisolated override func accessibilityPerformPress() -> Bool {
        MainActor.assumeIsolated { onPress?() }
        return true
    }
}

@MainActor
final class ResolvedImageAttachmentCell: NSTextAttachmentCell {
    private let descriptionText: String

    init(image: NSImage, description: String) {
        self.descriptionText = description
        super.init(imageCell: image)
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    nonisolated override func accessibilityLabel() -> String? {
        MainActor.assumeIsolated { descriptionText.isEmpty ? nil : descriptionText }
    }

    nonisolated override func accessibilityRole() -> NSAccessibility.Role? { .image }
}
