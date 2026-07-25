//
//  RichTextBuilder.swift
//  Markdown Editor
//

import AppKit

/// Main-actor conversion of a Sendable projection model into attributed storage.
///
/// // REQ-054–056/080/084: AppKit types constructed only on the main actor.
@MainActor
enum RichTextBuilder {
    struct BuiltRichText {
        let attributed: NSAttributedString
        let attachmentNodes: [Int: MarkdownNodeID] // UTF-16 location → node
    }

    static func build(
        model: MarkdownProjectionModel,
        theme: MarkdownTheme,
        images: [MarkdownNodeID: NSImage] = [:],
        openURL: ((URL) -> Void)? = nil
    ) -> BuiltRichText {
        let storage = NSMutableAttributedString(string: model.renderedString)
        let full = NSRange(location: 0, length: storage.length)
        storage.setAttributes(theme.baseAttributes, range: full)

        for run in model.runs {
            guard NSMaxRange(run.utf16Range) <= storage.length else { continue }
            var attrs: [NSAttributedString.Key: Any] = theme.baseAttributes
            for style in run.styles {
                switch style {
                case .heading(let level):
                    attrs.merge(headingAttributes(level: level, theme: theme)) { _, new in new }
                case .emphasis:
                    attrs[.obliqueness] = 0.15
                case .strong:
                    if let font = attrs[.font] as? NSFont {
                        attrs[.font] = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
                    }
                case .strikethrough:
                    attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                case .code:
                    attrs[.font] = NSFont.monospacedSystemFont(ofSize: theme.baseFont.pointSize * 0.95, weight: .regular)
                    attrs[.backgroundColor] = NSColor.controlBackgroundColor
                case .link:
                    break
                case .blockQuote:
                    attrs[.foregroundColor] = NSColor.secondaryLabelColor
                case .literalFallback:
                    attrs[.foregroundColor] = NSColor.secondaryLabelColor
                    attrs[.font] = NSFont.monospacedSystemFont(ofSize: theme.baseFont.pointSize * 0.95, weight: .regular)
                }
            }
            if let destination = run.linkDestination, let url = URL(string: destination) {
                attrs[.link] = url
                attrs[.foregroundColor] = NSColor.linkColor
                attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
            }
            storage.addAttributes(attrs, range: run.utf16Range)
        }

        var attachmentNodes: [Int: MarkdownNodeID] = [:]
        for attachment in model.attachments {
            guard attachment.utf16Location < storage.length else { continue }
            let range = NSRange(location: attachment.utf16Location, length: 1)
            let nsAttachment = NSTextAttachment()
            switch attachment.kind {
            case .task(let checked, let label):
                nsAttachment.attachmentCell = TaskCheckboxAttachmentCell(checked: checked, label: label)
            case .image(let destination, let description):
                if let image = images[attachment.nodeID] {
                    nsAttachment.image = image
                    let maxWidth: CGFloat = 480
                    let size = image.size
                    if size.width > maxWidth && size.width > 0 {
                        let scale = maxWidth / size.width
                        nsAttachment.bounds = CGRect(x: 0, y: 0, width: maxWidth, height: size.height * scale)
                    }
                } else {
                    nsAttachment.attachmentCell = PlaceholderAttachmentCell(
                        text: description.isEmpty ? "Missing image: \(destination)" : description
                    )
                }
            case .thematicBreak:
                nsAttachment.attachmentCell = PlaceholderAttachmentCell(text: "————————")
            }
            let attr = NSAttributedString(attachment: nsAttachment)
            storage.replaceCharacters(in: range, with: attr)
            attachmentNodes[attachment.utf16Location] = attachment.nodeID
        }

        // Native tables: apply paragraph styles with NSTextTable where metadata exists.
        for table in model.tables {
            applyTable(table, to: storage, theme: theme)
        }

        _ = openURL // retained for future custom link click routing via text view
        return BuiltRichText(attributed: storage, attachmentNodes: attachmentNodes)
    }

    private static func headingAttributes(level: Int, theme: MarkdownTheme) -> [NSAttributedString.Key: Any] {
        let sizes: [CGFloat] = [28, 24, 20, 18, 16, 14]
        let size = sizes[max(0, min(level - 1, sizes.count - 1))]
        let font = NSFont.systemFont(ofSize: size, weight: .bold)
        return [.font: font, .foregroundColor: NSColor.labelColor]
    }

    private static func applyTable(_ table: ProjectionTable, to storage: NSMutableAttributedString, theme: MarkdownTheme) {
        let nsTable = NSTextTable()
        nsTable.numberOfColumns = max(table.columnCount, 1)
        nsTable.layoutAlgorithm = .automatic
        nsTable.collapsesBorders = true

        for cell in table.cells {
            guard NSMaxRange(cell.utf16Range) <= storage.length, cell.utf16Range.length > 0 else { continue }
            let block = NSTextTableBlock(table: nsTable, startingRow: cell.row, rowSpan: 1, startingColumn: cell.column, columnSpan: 1)
            block.setBorderColor(NSColor.separatorColor)
            block.setWidth(0.5, type: .absoluteValueType, for: .border)
            block.setWidth(4, type: .absoluteValueType, for: .padding)
            let style = NSMutableParagraphStyle()
            style.textBlocks = [block]
            switch cell.alignment {
            case .left, .none: style.alignment = .left
            case .center: style.alignment = .center
            case .right: style.alignment = .right
            }
            if cell.isHeader {
                storage.addAttribute(.font, value: NSFont.systemFont(ofSize: theme.baseFont.pointSize, weight: .semibold), range: cell.utf16Range)
            }
            storage.addAttribute(.paragraphStyle, value: style, range: cell.utf16Range)
        }
    }
}

// MARK: - Attachment cells

@MainActor
final class TaskCheckboxAttachmentCell: NSTextAttachmentCell {
    private let checked: Bool
    private let label: String

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
                NSColor.controlAccentColor.setStroke()
                check.lineWidth = 1.5
                check.stroke()
            }
        }
    }

    nonisolated override func accessibilityRole() -> NSAccessibility.Role? { .checkBox }
    nonisolated override func accessibilityLabel() -> String? { label.isEmpty ? "Task" : label }
    nonisolated override func accessibilityValue() -> Any? { checked ? 1 : 0 }
}

@MainActor
final class PlaceholderAttachmentCell: NSTextAttachmentCell {
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
