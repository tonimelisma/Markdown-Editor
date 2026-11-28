# 0019. Return and Backspace are structural commands, planned from the source

- Status: accepted
- Date: 2026-11-27

## Context and problem

**Why.** The tour typed a note into a new window (45957180019). Every space at the end of a line was
refused as unprovable, Return as a mapping failure, and every Backspace as an ambiguous selection,
since AppKit names the character it deletes rather than the caret. Typing a paragraph was not
possible in the default mode.

## Decision drivers

**Criteria** (vision.md's order): ordinary Markdown files a person would write by hand; editing that
behaves as on a Mac; a proof for each edit; cost.

## Considered options

| Option | Markdown a person writes | Mac editing | Proof | Cost |
| --- | --- | --- | --- | --- |
| **Structural commands, planned from source (chosen)** | ✓ blank lines, list markers | ✓ Notes-like lists | ✓ exact build, kernel's structural check | a planner, two commands |
| Return types a hard break (two spaces and a line break) | ✗ trailing spaces nobody writes | ✗ no paragraphs | ✓ | small |
| Return types `\n`, shown as a soft break | ✗ one paragraph forever | ✗ | ✗ a soft break shows as a space | none |
| Do nothing | — | ✗ Return and Backspace do nothing | — | none |

## Decision

**Decision.** In WYSIWYG, Return is `insertParagraphBreak` and Backspace over a block boundary is
`joinBlockBackward`. Both are planned from the source structure by `BlockBoundaryPlanner`, and the
exact next presentation is built from the result. Empty paragraphs, a paragraph's trailing blanks
and empty list items have a presentation, so the caret has somewhere to go. architecture.md §5 "Return
and Backspace at block boundaries" has the rules.

## Consequences

**Where it is worse.** Return in a quote leaves the quote rather than starting a second paragraph
in it: an empty line inside a quote has no presentation yet. A second Return in a nested empty list
item ends every enclosing list rather than outdenting one level. Each Return and block Backspace
pays one parse and one presentation build on the main actor, as formatting commands do; the
semantic-command budget bounds it.

## Confirmation

REQ-152 and REQ-153's tests (`BlockBoundaryTypingTests`) plan Return and Backspace from the source and check the exact next presentation.

## Retirement proof

A presentation for every empty block (an empty line inside a quote, say) that a native text edit could map without a structural command.

## Reversal plan

Route Return and Backspace through ordinary text replacement again; WYSIWYG then cannot make paragraphs.
