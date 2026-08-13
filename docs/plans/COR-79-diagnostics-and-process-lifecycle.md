# COR-79 — Diagnostics and process lifecycle

- **Status:** Approved; not implemented
- **Delivers:** REQ-097, REQ-098, REQ-101, REQ-102
Architecture impact: none; completes ARC-016, ARC-017, ARC-021, ARC-Q12, and ARC-Q17
Blockers: COR-68, COR-69, COR-73, COR-78
Executor: A junior may implement the route matrix; a senior must review signal/process-lifecycle and durability changes.

## Scope and files

Own `DiagnosticLog`, `DiagnosticRunCoordinator`, `JSONLinesEditorTrace`, fault reporter, alert owner,
image-placement diagnostics, `Scripts/smoke-test.sh`, `Scripts/verify-smoke-log.py`, and their
fixtures. Do not add content-bearing payloads or UI assertions.

## Implementation

1. Enumerate every image-placement phase/result and every user-visible alert assignment. Route alerts
   through `presentAlert(_:reason:)` and prove matching warn/error records.
2. Prove diagnostics-directory override isolation, retention, size bounds, collapse, ordering,
   terminal close, crash/fault durability, and rejection of writes after finish.
3. Run process smoke on a copied fixture. Require open, accepted text, accepted command, applied
   reconciliation, bounded host updates, intent ledgers, performance samples, zero fault/error, and
   `runEnd`; assert solely on structured records.
4. Add deterministic failure fixtures for missing/empty/truncated/duplicate/out-of-order records,
   wrong run/host/schema, absent terminal close, and a user alert without its diagnostic.
5. Ensure test/encoding/fixture evidence origins added by COR-68 cannot satisfy production smoke.

## Proof and failure behavior

Environment override never reads/prunes the production log directory. Every placement route records
start→phase→terminal result with numeric counts only. A blocked main actor still produces its fault
before recovery, and terminal close never waits on main actor. Smoke timeout kills only the launched
PID, preserves logs, and reports which invariant was missing.

## Deletion/conformance gate

No direct alert assignment, free-form string payload, production/test log union, or second smoke
verifier remains. All trace cases used for coverage name and execute a production route.
