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
        theme: MarkdownTypography,
        images: [MarkdownNodeID: NSImage] = [:],
        onTaskPress: ((MarkdownNodeID) -> Void)? = nil,
        intent: IntentContext? = nil
    ) -> AttributedPresentation {
        let whole = NSRange(location: 0, length: (model.renderedString as NSString).length)
        let scoped = buildScoped(
            model: model,
            theme: theme,
            images: images,
            onTaskPress: onTaskPress,
            scope: whole,
            intent: intent
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
        theme: MarkdownTypography,
        images: [MarkdownNodeID: NSImage] = [:],
        onTaskPress: ((MarkdownNodeID) -> Void)? = nil,
        scope: NSRange,
        intent: IntentContext? = nil
    ) -> Scoped {
        if let intent {
            intent.recorder.add(intent) {
                $0.attributedBuilds += 1
                $0.attributedCharactersWritten += scope.length
            }
        }
        let typography = theme
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

        // Projection runs are emitted in projection order. Stop once the sorted run stream is
        // beyond the bounded scope; ordinary input must not scan/style the whole document.
        for run in model.runs {
            if run.utf16Range.location >= NSMaxRange(scope) { break }
            guard let local = localRange(run.utf16Range, in: scope), local.length > 0 else { continue }
            storage.addAttributes(
                inlineAttributes(for: run, theme: theme, typography: typography),
                range: local
            )
        }

        // Containing blocks first: a nested list or quote then refines its own paragraph geometry
        // instead of being overwritten by the block that encloses it.
        let scopedBlocks = model.blocks
            .filter { intersectsOrTouches($0.projectionRange, scope) }
            .sorted { $0.projectionRange.length > $1.projectionRange.length }
        for block in scopedBlocks {
            guard let local = localRange(block.projectionRange, in: scope), local.length > 0 else { continue }
            apply(block: block, localRange: local, to: storage, typography: typography)
        }

        var attachmentNodes: [Int: MarkdownNodeID] = [:]
        for attachment in model.attachments {
            if attachment.utf16Location >= NSMaxRange(scope) { break }
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
        theme: MarkdownTypography,
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
                attrs[.backgroundColor] = EditorColorCatalog.color(.codeBackground, alpha: MarkdownTypography.codeBackgroundAlpha)
            case .codeBlock:
                // REQ-107; COR-28: monospaced only. The block's `NSTextBlock` container already
                // supplies the background and padding; adding the inline run background here is
                // what drew a darker band inside the container.
                monospaced = true
            case .link:
                break
            case .blockQuote, .literalFallback:
                attrs[.foregroundColor] = EditorColorCatalog.color(.secondaryText)
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
            attrs[.foregroundColor] = EditorColorCatalog.color(.link)
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
            // An image alone in its paragraph is laid out at its own height. The body's line
            // height multiple, applied to an image's line, let the next block's text draw over
            // the bottom of the image (tour 45976057730, showcase).
            let text = (storage.string as NSString).substring(with: range)
            if text.contains("\u{FFFC}"),
               text.unicodeScalars.allSatisfy({ $0 == "\u{FFFC}" || $0 == "\n" || $0 == " " }) {
                style.lineHeightMultiple = 1
            }
        case .heading(let level):
            let spacing = typography.headingSpacing(for: level)
            style.paragraphSpacingBefore = spacing.before
            style.paragraphSpacing = spacing.after
            if level >= 6 {
                storage.addAttribute(.foregroundColor, value: EditorColorCatalog.color(.secondaryText), range: range)
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
            // Composed: a code block inside a quote keeps both containers. Depth is total
            // enclosing quote depth; existing quote blocks from outer quotes are preserved.
            let existingBlocks = style.textBlocks
            let existingQuoteCount = existingBlocks.filter { Self.isQuoteBlock($0) }.count
            let needed = max(1, depth) - existingQuoteCount
            if needed > 0 {
                style.textBlocks = existingBlocks + (0..<needed).map { _ in typography.quoteBlock() }
            } else if existingBlocks.isEmpty {
                style.textBlocks = (0..<max(1, depth)).map { _ in typography.quoteBlock() }
            }
            style.paragraphSpacing = typography.blockSpacing
        case .codeBlock:
            let existingBlocks = style.textBlocks
            style.textBlocks = existingBlocks + [typography.codeBlock()]
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
            storage.addAttribute(.foregroundColor, value: EditorColorCatalog.color(.secondaryText), range: range)
        }
        // Paragraph styles are copied per block and installed only after all values are set, so
        // a style already inside storage is never mutated in place.
        installPerTextKitParagraph(style, to: storage, range: range)
    }

    /// Installs one semantic block's paragraph style across the **TextKit paragraphs** its
    /// rendered text actually contains.
    ///
    /// // REQ-106/107; COR-27/36: spacing and hanging indent belong to semantic boundaries, not to
    /// // every `\n`. Extracted so the style-array logic is testable without constructing a view.
    private static func installPerTextKitParagraph(
        _ style: NSMutableParagraphStyle,
        to storage: NSMutableAttributedString,
        range: NSRange
    ) {
        let styles = ParagraphStyleInstaller.styles(for: style, range: range, text: storage.string as NSString)
        for (sub, scoped) in styles {
            storage.addAttribute(.paragraphStyle, value: scoped.copy() as! NSParagraphStyle, range: sub)
        }
    }

    /// Pure per-paragraph style computation — no `NSTextStorage` side effect, so a unit test can
    /// assert on the array without constructing a `NSTextView`.
    enum ParagraphStyleInstaller {
        static func styles(
            for style: NSMutableParagraphStyle,
            range: NSRange,
            text: NSString
        ) -> [(NSRange, NSMutableParagraphStyle)] {
            func copy(_ s: NSMutableParagraphStyle) -> NSMutableParagraphStyle {
                s.mutableCopy() as! NSMutableParagraphStyle
            }
            guard range.length > 1 else {
                return [(range, copy(style))]
            }
            var starts = [range.location]
            for index in range.location..<(NSMaxRange(range) - 1) where text.character(at: index) == 0x0A {
                starts.append(index + 1)
            }
            guard starts.count > 1 else {
                return [(range, copy(style))]
            }
            starts.append(NSMaxRange(range))
            var out: [(NSRange, NSMutableParagraphStyle)] = []
            for position in 0..<(starts.count - 1) {
                let sub = NSRange(
                    location: starts[position],
                    length: starts[position + 1] - starts[position]
                )
                guard sub.length > 0 else { continue }
                let scoped = copy(style)
                if position != starts.count - 2 { scoped.paragraphSpacing = 0 }
                if position != 0 {
                    scoped.paragraphSpacingBefore = 0
                    scoped.firstLineHeadIndent = scoped.headIndent
                }
                out.append((sub, scoped))
            }
            return out
        }
    }

    // MARK: - Text block identity (COR-39)

    /// Typed predicate for quote vs code block. Using `backgroundColor == nil` as kind tag worked
    /// while only two `NSTextBlock` kinds existed, but a third container would collide.
    private static func isQuoteBlock(_ block: NSTextBlock) -> Bool {
        block is QuoteTextBlock
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
            block.setBorderColor(EditorColorCatalog.color(.structuralRule))
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
        case .image(_, let description):
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
            EditorColorCatalog.color(.structuralRule).setStroke()
            let line = NSBezierPath()
            line.move(to: NSPoint(x: cellFrame.minX, y: cellFrame.midY))
            line.line(to: NSPoint(x: cellFrame.maxX, y: cellFrame.midY))
            line.lineWidth = 1
            line.stroke()
        }
    }

    // REQ-129: role and description come from `MarkdownAccessibilityModel`, so the closed matrix
    // is what assistive technology actually receives rather than a parallel hard-coded answer.
    nonisolated override func accessibilityRole() -> NSAccessibility.Role? {
        MarkdownAccessibilityModel.descriptor(for: .thematicBreak).role
    }
    nonisolated override func accessibilityLabel() -> String? {
        MarkdownAccessibilityModel.descriptor(for: .thematicBreak).roleDescription
    }
}

