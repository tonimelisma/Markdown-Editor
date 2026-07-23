# RESEARCH-0003 — Editor performance, jank, and concurrency

- **Date:** 2026-07-22
- **For:** INC-02 (live-styled source) and the editor's long-term architecture
- **Type:** online research (deep dive)
- **Status:** Done
- **Outcome:** A concurrency + highlighting pipeline that keeps typing on the main thread with
  nothing else in the path, computes styling off-main, and applies it as display-only
  `NSTextStorage` attributes (never the string). Recorded as [ADR-0010](../decisions/0010-concurrency-highlighting-pipeline.md)
  (pipeline) and [ADR-0009](../decisions/0009-regex-live-highlighting-engine.md) (regex engine).

## Question

How do we make live syntax highlighting feel instant and never introduce jank, and how exactly
should we structure main-actor / async / background work in a Swift 6 + AppKit `NSTextView` app?

## 1. The input-latency model

Per Pavel Fatin, [*Typing with pleasure*](https://pavelfatin.com/typing-with-pleasure/):
total latency = input (keyboard ~14 ms) + **processing (software, the part we control)** +
output (display ~12 ms). **Jank** (jitter) is worse than steady latency because it corrupts the
brain's predictive motor model — you needn't consciously perceive it to be slowed by it.

- **Budget:** ideal processing < 5 ms; realistic target 10–20 ms. IntelliJ's "zero-latency
  typing" cut average latency 24.7 ms → **2.9 ms** by rendering the keystroke *first* and making
  everything else async.
- **Jank sources:** secondary work (highlighting, spell-check, inspections) done *synchronously*
  on the keystroke; GC pauses; redundant repaints (latency that scales with file/window size ⇒
  over-painting); double-buffering / V-Sync; background I/O stealing the main thread.
- **Universal fix:** render the typed character with nothing else in the path; do all secondary
  features async; don't repaint more than the changed region.

## 2. How real editors architect around it

| Editor | Buffer | Concurrency | Highlighting |
|---|---|---|---|
| Zed | Rope + SumTree | Rust; entities on one foreground thread (lock-free) + heavy background parallelism; GPU render; 8 ms/120 fps, 2 ms latency | tree-sitter incremental |
| VS Code | Piece table | tokenize on background worker; DOM virtualization (visible lines) | TextMate / tree-sitter |
| IntelliJ | — | keystroke first, everything async ("zero-latency mode") | async |
| **CotEditor** (native Swift/AppKit — closest to us) | NSTextStorage | `NSTextView` + custom `NSLayoutManager`; **background highlighting** above a size threshold; re-apply after edits | hybrid regex + tree-sitter |
| CodeEdit / STTextView | NSTextStorage | async highlight provider, viewport-based, apply on main (ChimeHQ's Neon) | tree-sitter |

**Data structures** (gap buffer / piece table / rope): we don't own the buffer — `NSTextStorage`
is our store (NSString-backed, contiguous-ish). Fine to low-MB; it's *why* huge files slow down
(it's not a rope), so the mitigation is viewport-limited work + a size threshold, not replacing
the buffer.

**Highlighting engines:** tree-sitter is incremental and grammatical (why serious *code* editors
use it). For **Markdown source**, regex is the pragmatic standard (Marklight, HighlightedTextEditor)
and covers our Tier-2 extensions — hence [ADR-0009](../decisions/0009-regex-live-highlighting-engine.md).
tree-sitter-markdown stays a future option (esp. for in-fence language coloring).

## 3. macOS / Swift mechanics that bite

- **Styling is display state, not the string — that's what protects INV-2.** We save the
  `NSTextStorage` *string*, which attribute styling never changes. `NSLayoutManager`'s
  `setTemporaryAttributes` is purely display but can't change font/size, so we style via
  `NSTextStorage` attributes instead — still string-safe, applied from `textDidChange` (not
  `processEditing()`) and batched in `beginEditing()`/`endEditing()` to avoid caret jumps
  ([Tietze](https://christiantietze.de/posts/2017/11/syntax-highlight-nstextstorage-insertion-point-change/)).
- **Never highlight inside `processEditing()`** — `NSTextStorage` unions `edited(...)` ranges,
  so the selection-fix runs on the widened range and **jumps the caret**. Highlight from
  `textDidChange` (a separate layout pass) instead.
- **Swift 6 main-actor friction:** AppKit views are `@MainActor`; `NSTextInputClient` isn't
  ([forum](https://developer.apple.com/forums/thread/758011)). Avoid by keeping the `NSTextView`
  subclass minimal.
- **`NSViewRepresentable` update loops:** `updateNSView` fires multiple times; delegate→binding→
  `updateNSView` can loop. Fix: `Coordinator` holds the `Binding`, guard with a programmatic-update
  flag + compare-before-set ([forum](https://developer.apple.com/forums/thread/749620)).

## 4. Engineering spec (adopted → ADR-0010)

**Threading contract**
- **Main actor** owns all AppKit: `NSTextView`, `NSTextStorage`, `NSLayoutManager`, delegate
  callbacks, and applying `NSTextStorage` attributes. Per-keystroke main-thread work = the native
  text insertion only.
- **Highlight compute is always off-main:** `actor MarkdownHighlighter` holds the once-compiled
  `NSRegularExpression`s; `func tokens(for text: String, version: Int) -> [Token]`, `Token =
  (NSRange, TokenStyle)` — only `Sendable` values cross the boundary (String in, value tokens out).
- **Pipeline:** `textDidChange` (main) → bump `version` → `Task { await highlighter.tokens(...) }`
  → back on `@MainActor`, **discard if `version` is stale** (coalesces async races) → apply
  `NSTextStorage` attributes (display-only; the string is never changed ⇒ INV-2).
- **Debounce + viewport-first:** coalesce rapid edits; style the visible range + margin first,
  then the rest. Above a size threshold, cap/disable live highlighting.
- Only invalidate/repaint changed ranges.

## Sources

[Typing with pleasure](https://pavelfatin.com/typing-with-pleasure/) ·
[Zed rope/SumTree](https://zed.dev/blog/zed-decoded-rope-sumtree) ·
[Editor data structures](https://gauravsarma1992.medium.com/the-data-structures-behind-text-editors-gap-buffers-piece-tables-ropes-and-crdts-8df38a999cce) ·
[tree-sitter](https://tree-sitter.github.io/tree-sitter/) ·
[CotEditor perf issue](https://github.com/coteditor/CotEditor/issues/1136) ·
[Tietze: highlighting & selection](https://christiantietze.de/posts/2017/11/syntax-highlight-nstextstorage-insertion-point-change/) ·
[NSTextInputClient + Swift 6](https://developer.apple.com/forums/thread/758011) ·
[NSViewRepresentable loops](https://developer.apple.com/forums/thread/749620)
