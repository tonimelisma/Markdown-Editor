# RESEARCH-0002 — SPIKE-01: text engine (TextKit 1 vs 2 vs third-party)

- **Date:** 2026-07-22
- **For:** SPIKE-01 (standalone spike; feeds INC-02)
- **Type:** native-API investigation (throwaway POC) + online research
- **Status:** Done
- **Outcome:** **TextKit 1 `NSTextView`** for the editor surface. The POC confirmed temporary
  attributes as a rendering mechanism; INC-02 subsequently established that full typography
  requires `NSTextStorage` display attributes while still preserving the saved string. Recorded
  in [ADR-0008](../decisions/0008-textkit1-nstextview-editor-engine.md) and ADR-0010.

> Spike per [ADR-0005](../decisions/0005-discovery-and-build-are-separate-units.md): POC code
> is throwaway (lived in the scratchpad, never merged). This doc + the ADR are the outputs.

## Question

Which text engine should back the editor once we need **live syntax highlighting** (INC-02
onward): TextKit 1 `NSTextView`, TextKit 2 `NSTextView`, or a third-party view?

## Method

- **POC** on the real toolchain (macOS 27 / Xcode 27): probe `NSTextView`'s default engine,
  the `usingTextLayoutManager:` selector, and whether TextKit 1 `setTemporaryAttributes`
  (rendering-only highlight) applies and is retrievable.
- **Online research** on the reliability of TextKit 2's rendering-attributes for dynamic
  highlighting.

## Findings

**POC (empirical, macOS 27):**

- Default `NSTextView` uses **TextKit 2** (`textLayoutManager != nil`).
- `NSTextView(usingTextLayoutManager: false)` **forces TextKit 1** (`layoutManager` present,
  no `textLayoutManager`) — a supported, one-line opt-out at init.
- TextKit 1 `layoutManager.setTemporaryAttributes(_:forCharacterRange:)` **applies and is
  retrievable** — the proven, rendering-only highlight mechanism (styles display without
  mutating text storage).

**Research:**

- TextKit 2's `setRenderingAttributes` / `addRenderingAttribute` for **dynamic subrange
  highlighting is documented-unreliable** — doesn't reliably refresh until a window resize
  ([Apple forums 817471](https://developer.apple.com/forums/thread/817471),
  [763670](https://developer.apple.com/forums/thread/763670)).
- Broader TextKit 2 editing issues (viewport/scroll jank, perf >~3k lines, silent fallback to
  TK1) — [Krzyżanowski](https://blog.krzyzanowskim.com/2025/08/14/textkit-2-the-promised-land/),
  [Michael Tsai](https://mjtsai.com/blog/2026/02/24/textedit-love/).
- Third-party views ([STTextView](https://github.com/krzyzanowskim/STTextView),
  [TextViewPlus](https://github.com/ChimeHQ/TextViewPlus)) are TextKit 2-based workarounds —
  inherit the concerns and add a dependency.

## Recommendation

**TextKit 1 `NSTextView`** via `usingTextLayoutManager: false`, wrapped in `NSViewRepresentable`
(per [ADR-0002](../decisions/0002-swiftui-first-appkit-where-needed.md)). The POC's temporary
attributes remain useful evidence about TextKit 1, but INC-02 uses `NSTextStorage` display
attributes because temporary overlays do not supply the necessary typography. Revisit TextKit 2
only if/when it matures.

## Decision (user-approved 2026-07-22)

Text engine → **TextKit 1 `NSTextView`**. See [ADR-0008](../decisions/0008-textkit1-nstextview-editor-engine.md).
