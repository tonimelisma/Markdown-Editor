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
        grouping: MutationGrouping,
        intent: IntentContext? = nil
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
                action: UndoActionName.typing.title,
                grouping: grouping,
                selectionBefore: selectionBefore,
                intent: intent
            )

        case .deleteBackward:
            if range.length > 0 {
                return SemanticEditEngine.commit(
                    snapshot,
                    range: range,
                    replacement: "",
                    action: UndoActionName.delete.title,
                    grouping: grouping,
                    selectionBefore: selectionBefore,
                    intent: intent
                )
            }
            guard range.location > 0 else { return .refused(.invalidRange) }
            return SemanticEditEngine.commit(
                snapshot,
                range: NSRange(location: range.location - 1, length: 1),
                replacement: "",
                action: UndoActionName.delete.title,
                grouping: grouping,
                selectionBefore: selectionBefore,
                intent: intent
            )

        case .toggleBold:
            return InlineEditPlanner.wrap(
                snapshot: snapshot,
                range: range,
                delimiters: [("**", "**"), ("__", "__")],
                action: UndoActionName.bold.title,
                grouping: grouping,
                selectionBefore: selectionBefore,
                intent: intent
            ) { if case .strong = $0 { return true }; return false }
        case .toggleItalic:
            return InlineEditPlanner.wrap(
                snapshot: snapshot,
                range: range,
                delimiters: [("*", "*"), ("_", "_")],
                action: UndoActionName.italic.title,
                grouping: grouping,
                selectionBefore: selectionBefore,
                intent: intent
            ) { if case .emphasis = $0 { return true }; return false }
        case .toggleStrikethrough:
            return InlineEditPlanner.wrap(
                snapshot: snapshot,
                range: range,
                delimiters: [("~~", "~~")],
                action: UndoActionName.strikethrough.title,
                grouping: grouping,
                selectionBefore: selectionBefore,
                intent: intent
            ) { if case .strikethrough = $0 { return true }; return false }
        case .toggleInlineCode:
            return InlineEditPlanner.wrapCode(
                snapshot: snapshot,
                range: range,
                grouping: grouping,
                selectionBefore: selectionBefore,
                intent: intent
            )

        case .setHeading(let level):
            return BlockEditPlanner.setHeading(
                snapshot: snapshot, range: range, level: level,
                grouping: grouping, selectionBefore: selectionBefore, intent: intent
            )
        case .setParagraph:
            return BlockEditPlanner.setParagraph(
                snapshot: snapshot, range: range,
                grouping: grouping, selectionBefore: selectionBefore, intent: intent
            )

        case .toggleUnorderedList:
            return ListEditPlanner.toggle(
                snapshot: snapshot, range: range, prefix: "- ", action: UndoActionName.unorderedList.title,
                grouping: grouping, selectionBefore: selectionBefore, intent: intent
            )
        case .toggleOrderedList:
            return ListEditPlanner.toggle(
                snapshot: snapshot, range: range, prefix: "1. ", action: UndoActionName.orderedList.title,
                grouping: grouping, selectionBefore: selectionBefore, intent: intent
            )
        case .toggleTaskList:
            return ListEditPlanner.toggle(
                snapshot: snapshot, range: range, prefix: "- [ ] ", action: UndoActionName.taskList.title,
                grouping: grouping, selectionBefore: selectionBefore, intent: intent
            )
        case .toggleBlockQuote:
            return ListEditPlanner.toggleBlockQuote(
                snapshot: snapshot, range: range,
                grouping: grouping, selectionBefore: selectionBefore, intent: intent
            )
        case .toggleCodeBlock:
            return BlockEditPlanner.toggleCodeFence(
                snapshot: snapshot, range: range,
                grouping: grouping, selectionBefore: selectionBefore, intent: intent
            )

        case .setLink(let destination):
            return LinkEditPlanner.setLink(
                snapshot: snapshot, range: range, destination: destination,
                grouping: grouping, selectionBefore: selectionBefore, intent: intent
            )

        case .insertImageMarkdown(let markdown):
            return SemanticEditEngine.commit(
                snapshot,
                range: range,
                replacement: markdown,
                action: UndoActionName.insertImage.title,
                grouping: .discrete,
                selectionBefore: selectionBefore,
                intent: intent
            )

        case .toggleTask, .replaceTableCell, .insertParagraphBreak, .joinBlockBackward:
            // Source mode types line breaks as text; these are WYSIWYG's structural keys.
            return .refused(.unsupportedCommand)
        }
    }

    // MARK: - WYSIWYG mode


}
