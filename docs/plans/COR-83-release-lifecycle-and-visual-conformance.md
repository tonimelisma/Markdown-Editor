# COR-83 — Release lifecycle and visual conformance

- **Status:** Approved; not implemented
- **Delivers:** REQ-142
Architecture impact: none; establishes reserved ARC-Q26 and strengthens ARC-Q13–ARC-Q17 evidence
Blockers: COR-69, COR-72, COR-73, COR-79, COR-81, COR-82
Executor: A junior developer may run Stage 0 and implement only its mechanically selected branch. Obtain senior review of the probe evidence before changing process verification.

## Outcome

Close the programme with repeatable leak/lifecycle evidence and component-level visual geometry over
the declared semantic, appearance, width, scale, and preference matrix. The required single passive
app screenshot remains human oversight, not a UI-test gate.

## Stage 0 decision probe

Probe `leaks -atExit -- <shipping-app smoke arguments>` and Instruments/xctrace availability against
the app's own structured smoke lifecycle.

| Observed outcome | Branch |
| --- | --- |
| `leaks -atExit` preserves app exit and yields machine-parseable leak count | Integrate a strict wrapper around that route |
| xctrace provides deterministic headless allocation/leak output and app exit | Integrate a pinned xctrace template/export parser |
| Neither is deterministic on the supported environment | Keep REQ-142 `Planned`, commit research, and finish only component lifecycle/visual proofs |
| No row describes the observation | Stop and return to discovery |

Commit environment/method/results to `docs/research/`, delete POC artifacts, and rewrite the remaining
phase before production script changes.

## Files and ownership

- Leak branch: add one `Scripts/leak-smoke.sh` plus fixture-tested parser; compose, do not duplicate,
  `smoke-test.sh` and `verify-smoke-log.py`.
- Lifecycle tests: sessions, samplers, display links, image tasks/caches, highlight tasks, parse tasks,
  diagnostic sinks, windows/documents, and observers must expose bounded shutdown.
- Visual component tests: build real AppKit text systems for each semantic block at narrow/default/
  wide widths, Light/Dark, 1×/2×/3×, Increase Contrast, and relevant Reduce preferences; assert line
  fragments, insets, bounds, clipping, attachment frames, and stable source.

## Implementation and proof

1. Add red retain/release tests with weak sentinels and deterministic cancellation/drain hooks; avoid
   arbitrary sleeps and “eventually” polling without a bounded controlled executor.
2. Execute the selected process leak tool repeatedly after smoke actions. Require parsed run identity,
   clean structured termination, tool success, zero leak count, and retained raw report path.
3. Generate the closed visual matrix from semantic/color/layout enums. A new member fails until it
   has expected geometry and contrast ownership.
4. Run `smoke-screenshot.sh` exactly once at closing on the rich fixture, inspect it, and send it to
   the user. Do not turn screenshots into automated pixel truth or capture other windows.

## Failure and conformance

Timeout, unsupported tool, parse ambiguity, nonzero leaks, missing runEnd, live owner after drain,
clipping, out-of-bounds attachment, or source mutation fails. No duplicate smoke launcher/verifier,
XCUITest, screen driving, golden-pixel fragility, unbounded timer/task, or leaked observer remains.

## Deletion/conformance gate

One smoke launcher/verifier composition, one selected leak-tool adapter, and a closed lifecycle/
visual matrix remain. Structural checks find no duplicate process verifier, unmanaged owner,
screen-driving target, full-screen capture, or pixel-golden test.
