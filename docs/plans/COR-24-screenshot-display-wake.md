# COR-24 — Reliable window-only screenshot capture after display sleep

- **Status:** Approved; not implemented

## Scope

Implement the existing REQ-104 / ARC-Q13 window-only screenshot proof reliably when the
local display was asleep. This plan does not change product behavior or architecture.

## Requirements and invariants

- REQ-104: capture exactly one image of the launched application's own window and review it.
- ARC-Q13: preserve a window-scoped capture; never fall back to full-screen capture.
- Architecture impact: none.

## Production route

Modify `Scripts/smoke-screenshot.sh` only. Before launching the smoke fixture, create a
bounded macOS `caffeinate` assertion that requests user activity and prevents display/idle
sleep for the smoke lifetime. The assertion is terminated by the script cleanup trap. The
existing PID-specific `find-window-id` and `screencapture -l<windowID>` route remains the
only capture route.

## Implementation phases

1. Add a bounded, cleanup-owned wake/keep-awake assertion to the screenshot verifier.
2. Preserve all current failure distinctions and explicit no-full-screen-capture rule.
3. Run the verifier after the display has been observed asleep; confirm it produces a non-empty
   PNG and clean structured diagnostics.
4. Review the captured application window and run documentation/instrumentation gates.

## Proof and failure handling

The regression proof is a prior failing `screencapture -l<windowID>` run while the display is
asleep followed by the verifier producing one non-empty, reviewed, PID-scoped window image
under the same condition. `caffeinate` is bounded to the smoke run and is explicitly killed on
all exits; any capture failure remains a failing verifier result rather than becoming a
full-screen fallback.

## Completion gate

Delete this plan in the implementing change. `Scripts/smoke-screenshot.sh` must retain exactly
one `screencapture -l<windowID>` capture route and no `-S`, `-R`, or unscoped screen capture.
