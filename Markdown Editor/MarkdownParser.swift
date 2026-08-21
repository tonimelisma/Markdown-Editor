//
//  MarkdownParser.swift
//  Markdown Editor
//

import Foundation
import Synchronization
import cmark_gfm
import cmark_gfm_extensions

/// Owned wrapper that confines all cmark C API use to one call boundary.
///
/// // REQ-054: pin swift-cmark 5d9bdaa; enable table/tasklist/strikethrough/autolink/tagfilter;
/// // CMARK_OPT_STRIKETHROUGH_DOUBLE_TILDE; disable smart punctuation and extras.
/// // REQ-085: parsing is synchronous and runs off-main on immutable source.
nonisolated enum MarkdownParser {
    /// Exact pinned revision string for tests / attribution.
    static let pinnedRevision = FormalGFMDialect.pinnedRevision

    /// Enabled formal-GFM extension names (exact set).
    static let enabledExtensions = FormalGFMDialect.enabledExtensions

    /// cmark-gfm global registration / parse is not concurrent-safe.
    private static let parseLock = Mutex(false)

    /// Parser option bits: double-tilde strikethrough only; no smart/table-span extras.
    static var parserOptions: Int32 {
        FormalGFMDialect.parserOptions
    }

    /// Parse Markdown into an immutable Swift value tree.
    static func parse(
        _ source: String,
        sourceVersion: UInt64,
        intent: IntentContext? = nil,
        isCancelled: @Sendable () -> Bool = { false }
    ) -> Result<MarkdownTree, MarkdownParseFailure> {
        parseLock.withLock { _ in
            // Cancellation is checked only at the parser boundary. Once cmark has entered its
            // synchronous C call it cannot safely be interrupted, but a cancelled waiter must
            // not copy its source or enter cmark after the lock becomes available.
            guard !isCancelled() else { return .failure(.cancelled) }
            if let intent {
                intent.recorder.add(intent) { $0.documentParses += 1 }
            }
            var bytes = Array(source.utf8)
            return bytes.withUnsafeMutableBufferPointer { buffer in
                guard let base = buffer.baseAddress else {
                    return parseUTF8Unlocked("", byteCount: 0, sourceVersion: sourceVersion, source: "")
                }
                return base.withMemoryRebound(to: CChar.self, capacity: buffer.count) { cPtr in
                    parseUTF8Unlocked(cPtr, byteCount: buffer.count, sourceVersion: sourceVersion, source: source)
                }
            }
        }
    }

    /// Test-only critical-section gate used to prove cancellation ordering without exposing the
    /// cmark lock or C pointers to production callers.
    static func withParseLockForTesting<T: Sendable>(_ body: @Sendable () -> T) -> T {
        parseLock.withLock { _ in body() }
    }

    /// Render HTML with the same pinned configuration (formal-GFM conformance).
    static func renderHTML(_ source: String) -> Result<String, MarkdownParseFailure> {
        renderHTML(source, extensions: enabledExtensions)
    }

    /// Render HTML enabling only the named extensions (spec suite example metadata).
    static func renderHTML(
        _ source: String,
        extensions: [String]
    ) -> Result<String, MarkdownParseFailure> {
        parseLock.withLock { _ in
            var bytes = Array(source.utf8)
            return bytes.withUnsafeMutableBufferPointer { buffer in
                guard let base = buffer.baseAddress else {
                    return renderHTMLUTF8Unlocked("", byteCount: 0, extensions: extensions)
                }
                return base.withMemoryRebound(to: CChar.self, capacity: buffer.count) { cPtr in
                    renderHTMLUTF8Unlocked(cPtr, byteCount: buffer.count, extensions: extensions)
                }
            }
        }
    }

    /// Parse UTF-8 bytes (used by conformance fixtures that may contain NULs).
    static func parseUTF8(
        _ bytes: UnsafePointer<CChar>,
        byteCount: Int,
        sourceVersion: UInt64
    ) -> Result<MarkdownTree, MarkdownParseFailure> {
        parseLock.withLock { _ in
            let source = String(decoding: (0..<byteCount).map { UInt8(bitPattern: bytes[$0]) }, as: UTF8.self)
            return parseUTF8Unlocked(bytes, byteCount: byteCount, sourceVersion: sourceVersion, source: source)
        }
    }

    static func renderHTMLUTF8(
        _ bytes: UnsafePointer<CChar>,
        byteCount: Int,
        extensions: [String] = MarkdownParser.enabledExtensions
    ) -> Result<String, MarkdownParseFailure> {
        parseLock.withLock { _ in
            renderHTMLUTF8Unlocked(bytes, byteCount: byteCount, extensions: extensions)
        }
    }

    private static func parseUTF8Unlocked(
        _ bytes: UnsafePointer<CChar>,
        byteCount: Int,
        sourceVersion: UInt64,
        source: String
    ) -> Result<MarkdownTree, MarkdownParseFailure> {
        cmark_gfm_core_extensions_ensure_registered()

        guard let parser = cmark_parser_new(parserOptions) else {
            return .failure(.allocationFailed)
        }
        defer { cmark_parser_free(parser) }

        for name in enabledExtensions {
            guard let ext = cmark_find_syntax_extension(name) else {
                return .failure(.extensionUnavailable(name))
            }
            cmark_parser_attach_syntax_extension(parser, ext)
        }

        cmark_parser_feed(parser, bytes, byteCount)
        guard let document = cmark_parser_finish(parser) else {
            return .failure(.emptyDocumentNode)
        }
        defer { cmark_node_free(document) }

        var nextID: UInt64 = 1
        let sourceIndex = MarkdownSourceIndex(source: source, sourceVersion: sourceVersion)
        guard let root = convert(document, nextID: &nextID, sourceIndex: sourceIndex) else {
            return .failure(.emptyDocumentNode)
        }
        return .success(MarkdownTree(sourceVersion: sourceVersion, root: root))
    }

    private static func renderHTMLUTF8Unlocked(
        _ bytes: UnsafePointer<CChar>,
        byteCount: Int,
        extensions: [String]
    ) -> Result<String, MarkdownParseFailure> {
        if let unsupported = extensions.first(where: { !FormalGFMDialect.accepts(extensions: [$0]) }) {
            return .failure(.unsupportedExtension(unsupported))
        }
        cmark_gfm_core_extensions_ensure_registered()

        // Parse options always include double-tilde strikethrough; smart/extras stay off.
        guard let parser = cmark_parser_new(parserOptions) else {
            return .failure(.allocationFailed)
        }
        defer { cmark_parser_free(parser) }

        for name in extensions {
            guard let ext = cmark_find_syntax_extension(name) else {
                return .failure(.extensionUnavailable(name))
            }
            cmark_parser_attach_syntax_extension(parser, ext)
        }

        cmark_parser_feed(parser, bytes, byteCount)
        guard let document = cmark_parser_finish(parser) else {
            return .failure(.emptyDocumentNode)
        }
        defer { cmark_node_free(document) }

        // Formal-GFM HTML conformance uses CMARK_OPT_UNSAFE so raw HTML is emitted
        // (the app never executes HTML — WYSIWYG shows it literally).
        let renderOptions = parserOptions | Int32(CMARK_OPT_UNSAFE)
        let attached = cmark_parser_get_syntax_extensions(parser)
        guard let cHTML = cmark_render_html(document, renderOptions, attached) else {
            return .failure(.allocationFailed)
        }
        defer { free(cHTML) }
        return .success(String(cString: cHTML))
    }

    // MARK: - C → Swift

    private static func convert(
        _ node: UnsafeMutablePointer<cmark_node>,
        nextID: inout UInt64,
        sourceIndex: MarkdownSourceIndex
    ) -> MarkdownNode? {
        let id = MarkdownNodeID(rawValue: nextID)
        nextID &+= 1

        let position = SourcePosition(
            startLine: Int(cmark_node_get_start_line(node)),
            startColumn: Int(cmark_node_get_start_column(node)),
            endLine: Int(cmark_node_get_end_line(node)),
            endColumn: Int(cmark_node_get_end_column(node))
        )

        let type = cmark_node_get_type(node)
        let typeName = String(cString: cmark_node_get_type_string(node))

        let kind: MarkdownNodeKind
        switch type {
        case CMARK_NODE_DOCUMENT:
            kind = .document
        case CMARK_NODE_BLOCK_QUOTE:
            kind = .blockQuote
        case CMARK_NODE_LIST:
            kind = .list(listInfo(from: node))
        case CMARK_NODE_ITEM:
            // Task-list items keep CMARK_NODE_ITEM but report type string "tasklist".
            let checked: Bool? = (typeName == "tasklist")
                ? cmark_gfm_extensions_get_tasklist_item_checked(node)
                : nil
            kind = .item(taskChecked: checked)
        case CMARK_NODE_CODE_BLOCK:
            let literal = literalString(cmark_node_get_literal(node))
            let info = literalString(cmark_node_get_fence_info(node))
            var length: Int32 = 0
            var offset: Int32 = 0
            var character: CChar = 0
            let fenced = cmark_node_get_fenced(node, &length, &offset, &character) != 0
            let fenceChar: Character? = fenced ? Character(UnicodeScalar(UInt8(bitPattern: character))) : nil
            kind = .codeBlock(info: info, literal: literal, fenced: fenced, fenceChar: fenceChar, fenceLength: Int(length))
        case CMARK_NODE_HTML_BLOCK:
            kind = .htmlBlock(literal: literalString(cmark_node_get_literal(node)))
        case CMARK_NODE_PARAGRAPH:
            kind = .paragraph
        case CMARK_NODE_HEADING:
            kind = .heading(level: Int(cmark_node_get_heading_level(node)))
        case CMARK_NODE_THEMATIC_BREAK:
            kind = .thematicBreak
        case CMARK_NODE_TEXT:
            kind = .text(literalString(cmark_node_get_literal(node)))
        case CMARK_NODE_SOFTBREAK:
            kind = .softBreak
        case CMARK_NODE_LINEBREAK:
            kind = .lineBreak
        case CMARK_NODE_CODE:
            kind = .code(literal: literalString(cmark_node_get_literal(node)))
        case CMARK_NODE_HTML_INLINE:
            kind = .htmlInline(literal: literalString(cmark_node_get_literal(node)))
        case CMARK_NODE_EMPH:
            kind = .emphasis
        case CMARK_NODE_STRONG:
            kind = .strong
        case CMARK_NODE_LINK:
            let preservesLiteralSource: Bool
            switch sourceIndex.substring(position: position) {
            case .success(let source):
                preservesLiteralSource = FormalGFMDialect.preservesUnsupportedLinkLiteral(source)
            case .failure:
                preservesLiteralSource = false
            }
            kind = .link(
                destination: literalString(cmark_node_get_url(node)),
                title: literalString(cmark_node_get_title(node)),
                preservesLiteralSource: preservesLiteralSource
            )
        case CMARK_NODE_IMAGE:
            kind = .image(
                destination: literalString(cmark_node_get_url(node)),
                title: literalString(cmark_node_get_title(node))
            )
        default:
            switch typeName {
            case "strikethrough":
                kind = .strikethrough
            case "table":
                let columns = Int(cmark_gfm_extensions_get_table_columns(node))
                let alignments = tableAlignments(from: node, columns: columns)
                kind = .table(columnCount: columns, alignments: alignments)
            case "table_row", "table_header":
                let isHeader = cmark_gfm_extensions_get_table_row_is_header(node) != 0
                kind = .tableRow(isHeader: isHeader)
            case "table_cell":
                kind = .tableCell
            case "tasklist":
                kind = .item(taskChecked: cmark_gfm_extensions_get_tasklist_item_checked(node))
            default:
                kind = .unsupported(typeName: typeName)
            }
        }

        var children: [MarkdownNode] = []
        var child = cmark_node_first_child(node)
        while let current = child {
            if let converted = convert(current, nextID: &nextID, sourceIndex: sourceIndex) {
                children.append(converted)
            }
            child = cmark_node_next(current)
        }

        return MarkdownNode(id: id, kind: kind, position: position, children: children)
    }

    private static func listInfo(from node: UnsafeMutablePointer<cmark_node>) -> MarkdownListInfo {
        let listType = cmark_node_get_list_type(node)
        let tight = cmark_node_get_list_tight(node) != 0
        let marker: MarkdownListMarker
        switch cmark_node_get_list_marker(node) {
        case CMARK_HYPHEN_LIST_MARKER: marker = .dash
        case CMARK_PLUS_LIST_MARKER: marker = .plus
        case CMARK_ASTERISK_LIST_MARKER: marker = .asterisk
        default: marker = .other
        }

        let kind: MarkdownListKind
        if listType == CMARK_ORDERED_LIST {
            let delim: OrderedDelimiter = cmark_node_get_list_delim(node) == CMARK_PAREN_DELIM ? .paren : .period
            kind = .ordered(start: Int(cmark_node_get_list_start(node)), delimiter: delim)
        } else {
            kind = .bullet
        }
        return MarkdownListInfo(kind: kind, tight: tight, marker: marker)
    }

    private static func tableAlignments(from node: UnsafeMutablePointer<cmark_node>, columns: Int) -> [TableAlignment] {
        guard columns > 0, let raw = cmark_gfm_extensions_get_table_alignments(node) else {
            return Array(repeating: .none, count: max(columns, 0))
        }
        var result: [TableAlignment] = []
        result.reserveCapacity(columns)
        for i in 0..<columns {
            switch raw[i] {
            case UInt8(ascii: "l"): result.append(.left)
            case UInt8(ascii: "c"): result.append(.center)
            case UInt8(ascii: "r"): result.append(.right)
            default: result.append(.none)
            }
        }
        return result
    }

    private static func literalString(_ cString: UnsafePointer<CChar>?) -> String {
        guard let cString else { return "" }
        return String(cString: cString)
    }
}
