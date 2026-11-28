# 0008. The product is photographed by naming a screen at launch, not by driving the UI

- Status: accepted
- Date: 2026-08-29

## Context and problem

**Appearance is forced through the argument domain**, not by application code: the product has no
appearance setting of its own and must not grow one to be photographed. Measured, not assumed:
`-AppleInterfaceStyle Light` is a no-op (it is only tested against the string `Dark`), so the
light scenes pass `-NSRequiresAquaSystemAppearance YES`, which does force light on a dark-mode
machine — window luma 240 versus 44.

**Every image is gated on its own run's log.** A scene whose structured diagnostics fail is
reported and its PNG is not copied into the repository. The first run of the script found this
worth having in the opposite direction: killing the app straight after the capture lost the
end-of-run performance summaries, and all five scenes were correctly reported unhealthy while the
pixels were fine. The fix was to let each run reach its own bounded self-termination.

## Decision drivers

**Criteria**, from vision.md's objective ordering: (1) the verification carve-outs in CLAUDE.md §4
must survive intact — no UI automation; (2) honesty — a committed image must not claim a render
the log says was unhealthy; (3) ownership clarity and absence of duplicate paths; (4)
implementation and maintenance cost; (5) the product must not grow surface it does not need in
order to be photographed.

## Considered options

**Alternatives.**

- **A — name the scene at launch, apply it in-process** (chosen). Reuses the exact handle
  `exerciseSmokeEdits` already uses: the window's toolbar delegate holds the window-scoped
  `EditorCommandController`, so a scene reaches the session the same way a toolbar click does.
  No synthetic events, no accessibility, no screen automation, so §4 holds unchanged. Costs one
  declared environment variable, gated on the smoke argument like every other, and one enum the
  gallery script's scene table is compared against by a test.
- **B — drive the UI with `cliclick`/accessibility.** Photographs any screen with no product
  change at all, and is the only option that could reach a menu being pulled down. Rejected: it
  is precisely the automation §4 exists to forbid, and it would be the second path into the
  command model, competing with the first.
- **C — capture only what a launch already reaches.** No product change, no new variable — but
  the gallery would then be five pictures of the same screen, which does not answer the ask.
- **D — do nothing; keep the single REQ-104 review screenshot.** It is a temp file for one
  reviewer at one moment, and the repository still contains no picture of the product.

## Decision

**Decision.** `Scripts/screenshots.sh` produces a committed gallery of the product's important
screens in `docs/screenshots/`. Screens an ordinary launch does not reach — Source mode, the link
sheet — are named at launch with `MARKDOWN_EDITOR_SMOKE_SCENE` and presented by the application
itself through its window-scoped command routes (REQ-151). The gallery is documentation, not a
gate: `Scripts/check.sh` does not run it.

## Consequences

**Where the chosen option is worse.** It puts three lines of photography-shaped behaviour in the
shipping binary, and `LaunchSurface` grows a sixth variable. B would have kept the product clean
at the cost of the rule that keeps the test suite trustworthy; that trade is the wrong way round.
The mitigation is the same one COR-90 chose for the rest of the launch surface: the variable is
declared, enumerated, gated on `--diagnostic-smoke-exit`, and proved unable to change document
content.

## Confirmation

REQ-144 and REQ-151's tests (`ScreenshotSceneTests`, `LaunchSurfaceTests`) prove the scene variable is gated on the smoke argument, cannot change document content, and that every declared scene is in the gallery.

## Retirement proof

A UI-driving tool that §4 of CLAUDE.md admits as a gate, or a product appearance setting that makes the argument-domain trick unnecessary.

## Reversal plan

Delete the scene variable, its enum and `Scripts/screenshots.sh`; the gallery stays as committed images.