@MainActor
final class MissingImageAttachmentCell: NSTextAttachmentCell {
    private let text: String
    /// Stored rather than computed so the nonisolated `accessibilityLabel()` override can read
    /// it without crossing the main-actor boundary.
    private let displayText: String

    init(text: String) {
        self.text = text
        // REQ-107; COR-28: architecture.md §7 requires "an intentional labeled placeholder rather
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
            EditorColorCatalog.color(.codeBackground).setFill()
            NSBezierPath(roundedRect: cellFrame, xRadius: 3, yRadius: 3).fill()
            let attrs: [NSAttributedString.Key: Any] = [
                .font: Self.labelFont,
                .foregroundColor: EditorColorCatalog.color(.secondaryText)
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
            EditorColorCatalog.color(.accent).setStroke()
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

    // REQ-129: the role and the checked state come from the closed matrix; only the label is
    // document text, which reaches assistive technology through this element and nowhere else.
    private nonisolated var taskDescriptor: MarkdownAccessibilityDescriptor {
        MarkdownAccessibilityModel.descriptor(
            for: .listItem(kind: .bullet, nesting: 0, task: true),
            isChecked: checked
        )
    }

    nonisolated override func accessibilityRole() -> NSAccessibility.Role? { taskDescriptor.role }
    nonisolated override func accessibilityLabel() -> String? {
        label.isEmpty ? taskDescriptor.roleDescription : label
    }
    nonisolated override func accessibilityValue() -> Any? { (taskDescriptor.checked ?? false) ? 1 : 0 }

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

    // REQ-129: role from the closed matrix.
    nonisolated override func accessibilityRole() -> NSAccessibility.Role? {
        MarkdownAccessibilityModel.descriptor(for: .image).role
    }

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
