# ADR-0008 — Editor text engine: TextKit 1 NSTextView

- **Status:** Accepted
- **Date:** 2026-07-22
- **Deciders:** Toni Melisma
- **Related:** [ADR-0002](0002-swiftui-first-appkit-where-needed.md) (resolves the deferred
  engine), [ADR-0007](0007-editor-surface-interim-texteditor.md) (interim TextEditor, replaced
  at INC-02); [RESEARCH-0002](../research/0002-textkit-engine-spike.md); SPIKE-01 → INC-02

> Living decision. Revisit if TextKit 2's editing/rendering reliability materially improves.

## Context

From INC-02 the editor needs **live syntax highlighting**, which requires an `NSTextView`
(SwiftUI's `TextEditor` can't do it — [ADR-0002](0002-swiftui-first-appkit-where-needed.md)).
`NSTextView` can run on **TextKit 1** or **TextKit 2**. SPIKE-01 investigated both plus
third-party views ([RESEARCH-0002](../research/0002-textkit-engine-spike.md)):

- POC (macOS 27): default is TextKit 2; `NSTextView(usingTextLayoutManager: false)` forces
  TextKit 1; TextKit 1 `setTemporaryAttributes` works for temporary rendering overlays.
- TextKit 2's dynamic rendering-attributes are documented-unreliable (won't refresh until a
  resize), plus viewport/scroll jank and silent TK1 fallback.
- Third-party views are TextKit 2-based and add a dependency.

## Decision

Use **TextKit 1 `NSTextView`**, created with `NSTextView(usingTextLayoutManager: false)` and
wrapped in an `NSViewRepresentable`. INC-02 applies live styling through `NSTextStorage` display
attributes: temporary attributes cannot provide the font and size changes required for headings,
bold text, and code blocks. This still protects INV-2 because the document saves the storage's
string, which attribute application never changes. The wrapper replaces the interim stock
`TextEditor` ([ADR-0007](0007-editor-surface-interim-texteditor.md)).

## Consequences

- **Positive:** stable TextKit 1 editing and layout behavior; avoids TextKit 2's documented
  rendering-attribute unreliability; no third-party dependency; display attributes leave the
  saved string and file bytes untouched.
- **Negative / costs:** TextKit 1 is the older engine and Apple's stated long-term direction is
  TextKit 2; some newer TK2-only features (e.g. certain Writing Tools animations) are
  unavailable; we own the `NSViewRepresentable` bridge (focus, undo, first-responder).
- **Revisit trigger:** re-evaluate TextKit 2 if its dynamic rendering-attributes and viewport
  behavior become reliable; update or supersede this ADR then.

## Alternatives considered

- **TextKit 2 `NSTextView`:** rejected now — `setRenderingAttributes` unreliable for dynamic
  highlighting (our core need), plus viewport jank.
- **Third-party (STTextView / TextViewPlus):** rejected — TextKit 2-based (same concerns) and a
  new dependency, against keeping dependencies minimal.
