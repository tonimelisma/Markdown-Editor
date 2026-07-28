# COR-11 — Hermetic diagnostics directory and process smoke verification

- **Status:** Approved; not implemented
- **Requirements:** REQ-097, REQ-098
- **Architecture impact:** none to ARC-001–016. Adds quality scenario ARC-Q12 (added to
  `docs/ENGINEERING.md` on this branch when implemented).
- **Approved decisions:** smoke-exit mechanism is a launch argument
  (`--diagnostic-smoke-exit`), not `osascript`. The CLAUDE.md §4 carve-out wording below is
  approved as written.

Do this increment first. It is small, and it gives every later increment in this initiative a
real regression net for the class of bug that caused this whole effort (a SwiftUI update loop
that no unit test can reach, because unit tests never run the real view graph).

## CLAUDE.md §4 carve-out (approved wording)

Add to `CLAUDE.md` §4, as an explicit, narrow exception to "No manual or UI tests, ever":

> Process-level smoke verification is permitted: launching the built application on a fixture and
> asserting only on structured diagnostic records it writes. It must not drive, read, or assert on
> any user interface, must not use screen automation or accessibility inspection, and must not be
> the sole proof of any requirement. XCUITest and screen automation remain forbidden.

## Requirements

- **REQ-097** — The system shall write diagnostics to a directory named by the
  `MARKDOWN_EDITOR_DIAGNOSTICS_DIR` environment variable when it is set, so verification runs
  cannot read, prune, or pollute the user's production diagnostics.
- **REQ-098** — WHEN process-level smoke verification runs, the system shall open a fixture
  document, settle within a bounded number of editor-host view updates, record no `error` or
  `fault` diagnostic, and write a terminating record.

`ARC-014` ("No production or verification claim depends on manual or UI testing") is unchanged
and still true — the smoke test is automated and reads no UI.

## Files

**Modify**
- `Markdown Editor/DiagnosticLog.swift` — environment override in `defaultDirectory(hostKind:)`.
- `Markdown Editor/Markdown_EditorApp.swift` — smoke-exit launch argument.
- `CLAUDE.md` — §4 carve-out (above).
- `docs/ENGINEERING.md` — §11 (verification note) and §12 (ARC-Q12).
- `docs/REQUIREMENTS.md` — flip REQ-097/098 to Done with implementation/verification.

**Add**
- `Scripts/smoke-test.sh`
- `Scripts/Fixtures/smoke-basic.md`
- test cases in `Markdown EditorTests/DiagnosticLogTests.swift`

## Phase 1 — directory override

In `DiagnosticLog.defaultDirectory(hostKind:)`, before computing the Library path:

```swift
// REQ-097: verification runs get their own directory so they cannot prune production evidence.
if let override = ProcessInfo.processInfo.environment["MARKDOWN_EDITOR_DIAGNOSTICS_DIR"],
   !override.isEmpty {
    return URL(fileURLWithPath: override, isDirectory: true)
}
```

Keep the existing `unitTest` subdirectory behavior for when the variable is absent.

**Test**: refactor `defaultDirectory` to `defaultDirectory(hostKind:environment:)` with a
defaulted argument so the test is deterministic and parallel-safe (no process-environment
mutation). Name it `diagnosticsDirectoryHonoursEnvironmentOverride`.

## Phase 2 — smoke exit

In `MarkdownAppDelegate`, add:

```swift
/// REQ-098: process-level smoke verification. Opens, settles, closes the log, exits.
static var isSmokeRun: Bool {
    ProcessInfo.processInfo.arguments.contains("--diagnostic-smoke-exit")
}
```

In `applicationDidFinishLaunching`, when `isSmokeRun`, schedule a bounded settle then terminate:

```swift
if Self.isSmokeRun {
    Task { @MainActor in
        try? await Task.sleep(for: .seconds(2))
        DiagnosticLog.shared?.finishSynchronously()
        NSApp.terminate(nil)
    }
}
```

`applicationWillTerminate` already calls `finishSynchronously()`; verify (do not assume) that it
is idempotent because `finish()` guards on `closed`.

## Phase 3 — the script

`Scripts/smoke-test.sh` builds Debug, launches the binary directly (not through `open`, which does
not reliably pass environment/arguments together) with `MARKDOWN_EDITOR_DIAGNOSTICS_DIR` set and
`--diagnostic-smoke-exit <fixture>`, polls for the run file, then asserts with a small Python
snippet:

- schema version and `run.host == "production"`;
- sequence numbers strictly increasing;
- a `documentOpened` record exists;
- `hostUpdateEnded` count `<= 20` (livelock guard — healthy build observed at 2; a defective
  build produced thousands per second);
- no `error`/`fault` level records;
- the last record is `runEnd`.

Verify which of "launch via `open -g -j`" vs "launch the binary directly" actually stays
non-frontmost before finalizing the script — this is the one part of this increment with real
implementation uncertainty. Do not sleep a fixed amount for the run file; poll.

## Proof

- `diagnosticsDirectoryHonoursEnvironmentOverride` (unit).
- The script itself. Rehearse a real failure before trusting it: temporarily lower the threshold
  to `<= 1` and confirm the script exits non-zero, then restore `<= 20`.
- Record the measured wall-clock time in the PR description.

## Rollback

Self-contained. Deleting the script and reverting the two Swift edits restores prior behavior.
