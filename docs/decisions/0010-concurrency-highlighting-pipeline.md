# ADR-0010 — Concurrency & highlighting pipeline

- **Status:** Accepted
- **Date:** 2026-07-22
- **Deciders:** Toni Melisma
- **Related:** [ADR-0008](0008-textkit1-nstextview-editor-engine.md) (TextKit 1),
  [ADR-0009](0009-regex-live-highlighting-engine.md) (regex); [RESEARCH-0003](../research/0003-editor-performance-and-concurrency.md); INC-02

> Living decision — the app-wide contract for how editing, highlighting, and concurrency interact.

## Context

Live highlighting must never introduce typing jank ([RESEARCH-0003](../research/0003-editor-performance-and-concurrency.md)):
the keystroke path must carry nothing but the native text insertion, and all secondary work must
be async. We're on Swift 6 + AppKit, where views are `@MainActor` and cross-thread work must be
`Sendable`.

## Decision

**Threading contract:**
- **Main actor owns all AppKit** — `NSTextView`, `NSTextStorage`, `NSLayoutManager`, delegate
  callbacks, and *applying* attributes. The only per-keystroke main-thread work is the native
  text insertion.
- **Highlight compute is always off-main**, modelled as `actor MarkdownHighlighter` holding the
  once-compiled `NSRegularExpression`s. Its API is `func tokens(for text: String) -> [Token]`,
  where `Token` contains only `NSRange` and `TokenStyle` value data. The actor boundary carries a
  `String` in and `Sendable` value tokens out — **no AppKit object crosses**.
- **Coalesced pipeline:** `textDidChange` (main) → bump a monotonic `version` → `Task { await
  highlighter.tokens(for: snapshot) }` → hop to `@MainActor` → **discard if `version` is stale
  or the text no longer matches the snapshot** → apply.
- **Apply styling via `NSTextStorage` attributes** (font, color, …). This is *display* state:
  it changes how text is drawn but **never the string** — which is what we save — so INV-2 holds
  (no file change). (`NSLayoutManager` temporary attributes were considered but can't change
  font/size, so they can't render headings or bold weight; storage attributes are required.)
  Applied from `textDidChange` (never inside `processEditing()`) and batched in
  `beginEditing()`/`endEditing()` to avoid caret jumps and coalesce notifications.
- **Debounce + cap:** coalesce rapid edits with a 120 ms debounce. Above 100,000 UTF-16 code
  units, cancel pending work and suspend live styling; do not synchronously walk the whole text
  storage to reset attributes. Viewport-first incremental styling remains a future optimization,
  not current behavior.
- **Counts are secondary work too:** `TextStatsComputer` is an actor. It scans a text snapshot
  off-main, checks cancellation while scanning, and publishes only the latest completed result.
- **`NSViewRepresentable`:** the `Coordinator` holds the `Binding`; guard update loops with a
  programmatic-update flag + compare-before-set.

## Consequences

- **Positive:** IntelliJ-style "keystroke first, everything async"; INV-2 safe by construction;
  Swift-6-clean isolation (pure `Sendable` compute, `@MainActor` apply); stale results can't
  clobber fresh ones.
- **Negative / costs:** actor hops and version bookkeeping; live styling deliberately stops above
  the cap; the threshold must be tuned against real documents.
- **Revisit trigger:** if the regex compute itself becomes the bottleneck, move to incremental
  (tree-sitter) rather than changing the threading contract.

## Alternatives considered

- **Synchronous highlight on keystroke:** rejected — the classic jank source.
- **`NSLayoutManager` temporary (rendering-only) attributes:** insufficient — they can't change
  font/size (no headings or bold weight). Storage attributes are display-only for our purposes
  (the string is never touched ⇒ INV-2), applied outside `processEditing()` to avoid caret jumps.
- **TextKit 2 rendering attributes:** rejected upstream in [ADR-0008](0008-textkit1-nstextview-editor-engine.md)
  (documented-unreliable for dynamic ranges).
