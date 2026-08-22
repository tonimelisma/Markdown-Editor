# COR-83 Stage 0 — process leak tooling decision

- **Authority:** evidence only. Records which branch of the plan's decision table was selected.
- **First researched:** 2026-08-22
- **Last verified:** 2026-08-22
- **Environment:** macOS 27.0 (build 26A5416b), Darwin 27.0.0, arm64, Xcode-beta 27.0 (27A5228h),
  Debug build of `Markdown Editor.app`
- **Refresh triggers:** a macOS or Xcode major upgrade, a change to `Scripts/smoke-test.sh`'s launch
  arguments, or any change to how the app terminates.

## Probes

Both tools named by the plan are present:

```
/usr/bin/leaks            (leaks --atExit -- <command>)
xcrun xctrace version     27.0 (27A5228h)
```

`leaks -atExit` was run three times over the shipping binary with the smoke launch arguments —
`-ApplePersistenceIgnoreState YES --diagnostic-smoke-exit <fixture>`, with
`MARKDOWN_EDITOR_SMOKE_EXIT_SECONDS`, `MARKDOWN_EDITOR_SMOKE_EXERCISE_EDITS` and
`MARKDOWN_EDITOR_DIAGNOSTICS_DIR` set exactly as `smoke-test.sh` sets them.

| run | wrapper exit | leak line | `runEnd` in diagnostics |
| --- | --- | --- | --- |
| 1 | 0 | `Process 69277: 0 leaks for 0 total leaked bytes.` | yes |
| 2 | 0 | `0 leaks for 0 total leaked bytes` | yes |
| 3 | 0 | `0 leaks for 0 total leaked bytes` | yes |

Two properties matter and both hold:

- **App exit is preserved.** The app still reaches its own clean shutdown under the wrapper — the
  diagnostic log contains `runEnd`, so `leaks` is not killing the process before its lifecycle
  completes, and the structured smoke assertions remain meaningful.
- **The count is machine-parseable.** The report ends in a fixed
  `Process <pid>: <n> leaks for <m> total leaked bytes.` line.

The report also carries a physical-footprint summary (65.0M, peak 96.2M) which is retained in the
raw report rather than parsed, since REQ-142 is about leaks.

## Decision

**Row 1 of the plan's decision table applies:** *"`leaks -atExit` preserves app exit and yields
machine-parseable leak count → integrate a strict wrapper around that route."*

`xctrace` was not pursued. Row 1 matched on first probe, and the plan's table selects the first
matching row rather than the best of several — running an unnecessary second probe would be
discovery the plan did not authorise.

## What was built

`Scripts/leak-smoke.sh` composes the existing launcher rather than duplicating it: it runs
`smoke-test.sh` under `leaks -atExit`, requires the smoke run's own structured assertions to pass,
parses the leak line strictly, and fails on a nonzero count, a missing count, an ambiguous report,
or a nonzero wrapper exit. `Scripts/test-leak-report-parser.sh` drives the parser over fixtures for
each of those failure shapes, so the parser is shown to discriminate rather than assumed to.

The raw report is retained at `$CHECK_DERIVED_DATA/leaks/report.txt` for inspection.

## Not automated in the ordinary gate

`Scripts/check.sh` does not run the leak check by default: it adds roughly a further app launch and
`leaks` attaches to a live task, which is slower and more environment-sensitive than the rest of the
gate. It is run explicitly (`Scripts/leak-smoke.sh`) and at release. This is stated rather than
hidden, because a check nobody runs proves nothing — see `docs/DECISIONS.md`.
