# COR-29 — Instrumentation coverage and honest gates

- **Status:** Approved; not implemented
- **Delivers:** REQ-114, REQ-115

## Scope

The diagnostic plumbing is sound — a closed payload type makes content leakage unrepresentable, a
non-main fault route survives a stalled main actor, repeated events collapse with counts, and
faults never collapse. What is wrong is **what the plumbing is pointed at**: the process-level
runs exercise only document open and idle, one failure class is silently dropped, one gate is set
an order of magnitude above measured-healthy, and the latency budget stops before the work a user
actually perceives.

Measured at `88b7bd3`, `Scripts/smoke-screenshot.sh`, reproduced twice:
`diagnostics PASS (19 records, 2 host updates)`.

### 1. Local image resolution failures are unrecorded

`EditorSession.scheduleParse`:

```swift
if case .success(let desc) = LocalImageResolver.resolve(...) { descriptors.append(desc) }
```

There is no `else`. `LocalImageResolveFailure` has eight typed cases — `remoteURL`,
`missingFile`, `encodedFileTooLarge`, `unsupportedType`, `corrupt`, `oversizeDimensions`,
`decodeFailed`, `staleVersion` — and none of them reaches the run log. The user sees a
placeholder; the run log says nothing at all.

### 2. The livelock gate has ten-fold slack

Both smoke scripts default `SMOKE_HOST_UPDATE_THRESHOLD=20`. ENGINEERING §12 states a healthy run
settles at 2, and 2 is what both measured runs produced. A nine-fold regression in idle host
updates passes silently — on the exact metric that exists to catch a self-feeding reconciliation
loop, the defect fixed in `0b53a5f`.

### 3. Process-level verification never exercises an edit

Both scripts open a fixture and idle. No keystroke, no mode switch, no command, no undo, no image
placement. Consequences:

- `editRefused` — the event that would have surfaced COR-25 and every command in COR-26 — cannot
  fire in a process-level run;
- `nativeInputCallback` has zero samples, and the verifier only requires `parseProjection` to be
  non-empty;
- the ARC-Q02 synchronous-transition invariant is never observed at process level.

### 4. The latency budget stops before layout

`WYSIWYGEditor.swift:282` starts the `nativeInputCallback` sample and a `defer` ends it when the
`shouldChangeTextIn` delegate returns — after `storage.endEditing()`, before TextKit performs
glyph generation, layout, or drawing. On the TextKit 1 compatibility path with `NSTextTable` and
image attachments, that layout is the most likely source of perceived jank, and no metric covers
it. The five metrics cover every phase the app owns and none that TextKit owns.

### 5. Budgets are duplicated and untied

`PerformanceSampler.flush()` hard-codes `8_000_000` / `16_000_000` / `100_000_000`. REQ-090 and
ARC-Q05 state the same numbers in prose. Nothing ties them, so they can drift silently.

### 6. Two smaller honesty gaps

- `Scripts/smoke-screenshot.sh` passes `--allow-fault mainActorStall`. The justification is real
  (`screencapture` freezes the target process), and `Scripts/smoke-test.sh` compensates by
  tolerating nothing — but the run taken at *every* increment close is blind to the single most
  important jank fault, and that should be stated in ENGINEERING rather than only in a script
  comment.
- `Scripts/verify-smoke-log.py` asserts `len(reconciliations) == 1`. That freezes the current
  startup ordering into the gate: a correct future change that legitimately applies a second
  reconciliation would fail the gate for being correct.

## Requirements and invariants

- **REQ-114 (new):** WHEN a referenced local image fails to resolve for display, the system shall
  record its typed failure class without recording file names, paths, or image data.
- **REQ-115 (new):** WHEN process-level verification runs, it shall additionally exercise at
  least one accepted text insertion and one accepted semantic command, and shall assert on the
  resulting structured records.
- **REQ-116 (new):** The system shall record a bounded periodic summary of WYSIWYG layout
  duration alongside the existing metrics.
- REQ-089, ARC-016: payloads remain numbers, booleans, and code-defined symbols only.
- REQ-096, ARC-Q11: the idle-settle guard remains a fault route.
- REQ-090, REQ-103, ARC-Q05, ARC-020: metric boundaries stay honestly named and lifetime-owned.
- REQ-098, REQ-104, ARC-Q12, ARC-Q13: the process-level carve-outs are extended in scope but not
  in kind — still structured-record assertions only.
