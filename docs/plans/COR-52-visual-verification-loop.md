# COR-52 — Visual and layout verification loop

- **Status:** Approved; not implemented
- **Requirements:** REQ-104 (screenshot verification — extended from one capture to a declared matrix), REQ-105, REQ-106, REQ-107
- **Delivers:** REQ-104, REQ-105, REQ-106, REQ-107
- **ARC invariants:** ARC-Q13 amended from "exactly one screenshot" to a declared passive capture matrix — an architecture change, argued under `ENGINEERING.md` §15 below. ARC-Q14 and ARC-Q15 gain laid-out-geometry golden proofs. ARC-014 unchanged: no capture drives, reads, or asserts on the UI.

## Context

Today's visual evidence is exactly one capture: WYSIWYG, Light appearance, 720 pt wide.

**Dark mode has never been visually reviewed. Source mode has never been visually reviewed.** VISION
requires both appearances work. ARC-Q14 claims Light and Dark are proven, and its proof is an
attribute assertion — the same class `CLAUDE.md` §4 already rules insufficient for claims about what
the reader sees ("a proof asserting an attribute value does not discharge a requirement about what the
user sees").

A single screenshot is also the wrong instrument for regression: it is reviewed by eye once and then
replaced, so a one-point indentation drift is invisible unless someone happens to notice.

## Phase 1 — layout goldens

A component test constructs `NSTextView` directly, forces layout, and serialises **geometry** rather
than pixels:

```text
block[3] kind=heading(2) range={45,14}
  lineFragment[0] origin={28.0,120.0} size={664.0,29.0}
  font=system-semibold-24.0 spacingBefore=21.5 spacing=7.0
  paragraphStyle headIndent=0.0 firstLineHeadIndent=0.0 textBlocks=[]
```

over `{fixtures} × {480, 720, 1200 pt} × {light, dark}` into
`Tests/Goldens/<fixture>-<width>-<appearance>.txt`, diffed against committed goldens.

**Normalisation is the whole design.** A golden that fails on an OS point release is a golden nobody
trusts, and an untrusted gate gets disabled — at which point there is no visual evidence at all.
Therefore:

- font descriptors as `family-traits-size`, never PostScript names or version-bearing identifiers;
- geometry rounded to 0.5 pt;
- colours as **semantic names** (`labelColor`, `separatorColor`) wherever resolvable, never RGBA —
  RGBA legitimately changes with appearance and OS version;
- anything derived from the machine (screen scale, container height, backing store) omitted entirely.

`Scripts/update-goldens.sh` regenerates them. A golden change must appear in the PR diff, which is the
point: typography regressions become reviewable text instead of something a reviewer must spot in an
image.

This is a component test by direct construction — no UI automation, no screen reading — so it sits
inside `CLAUDE.md` §4's ordinary rules and needs no carve-out.

## Phase 2 — the screenshot matrix

Extend the ARC-Q13 capture from one image to a declared matrix. Still passive, still window-only,
still never the full screen.

| Axis | Values |
| --- | --- |
| mode | WYSIWYG, Source |
| appearance | Light, Dark |
| width | 720 (product default), 1200 (wide) |

Eight captures, composed into one contact sheet by `Scripts/contact-sheet.sh` — implemented as a small
Swift script using `NSImage` compositing, so no new dependency enters the project — and delivered as
the increment's visual evidence.

Mode and appearance are set through COR-45's benchmark driver (`--mode source --appearance dark`),
which assigns `NSApp.appearance` and calls `session.setMode`. No synthetic events, no pixel reads, no
accessibility API.

**This is an architecture change and is argued as one** (`ENGINEERING.md` §15):

1. *Counterexample:* two entire surfaces — Source mode and Dark appearance — have never been looked
   at, while ARC-Q14 asserts Dark is proven.
2. *Evidence:* the August review's single capture, and the absence of any Dark or Source artifact in
   the repository's history.
3. *Options:* keep one capture and accept the blind spots; rotate the captured surface per increment
   (which makes coverage depend on the order increments land); or capture the declared matrix.
4. *Approval:* recorded with this plan.
5. *Atomic update:* ARC-Q13 and REQ-104 amended in the implementing change.
6. *Discriminating proof:* the contact sheet, which under the old rule could not exist.
7. *Displaced path deleted:* the single-capture code path is replaced, not kept alongside.

## Phase 3 — screenshot diffing, as an aid and never a gate

Compute a per-pixel difference against the previous increment's contact sheet with a tolerance, and
emit a highlighted diff image.

**Report it; do not fail on it.** Font rasterisation legitimately changes across OS versions, and a
gate that cries wolf on every point release is a gate that gets switched off. Phase 1's goldens are
the gate; the diff is what tells a human where to look.

## Proof

- `layoutMatchesItsGolden`, parameterised over the full `{fixture × width × appearance}` case set.
  **Rehearsed failing** by nudging `MarkdownTypography.listIndent` by 1 pt: every list golden must
  move and nothing else may — which simultaneously proves the goldens are sensitive and that they are
  not over-broad.
- `goldenSerialisationOmitsMachineSpecificValues` — a golden generated on two different container
  configurations is byte-identical.
- `contactSheetContainsEveryDeclaredCell` — the matrix is closed; a missing capture fails rather than
  producing a smaller sheet.
- `captureNeverIncludesContentOutsideTheApplicationWindow` — the existing REQ-104 guarantee, re-proved
  for each of the eight captures.

## Instrumentation and performance evidence

The capture matrix runs eight application launches instead of one. Record the wall-clock cost in
`Scripts/smoke-screenshot.sh`'s output; if it exceeds two minutes, run appearance and width axes
within a single launch (both are settable at runtime) and record that optimisation rather than
silently trimming the matrix.

## Failure / rollback

Verification-only; nothing here ships in the application binary except the benchmark driver's existing
`--mode`/`--appearance` arguments, which are unreachable from an ordinary launch.

The realistic failure is golden churn — goldens that change for reasons unrelated to the change under
review. The normalisation rules above are the mitigation, and
`goldenSerialisationOmitsMachineSpecificValues` is the proof that they hold. If goldens still prove
unstable across a macOS point release, reduce the serialised set to geometry alone (dropping fonts and
colours) and record the reduction; a smaller stable gate beats a larger ignored one.

## Deletion / conformance gate

- The single-capture path in `Scripts/smoke-screenshot.sh` is replaced, not retained alongside the
  matrix.
- No golden contains an RGBA value, a PostScript font name, or a machine-derived number — enforced by
  `goldenSerialisationOmitsMachineSpecificValues` rather than by review.
- ARC-Q13 and REQ-104 are amended in the same change that lands the matrix.
- `Scripts/check-documentation-authority.sh` and `Scripts/check-proof-results.sh` pass.
