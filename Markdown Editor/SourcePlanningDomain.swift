//
//  SourcePlanningDomain.swift
//  Markdown Editor
//

import Foundation

/// Source-mode planning domain — extracted from SemanticEditEngine so the engine is a router.
///
/// // REQ-057/058; ARC-009: smallest-unit rewrite, no new logic.
enum SourcePlanningDomain {
    static func applySource(
        command: SemanticCommand,
        selection: SourceSelection,
        snapshot: SourceSnapshot,
        grouping: MutationGrouping
    ) -> SemanticEditResult {
        let ns = snapshot.text as NSString
        let range = selection.range.utf16
        guard range.location >= 0, NSMaxRange(range) <= ns.length else {
            return .refused(.invalidRange)
        }
        let selectionBefore = selection

        switch command {
        case .insertText(let text):
            return SemanticEditEngine.commit(
                snapshot,
                range: range,
                replacement: text,
                action: "Typing",
                grouping: grouping,
                selectionBefore: selectionBefore
            )

        case .deleteBackward:
            if range.length > 0 {
                return SemanticEditEngine.commit(
                    snapshot,
                    range: range,
                    replacement: "",
                    action: "Delete",
                    grouping: grouping,
                    selectionBefore: selectionBefore
                )
            }
            guard range.location > 0 else { return .refused(.invalidRange) }
            return SemanticEditEngine.commit(
                snapshot,
                range: NSRange(location: range.location - 1, length: 1),
                replacement: "",
                action: "Delete",
                grouping: grouping,
                selectionBefore: selectionBefore
            )

        case .toggleBold:
            return InlineEditPlanner.wrap(
                snapshot: snapshot,
                range: range,
                delimiters: [("**", "**"), ("__", "__")],
                action: "Bold",
                grouping: grouping,
                selectionBefore: selectionBefore
            ) { if case .strong = $0 { return true }; return false }
        case .toggleItalic:
            return InlineEditPlanner.wrap(
                snapshot: snapshot,
                range: range,
                delimiters: [("*", "*"), ("_", "_")],
                action: "Italic",
                grouping: grouping,
                selectionBefore: selectionBefore
            ) { if case .emphasis = $0 { return true }; return false }
        case .toggleStrikethrough:
            return InlineEditPlanner.wrap(
                snapshot: snapshot,
                range: range,
                delimiters: [("~~", "~~")],
                action: "Strikethrough",
                grouping: grouping,
                selectionBefore: selectionBefore
            ) { if case .strikethrough = $0 { return true }; return false }
        case .toggleInlineCode:
            return InlineEditPlanner.wrapCode(
                snapshot: snapshot,
                range: range,
                grouping: grouping,
                selectionBefore: selectionBefore
            )

        case .setHeading(let level):
            return BlockEditPlanner.setHeading(
                snapshot: snapshot, range: range, level: level,
                grouping: grouping, selectionBefore: selectionBefore
            )
        case .setParagraph:
            return BlockEditPlanner.setParagraph(
                snapshot: snapshot, range: range,
                grouping: grouping, selectionBefore: selectionBefore
            )

        case .toggleUnorderedList:
            return ListEditPlanner.toggle(
                snapshot: snapshot, range: range, prefix: "- ", action: "Unordered List",
                grouping: grouping, selectionBefore: selectionBefore
            )
        case .toggleOrderedList:
            return ListEditPlanner.toggle(
                snapshot: snapshot, range: range, prefix: "1. ", action: "Ordered List",
                grouping: grouping, selectionBefore: selectionBefore
            )
        case .toggleTaskList:
            return ListEditPlanner.toggle(
                snapshot: snapshot, range: range, prefix: "- [ ] ", action: "Task List",
                grouping: grouping, selectionBefore: selectionBefore
            )
        case .toggleBlockQuote:
            return ListEditPlanner.toggleBlockQuote(
                snapshot: snapshot, range: range,
                grouping: grouping, selectionBefore: selectionBefore
            )
        case .toggleCodeBlock:
            return BlockEditPlanner.toggleCodeFence(
                snapshot: snapshot, range: range,
                grouping: grouping, selectionBefore: selectionBefore
            )

        case .setLink(let destination):
            return LinkEditPlanner.setLink(
                snapshot: snapshot, range: range, destination: destination,
                grouping: grouping, selectionBefore: selectionBefore
            )

        case .insertImageMarkdown(let markdown):
            return SemanticEditEngine.commit(
                snapshot,
                range: range,
                replacement: markdown,
                action: "Insert Image",
                grouping: .discrete,
                selectionBefore: selectionBefore
            )

        case .toggleTask, .replaceTableCell:
            return .refused(.unsupportedCommand)
        }
    }

    // MARK: - WYSIWYG mode


}