- **Architecture impact: ENGINEERING §12 amendment**, in the implementing change, to add the
  layout metric, restate the screenshot run's fault tolerance, and record the tightened
  threshold. No `ARC-###` invariant changes.

## Production route

Modify:

- `Markdown Editor/EditorTrace.swift` — add `imageResolutionFailed(reason:)` over the existing
  `LocalImageResolveFailure` vocabulary; add `.layoutApplication` to `PerformanceSampler.Metric`.
- `Markdown Editor/JSONLinesEditorTrace.swift`, `Markdown Editor/DiagnosticRecord.swift`,
  `Markdown Editor/DiagnosticValue.swift` — symbols for the new reasons.
- `Markdown Editor/EditorSession.swift` — record the failure branch in `scheduleParse`.
- `Markdown Editor/PerformanceSampler.swift` — add the layout metric and its budget; replace the
  hard-coded budget `switch` with one exported table.
- `Markdown Editor/WYSIWYGEditor.swift` — sample layout by forcing and timing glyph layout for
  the affected range after applying a patch, at the same place the patch is applied.
- `Markdown Editor/Markdown_EditorApp.swift` — extend the smoke run to perform one scripted
  insertion and one scripted semantic command **through the ordinary production routes**, then
  settle and exit. This drives the app's own model, not its UI: no click, no key event, no
  accessibility, no screen automation.
- `Scripts/verify-smoke-log.py` — assert the new records; replace the exact
  `reconciliations == 1` equality with a bounded assertion; assert the run's reported budgets
  match the exported table.
- `Scripts/smoke-test.sh`, `Scripts/smoke-screenshot.sh` — default threshold `20` → `4`.

Delete: the inline budget `switch` in `PerformanceSampler.flush()`.

## Implementation phases

1. Add `imageResolutionFailed`; wire the `else` branch; assert with the deliberately broken
   fixture reference COR-28 adds.
2. Export the budget table; assert code and REQ-090 agree in a test that reads the table.
3. Add the layout metric and its boundary; record Release evidence for it.
4. Extend the smoke run with one insertion and one command; extend the verifier.
5. Tighten the threshold to 4; rehearse the gate failing at 1 to prove it still discriminates.
6. Amend ENGINEERING §12; reconcile requirements; delete this plan.

## Automated non-UI proof

- `imageResolutionFailed` is recorded once per failing reference, carries only a symbol, and is
  covered by the existing `editorTraceOmitsSourceSelectionAndPathStrings` privacy sweep.
- `Scripts/check-instrumentation-coverage.sh` covers the new event by construction.
- A test asserts every `PerformanceSampler.Metric` has a budget in the exported table, so a new
  metric cannot ship unbudgeted.
- The verifier's new assertions are rehearsed failing: a build with the insertion removed must
  fail, and the threshold must be rehearsed failing at a lowered value, exactly as REQ-098's
  existing rehearsal does.
- `Scripts/test-verify-smoke-log.sh` gains fixtures for a missing insertion record, a missing
  command record, an unbudgeted metric, and an over-threshold host-update count.

## Instrumentation and performance evidence

This increment *is* the instrumentation evidence. Additionally record, in Release on the approved
100,000 UTF-16 corpus: `layoutApplication` count, median, and p95, and confirm the existing
`nativeInputCallback` p95 < 8 ms gate is unchanged by the added sampling. Zero executed samples
for any metric remains a failing proof.

## Failure and rollback behavior

The scripted smoke insertion and command run through the ordinary accepted-edit route; if either
refuses, the run records `editRefused` and the verifier fails the gate — which is the intended
behavior, since an ordinary command refusing is exactly the class of defect this increment exists
to make visible. Layout sampling must never itself force layout the app would not otherwise
perform; if the measurement cannot be taken without changing behavior, the metric is dropped
rather than made misleading, and that outcome is reported rather than quietly absorbed.

## Deletion and conformance gate

- Prove no second instrumentation route exists (`os_log` still unused for editor events).
- Prove exactly one budget table exists and `PerformanceSampler` has no inline budget literals.
- Prove the smoke extension drives no UI: no XCUITest target, no accessibility API, no synthetic
  events — assert by source inspection, the same proof `ARC-014` already uses.
- Both gate scripts pass; both smoke scripts pass at threshold 4 and rehearse-fail at 1; delete
  this plan in the implementing change.
