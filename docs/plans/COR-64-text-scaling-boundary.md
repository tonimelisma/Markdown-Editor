# COR-64 — Record the Accessibility Text Size boundary and guard against a false claim

- **Status:** Approved; not implemented
- **Requirements:** new REQ-140 (the system shall not adopt an AppKit text-scaling API it cannot
  verify honors the system Accessibility Text Size preference, and shall record this boundary)
- **Delivers:** REQ-140
- **ARC invariants:** new ARC-Q24 (no production font role resolves through an unverified
  text-scaling API). No architecture change.

## Context

`docs/research/DISC-08-macos-text-scaling.md` (written alongside this plan) finds that AppKit's
`NSFont.preferredFont(forTextStyle:)` does not reliably reflect macOS's Accessibility ▸ Display ▸
Text Size setting for third-party apps, and that no third-party-observable API exists at all for
that setting — unlike Light/Dark appearance and the three settings `COR-65` covers, all of which
are documented and observable. Adopting the API would produce a static font that silently stops
matching the system value, which is the same "asserted the attribute, not the behavior" shape
`COR-27` already corrected once for line-fragment geometry and `CLAUDE.md` §4 now names generally.

This increment is not a feature. It is the smallest honest response to a researched gap: **write
down** that the gap exists and is not an oversight, and **guard** against a future contributor
cargo-culting the iOS API into this codebase under the belief that it works here.

## Production changes

None. This increment is documentation plus one structural test.

## Phase 1 — the guard

```swift
// Verifies: REQ-140 — no production font role claims Dynamic Type conformance the platform cannot
// verify. DISC-08 found no observable API for AppKit third-party apps to read or react to
// Accessibility Text Size; calling `NSFont.preferredFont(forTextStyle:)` for editor content would
// be an unverifiable claim, not a working feature.
@Test func noProductionFileCallsPreferredFontForTextStyle() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Markdown Editor")
    let swiftFiles = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "swift" }
    for file in swiftFiles {
        let text = try String(contentsOf: file, encoding: .utf8)
        #expect(!text.contains("preferredFont(forTextStyle:"), "\(file.lastPathComponent) calls an unverified text-scaling API — see DISC-08")
    }
}
```

This is a source-conformance test in the shape of `noSecondaryMarkdownScannerRouteExists` and
`returnInterceptionHasExactlyOneRoute` — reading production source text to prove an absence, not
a UI or accessibility-tree read, so it needs no `CLAUDE.md` §4 carve-out.

## Phase 2 — record the boundary

`REQUIREMENTS.md` gains REQ-140, `Done` on the guard test alone (a `Correction`-shaped requirement
that is satisfied by *not doing* something is legitimately proved by an absence test — the same
class as `noUITestTargetInProject`). `ENGINEERING.md` §16 (Current risks) gains one line pointing at
`DISC-08` so a future architecture review does not re-discover this from scratch. `ROADMAP.md`'s
Post-MVP backlog already lists *"Additional themes and user-selectable typography options beyond
the approved default"* — this increment adds a one-line cross-reference from that backlog item to
`DISC-08`/REQ-140, so a future decision to build in-app text scaling starts from the researched
platform boundary instead of re-deriving it.

## Proof

- `noProductionFileCallsPreferredFontForTextStyle`. **Rehearsed failing** by adding a call to
  `NSFont.preferredFont(forTextStyle: .body)` in a scratch production file and observing the test
  turn red, then removing it.

## Instrumentation and performance evidence

None — no runtime code path is added.

## Failure / rollback

Nothing here can affect runtime behavior; the only production-adjacent artifact is a test. Revert
is one commit.

## Deletion / conformance gate

- No production file calls `NSFont.preferredFont(forTextStyle:`, enforced by the guard rather than
  by review.
- `docs/research/DISC-08-macos-text-scaling.md` is listed in `docs/research/README.md`.
- `Scripts/check-documentation-authority.sh` and `Scripts/check-proof-results.sh` pass.
