# COR-12 — Complete the trace vocabulary

- **Status:** Approved; not implemented
- **Requirements:** REQ-099
- **Architecture impact:** none.

Nine of 32 `EditorTraceEvent` cases are defined and mapped but never recorded in production. That
is worse than having no event: it reads like coverage in review and produces nothing in a log.

## Disposition table

Verify each against current code before acting; the disposition column is a recommendation, not a
foregone conclusion.

| Event | Disposition | Where to record it |
|---|---|---|
| `parseStarted` | wire | `EditorSession.scheduleParse`, at the top of the detached task, with `snapshot.sourceVersion` and UTF-16 count |
| `parseCompleted` | wire | same task, after `MarkdownParser.parse` succeeds — must hop to `MainActor` to reach `trace` |
| `parseCancelled` | wire | each `if Task.isCancelled { return }` early exit in that task |
| `compositionCancelled` | wire | `WYSIWYGTextView.WYSIWYGInputCoordinator.cancel()` |
| `compositionRefusedStale` | wire | `prepareCommit(currentVersion:)` when `isStale` is true |
| `availabilityChanged` | wire | `EditorSession.updateWYSIWYGModeState`, only when `availability` actually changed |
| `loadApplicationStale` | verify then wire or delete | look for a load-token staleness path in `MarkdownDocument`; if none exists, delete the event and its mapping/symbol |
| `mappingResult` | wire | `ProjectionCoordinateMap` conversion sites, at `debug`; if too chatty, delete instead |
| `mainActorStall` | already emitted | via `DiagnosticLog.shared?.record` in the app delegate, not through `EditorTraceEvent` — either route it through the trace for consistency or leave it and document why in ENGINEERING §11 |

`availabilityChanged` is the most valuable of these. "WYSIWYG went read-only and I don't know why"
is a user-visible symptom with, today, no log line. Record the transition, not the state, and only
on change:

```swift
func updateWYSIWYGModeState(_ mutate: (inout WYSIWYGModeState) -> Void) {
    noteModeStateMutation()
    var state = wysiwygModeState
    let before = state.availability
    mutate(&state)
    wysiwygModeState = state
    if state.availability != before {
        let editable: Bool
        if case .editable = state.availability { editable = true } else { editable = false }
        document?.trace?.record(
            .availabilityChanged(
                editable: editable,
                sourceRevision: document?.sourceVersion ?? 0
            )
        )
    }
}
```

`updateWYSIWYGModeState` is called from inside the reconciliation detector. Recording is not
publishing, so this is fine — but confirm `ReconciliationInvariantTests` still passes and that no
recursion is created through the trace sink.

## Requirement

- **REQ-099** — The system shall define no instrumentation event that is never recorded, so that
  the event vocabulary is an accurate description of what a run can report.

## The durable fix: make this impossible to regress

Add `Scripts/check-instrumentation-coverage.sh`, modeled on
`Scripts/check-documentation-authority.sh`. It extracts every case name from the
`EditorTraceEvent` declaration and fails if any has no production call site outside
`EditorTrace.swift` and `JSONLinesEditorTrace.swift`.

```bash
#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

failures=0
block="$(awk '/^nonisolated enum EditorTraceEvent/,/^}/' "Markdown Editor/EditorTrace.swift")"
cases="$(printf '%s\n' "$block" | rg -o '^    case (\w+)' -r '$1')"

while IFS= read -r name; do
    [[ -z "$name" ]] && continue
    hits="$(rg -l "\.$name\(|\.$name\b" 'Markdown Editor' \
        --glob '!EditorTrace.swift' --glob '!JSONLinesEditorTrace.swift' || true)"
    if [[ -z "$hits" ]]; then
        printf 'instrumentation-coverage: event never recorded: %s\n' "$name" >&2
        failures=$((failures + 1))
    fi
done <<<"$cases"

(( failures > 0 )) && { printf 'instrumentation-coverage: FAILED (%d)\n' "$failures" >&2; exit 1; }
printf 'instrumentation-coverage: PASS\n'
```

Add it to the increment lifecycle in `CLAUDE.md` §3 next to the documentation-authority check,
and to the build-unit gate step. Note that `.parseStarted(` and `.parseCompleted(` will match the
paren-form pattern; events with no associated values (`compositionCancelled`) need the `\b`
alternative — test both shapes before trusting the script.

## Files

**Modify:** `Markdown Editor/EditorSession.swift`, `Markdown Editor/WYSIWYGTextView.swift`,
`Markdown Editor/ProjectionCoordinateMap.swift` (or wherever conversion sites live — verify),
`CLAUDE.md` §3, `docs/REQUIREMENTS.md` (REQ-099 → Done).

**Add:** `Scripts/check-instrumentation-coverage.sh`,
`availabilityChangedRecordsOnlyOnTransition` test.

**Delete:** any event verified to have no honest call site (`loadApplicationStale` and/or
`mappingResult`, per the disposition table above) — its `EditorTraceEvent` case, its
`DiagnosticEventName`/`DiagnosticField` entries, and its `JSONLinesEditorTrace.map` arm, in the
same change. Update `everyTraceEventMapsToSymbolicPayload` accordingly.

## Proof

- The coverage script, demonstrated failing on a deliberately unwired event, then passing.
- `availabilityChangedRecordsOnlyOnTransition` — asserts that setting the same availability twice
  records once.
- Extend the smoke test (COR-11) to assert `availabilityChanged` appears for a document that
  starts unavailable and becomes editable.

## Rollback

Self-contained. Reverting the wiring and deleting the coverage script restores prior behavior;
any deleted dead event can be reinstated from Git history if a future increment needs it.
