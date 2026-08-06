//
//  AttributedPresentationBuilder.swift
//  Markdown Editor
//

import AppKit

/// Main-actor conversion of an immutable semantic projection into editable TextKit storage.
///
/// // REQ-105–107/109; ARC-018/ARC-019/ARC-Q14: semantic blocks determine paragraph geometry and
/// decoration; source text and coordinate meaning are never changed here. An ordinary accepted
/// edit builds only the semantic block scope it touches — never the whole document.
@MainActor
enum AttributedPresentationBuilder {
    /// Attributed content for one contiguous slice of a projection, in that projection's own
    /// coordinates. `range` covers whole semantic blocks, so no paragraph is styled from a
    /// truncated view of itself.
    struct Scoped {
        let range: NSRange
        let attributed: NSAttributedString
        /// Attachment locations in *projection* coordinates, not slice-relative ones.
        let attachmentNodes: [Int: MarkdownNodeID]
    }

    static func build(
        model: MarkdownProjectionModel,
        theme: MarkdownTheme,
        images: [MarkdownNodeID: NSImage] = [:],
        onTaskPress: ((MarkdownNodeID) -> Void)? = nil
    ) -> AttributedPresentation {
        let whole = NSRange(location: 0, length: (model.renderedString as NSString).length)
        let scoped = buildScoped(
            model: model,
            theme: theme,
            images: images,
            onTaskPress: onTaskPress,
            scope: whole
        )
        return AttributedPresentation(
            attributed: scoped.attributed,
            attachmentNodes: scoped.attachmentNodes
        )
    }

    /// Expands `range` to the union of every semantic block and table that intersects it, so the
    /// slice can be styled exactly as it would be inside a complete build.
    static func blockScope(for range: NSRange, in model: MarkdownProjectionModel) -> NSRange {
        let length = (model.renderedString as NSString).length
        var lower = max(0, min(range.location, length))
        var upper = max(lower, min(NSMaxRange(range), length))
        for block in model.blocks where intersectsOrTouches(block.projectionRange, range) {
            lower = min(lower, block.projectionRange.location)
            upper = max(upper, NSMaxRange(block.projectionRange))
        }
        for table in model.tables where intersectsOrTouches(table.utf16Range, range) {
            lower = min(lower, table.utf16Range.location)
            upper = max(upper, NSMaxRange(table.utf16Range))
        }
        lower = max(0, lower)
        upper = min(length, upper)
        return NSRange(location: lower, length: max(0, upper - lower))
    }

    static func buildScoped(
        model: MarkdownProjectionModel,
        theme: MarkdownTheme,
        images: [MarkdownNodeID: NSImage] = [:],
        onTaskPress: ((MarkdownNodeID) -> Void)? = nil,
        scope: NSRange
    ) -> Scoped {
        let typography = MarkdownTypography()
        let rendered = model.renderedString as NSString
        let scope = NSRange(
            location: max(0, min(scope.location, rendered.length)),
            length: max(0, min(scope.length, rendered.length - min(scope.location, rendered.length)))
        )
        let storage = NSMutableAttributedString(string: rendered.substring(with: scope))
        let full = NSRange(location: 0, length: storage.length)
        if full.length > 0 {
            storage.setAttributes(theme.baseAttributes, range: full)
        }

        for run in model.runs {
            guard let local = localRange(run.utf16Range, in: scope), local.length > 0 else { continue }
            storage.addAttributes(
                inlineAttributes(for: run, theme: theme, typography: typography),
                range: local
            )
        }

        // Containing blocks first: a nested list or quote then refines its own paragraph geometry
        // instead of being overwritten by the block that encloses it.
        for block in model.blocks.sorted(by: { $0.projectionRange.length > $1.projectionRange.length }) {
            guard let local = localRange(block.projectionRange, in: scope), local.length > 0 else { continue }
            apply(block: block, localRange: local, to: storage, typography: typography)
        }

        var attachmentNodes: [Int: MarkdownNodeID] = [:]
        for attachment in model.attachments {
            let location = attachment.utf16Location
            guard location >= scope.location, location < NSMaxRange(scope) else { continue }
            let local = NSRange(location: location - scope.location, length: 1)
            guard NSMaxRange(local) <= storage.length else { continue }
            storage.replaceCharacters(
                in: local,
                with: NSAttributedString(
                    attachment: makeAttachment(attachment, images: images, onTaskPress: onTaskPress)
                )
            )
            attachmentNodes[location] = attachment.nodeID
        }

        for table in model.tables where intersectsOrTouches(table.utf16Range, scope) {
            applyTable(table, to: storage, scope: scope, typography: typography)
        }

        return Scoped(range: scope, attributed: storage, attachmentNodes: attachmentNodes)
    }

    // MARK: - Inline

    private static func inlineAttributes(
        for run: ProjectionRun,
        theme: MarkdownTheme,
        typography: MarkdownTypography
    ) -> [NSAttributedString.Key: Any] {
        var attrs = theme.baseAttributes
        // Font traits are collected before the font is resolved, so style order inside the run
        // cannot decide whether a bold heading keeps its weight.
        var pointSize = MarkdownTypography.bodyPointSize
        var headingLevel: Int?
        var bold = false
        var italic = false
        var monospaced = false

        for style in run.styles {
            switch style {
            case .heading(let level):
                headingLevel = level
                pointSize = typography.font(for: level).pointSize
            case .strong: bold = true
            case .emphasis: italic = true
            case .strikethrough:
                attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            case .code:
                monospaced = true
                attrs[.backgroundColor] = NSColor.quaternaryLabelColor.withAlphaComponent(0.18)
            case .codeBlock:
                // REQ-107; COR-28: monospaced only. The block's `NSTextBlock` container already
                // supplies the background and padding; adding the inline run background here is
                // what drew a darker band inside the container.
                monospaced = true
            case .link:
                break
            case .blockQuote, .literalFallback:
                attrs[.foregroundColor] = NSColor.secondaryLabelColor
                if case .literalFallback = style { monospaced = true }
            }
        }

        var font: NSFont
        if monospaced {
            font = .monospacedSystemFont(
                ofSize: headingLevel == nil ? pointSize * MarkdownTypography.inlineCodeScale : pointSize,
                weight: bold ? .semibold : .regular
            )
        } else if let headingLevel {
            font = typography.font(for: headingLevel)
        } else {
            font = .systemFont(ofSize: pointSize, weight: bold ? .bold : .regular)
        }
        if bold, headingLevel != nil || monospaced {
            font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
        }
        if italic {
            font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
        }
        attrs[.font] = font

        if let destination = run.linkDestination, let url = URL(string: destination) {
            attrs[.link] = url
            attrs[.foregroundColor] = NSColor.linkColor
            attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        return attrs
    }

    // MARK: - Blocks

    private static func apply(
        block: PresentationBlock,
        localRange range: NSRange,
        to storage: NSMutableAttributedString,
        typography: MarkdownTypography
    ) {
        // Containing blocks are applied first, so an enclosing quote's or code block's geometry
        // is already installed here. A nested block must inherit its parent's geometry instead of
        // replacing it, so a paragraph inside a list item keeps the list's hanging indent.
        let style: NSMutableParagraphStyle
        if let enclosing = storage.attribute(.paragraphStyle, at: range.location, effectiveRange: nil)
            as? NSParagraphStyle {
            style = enclosing.mutableCopy() as! NSMutableParagraphStyle
        } else {
            style = typography.paragraphStyle()
        }
        switch block.kind {
        case .paragraph:
            break
        case .heading(let level):
            let spacing = typography.headingSpacing(for: level)
            style.paragraphSpacingBefore = spacing.before
            style.paragraphSpacing = spacing.after
            if level >= 6 {
                storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: range)
            }
        case .listItem(_, let nesting, _):
            let depth = CGFloat(nesting)
            style.firstLineHeadIndent = depth * MarkdownTypography.listIndent
            style.headIndent = (depth + 1) * MarkdownTypography.listIndent
            style.tabStops = [NSTextTab(textAlignment: .left, location: style.headIndent)]
            style.paragraphSpacing = typography.blockSpacing
        case .blockQuote(let depth):
            // The rule and content inset are the block's own geometry, so nesting composes
            // without a second indentation mechanism disagreeing with it.
            style.textBlocks = (0..<max(1, depth)).map { _ in typography.quoteBlock() }
            style.paragraphSpacing = typography.blockSpacing
        case .codeBlock:
            style.textBlocks = [typography.codeBlock()]
            style.paragraphSpacing = typography.blockSpacing
            storage.addAttribute(.font, value: typography.monoFont, range: range)
        case .table, .tableRow, .tableCell:
            return
        case .thematicBreak:
            style.paragraphSpacing = 0
        case .image:
            style.paragraphSpacing = typography.blockSpacing
        case .literalHTML:
            storage.addAttribute(.font, value: typography.monoFont, range: range)
            storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: range)
        }
        // Paragraph styles are copied per block and installed only after all values are set, so
        // a style already inside storage is never mutated in place.
        installPerTextKitParagraph(style, to: storage, range: range)
    }

    /// Installs one semantic block's paragraph style across the **TextKit paragraphs** its
    /// rendered text actually contains.
    ///
    /// // REQ-106/107; COR-27: `NSParagraphStyle.paragraphSpacing` is applied after every TextKit
    /// // paragraph, and TextKit ends a paragraph at every `\n`. A semantic block is not always
    /// // one TextKit paragraph: a formal hard break puts a real newline *inside* one CommonMark
    /// // paragraph, and a fenced code block is one semantic block spanning many lines. Applying
    /// // the block's style uniformly therefore gave a hard break the same vertical gap as a
    /// // paragraph boundary, and spaced a code block's own lines apart.
    /// //
    /// // Spacing belongs to a **semantic** boundary: only the last TextKit paragraph in the block
    /// // carries `paragraphSpacing`, and only the first carries `paragraphSpacingBefore`.
    /// //
    /// // COR-36: `firstLineHeadIndent` is likewise not uniform. It is the hanging indent that
    /// // positions the list marker, so only the block's first TextKit paragraph may carry it;
    /// // every later paragraph is continuation content and begins at `headIndent`. `headIndent`,
    /// // tab stops, text blocks, and alignment *are* identical across the block, so nesting,
    /// // quote rules, and code containers are unchanged.
    private static func installPerTextKitParagraph(
        _ style: NSMutableParagraphStyle,
        to storage: NSMutableAttributedString,
        range: NSRange
    ) {
        func install(_ value: NSMutableParagraphStyle, _ target: NSRange) {
            storage.addAttribute(.paragraphStyle, value: value.copy() as! NSParagraphStyle, range: target)
        }
        guard range.length > 1 else {
            install(style, range)
            return
        }
        let text = storage.string as NSString
        // A newline at the very end of the block terminates the block's own last paragraph, so it
        // does not start another one. Interior newlines do.
        var starts = [range.location]
        for index in range.location..<(NSMaxRange(range) - 1) where text.character(at: index) == 0x0A {
            starts.append(index + 1)
        }
        guard starts.count > 1 else {
            install(style, range)
            return
        }
        starts.append(NSMaxRange(range))
        for position in 0..<(starts.count - 1) {
            let sub = NSRange(
                location: starts[position],
                length: starts[position + 1] - starts[position]
            )
            guard sub.length > 0 else { continue }
            let scoped = style.mutableCopy() as! NSMutableParagraphStyle
            if position != starts.count - 2 { scoped.paragraphSpacing = 0 }
            if position != 0 {
                scoped.paragraphSpacingBefore = 0
                // COR-36: `firstLineHeadIndent` is the *hanging* indent — it positions the line
                // that carries the list marker, and it is smaller than `headIndent` by exactly one
                // indent step. Only the block's first TextKit paragraph carries that marker. Every
                // later one is continuation content, so it starts at the content indent; leaving it
                // at the marker indent drew a list item's second paragraph, and a quote nested in a
                // list item, flush to the reading margin as though they had left the list.
                scoped.firstLineHeadIndent = scoped.headIndent
            }
            install(scoped, sub)
        }
    }

    private static func applyTable(
        _ table: ProjectionTable,
        to storage: NSMutableAttributedString,
        scope: NSRange,
        typography: MarkdownTypography
    ) {
        let nsTable = NSTextTable()
        nsTable.numberOfColumns = max(table.columnCount, 1)
        nsTable.layoutAlgorithm = .automatic
        nsTable.collapsesBorders = true
        for cell in table.cells {
            guard let local = localRange(cell.utf16Range, in: scope), local.length > 0 else { continue }
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
            let paragraph = typography.paragraphStyle()
            paragraph.paragraphSpacing = 0
            paragraph.textBlocks = [block]
            switch cell.alignment {
            case .left, .none: paragraph.alignment = .left
            case .center: paragraph.alignment = .center
            case .right: paragraph.alignment = .right
            }
            storage.addAttribute(.paragraphStyle, value: paragraph.copy() as! NSParagraphStyle, range: local)
            if cell.isHeader {
                storage.enumerateAttribute(.font, in: local) { value, range, _ in
                    guard let font = value as? NSFont else { return }
                    storage.addAttribute(
                        .font,
                        value: NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask),
                        range: range
                    )
                }
            }
        }
    }

    private static func makeAttachment(
        _ attachment: ProjectionAttachment,
        images: [MarkdownNodeID: NSImage],
        onTaskPress: ((MarkdownNodeID) -> Void)?
    ) -> NSTextAttachment {
        let nsAttachment = NSTextAttachment()
        switch attachment.kind {
        case .task(let checked, let label):
            let cell = TaskCheckboxAttachmentCell(checked: checked, label: label)
            let nodeID = attachment.nodeID
            cell.onPress = { onTaskPress?(nodeID) }
            nsAttachment.attachmentCell = cell
        case .image(let destination, let description):
            if let image = images[attachment.nodeID] {
                nsAttachment.attachmentCell = ResolvedImageAttachmentCell(image: image, description: description)
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
                // The cell composes its own "Missing image" prefix, so pass only the author's
                // description; an empty one yields the bare label rather than a path.
                nsAttachment.attachmentCell = MissingImageAttachmentCell(text: description)
            }
        case .thematicBreak:
            nsAttachment.attachmentCell = ThematicRuleAttachmentCell()
        }
        return nsAttachment
    }

    // MARK: - Range helpers

    private static func intersectsOrTouches(_ range: NSRange, _ other: NSRange) -> Bool {
        NSIntersectionRange(range, other).length > 0
            || (other.length == 0 && NSLocationInRange(other.location, range))
            || (range.length == 0 && NSLocationInRange(range.location, other))
    }

    /// Clips a projection range into slice-relative coordinates, or nil when it lies outside.
    private static func localRange(_ range: NSRange, in scope: NSRange) -> NSRange? {
        let intersection = NSIntersectionRange(range, scope)
        guard intersection.length > 0 else { return nil }
        return NSRange(location: intersection.location - scope.location, length: intersection.length)
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

    /// The separator spans the measure actually available, so a window narrower than the maximum
    /// reading measure gets a separator that fits rather than one that overhangs.
    nonisolated override func cellFrame(
        for textContainer: NSTextContainer,
        proposedLineFragment lineFrag: NSRect,
        glyphPosition position: NSPoint,
        characterIndex charIndex: Int
    ) -> NSRect {
        let available = min(lineFrag.width, MarkdownTypography.maximumReadingMeasure)
        return NSRect(x: 0, y: 0, width: max(1, available), height: MarkdownTypography.separatorHeight)
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
    /// Stored rather than computed so the nonisolated `accessibilityLabel()` override can read
    /// it without crossing the main-actor boundary.
    private let displayText: String

    init(text: String) {
        self.text = text
        // REQ-107; COR-28: ENGINEERING §7 requires "an intentional labeled placeholder rather
        // than an unrelated generic file icon". Showing only the image description rendered as a
        // bare grey chip of ordinary-looking text, which reads as content rather than as a
        // failure, so the label always says what it is.
        self.displayText = text.isEmpty ? "Missing image" : "Missing image — \(text)"
        super.init()
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private static let labelFont = NSFont.systemFont(ofSize: 11)

    nonisolated override func cellSize() -> NSSize {
        MainActor.assumeIsolated {
            let size = (displayText as NSString).size(withAttributes: [.font: Self.labelFont])
            // Ceil, and leave real horizontal slack. `size(withAttributes:)` measures a single
            // line while `draw(in:)` wraps, so a rect merely *equal* to the measured width let
            // the last word wrap onto a second line that the single-line cell height then
            // clipped — the placeholder read "deliberately" for "deliberately missing".
            return NSSize(width: ceil(size.width) + 14, height: max(ceil(size.height) + 4, 16))
        }
    }

    nonisolated override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
        MainActor.assumeIsolated {
            NSColor.quaternaryLabelColor.setFill()
            NSBezierPath(roundedRect: cellFrame, xRadius: 3, yRadius: 3).fill()
            let attrs: [NSAttributedString.Key: Any] = [
                .font: Self.labelFont,
                .foregroundColor: NSColor.secondaryLabelColor
            ]
            // `draw(at:)` never wraps, so the label cannot be silently truncated by the cell's
            // own single-line height.
            let size = (displayText as NSString).size(withAttributes: attrs)
            let origin = NSPoint(
                x: cellFrame.minX + 7,
                y: cellFrame.minY + max(0, (cellFrame.height - size.height) / 2)
            )
            (displayText as NSString).draw(at: origin, withAttributes: attrs)
        }
    }

    nonisolated override func accessibilityLabel() -> String? { displayText }
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
                // An attachment cell draws inside the text view's flipped coordinate space, so
                // minY is the *top* edge. The stroke therefore runs left-middle → lower-middle
                // → upper-right; using minY for the middle point drew an inverted caret rather
                // than a check mark, which the window screenshot showed plainly.
                let check = NSBezierPath()
                check.move(to: NSPoint(x: cellFrame.minX + 3.5, y: cellFrame.midY))
                check.line(to: NSPoint(x: cellFrame.midX - 0.5, y: cellFrame.maxY - 4))
                check.line(to: NSPoint(x: cellFrame.maxX - 3, y: cellFrame.minY + 4))
                check.lineWidth = 1.5
                check.lineCapStyle = .round
                check.lineJoinStyle = .round
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
    private let intrinsicSize: NSSize

    init(image: NSImage, description: String) {
        self.descriptionText = description
        self.intrinsicSize = image.size
        super.init(imageCell: image)
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    nonisolated override func accessibilityLabel() -> String? {
        MainActor.assumeIsolated { descriptionText.isEmpty ? nil : descriptionText }
    }

    nonisolated override func accessibilityRole() -> NSAccessibility.Role? { .image }

    /// TextKit supplies the actual line fragment at layout time. Keep the image inside that
    /// measure as well as the document-wide maximum, preserving its intrinsic aspect ratio.
    nonisolated override func cellFrame(
        for textContainer: NSTextContainer,
        proposedLineFragment lineFrag: NSRect,
        glyphPosition position: NSPoint,
        characterIndex charIndex: Int
    ) -> NSRect {
        let available = max(1, min(lineFrag.width, MarkdownTypography.maximumReadingMeasure))
        guard intrinsicSize.width > 0, intrinsicSize.height > 0 else {
            return NSRect(x: 0, y: 0, width: available, height: 1)
        }
        let scale = min(1, available / intrinsicSize.width)
        return NSRect(
            x: 0,
            y: 0,
            width: intrinsicSize.width * scale,
            height: intrinsicSize.height * scale
        )
    }
}
