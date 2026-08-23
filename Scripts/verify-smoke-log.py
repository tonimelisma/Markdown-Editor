#!/usr/bin/env python3
"""Shared structured-log verifier for both process smoke scripts."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


# Mirrors PerformanceSampler.Metric and PerformanceSampler.budgetNanos.
#
# Deliberately a hand-maintained second statement of a closed set, and deliberately kept: it is an
# *independent* oracle that fails loudly the moment production drifts from it, which is what
# separates it from the falsification manifests that rotted silently (see docs/DECISIONS.md).
# Adding a metric in Swift without adding it here fails the smoke run, by design. The Swift side's
# own agreement with REQUIREMENTS is asserted by PerformanceBudgetTests.
#
# One table, not two: KNOWN_METRICS and BUDGET_NANOS used to be separate structures that could
# disagree with each other, and a metric present in the first but missing from the second was
# silently exempt from its budget below.
BUDGET_NANOS = {
    "nativeInputCallback": 8_000_000,
    "modeTransition": 16_000_000,
    "parseProjection": 100_000_000,
    "imageResolution": 16_000_000,
    "authoritativeApplication": 100_000_000,
    "layoutApplication": 16_000_000,
    "mainActorLatency": 16_000_000,
    "sourceHighlightApplication": 8_000_000,
    "sourceHighlightCompute": 100_000_000,
    "semanticCommand": 16_000_000,
}

KNOWN_METRICS = frozenset(BUDGET_NANOS)

WORK_SCOPES = {"acceptedEdit", "reconciliation", "documentOpen", "modeTransition", "semanticCommand"}
WORK_LEDGER_FIELDS = {
    "documentParses", "projectionCompiles", "oracleValidations", "attributedBuilds",
    "attributedCharactersWritten", "storageFullReplacements", "imageDecodes",
    "fileBytesRead", "mainThreadBlockedNanos",
}


def is_bounded_cancelled_orphan(record: dict) -> bool:
    data = record.get("data", {})
    if record.get("lvl") != "fault" or record.get("ev") != "workLedger":
        return False
    if data.get("orphaned") is not True or data.get("orphanReason") != "cancelled":
        return False
    if data.get("lateWork") is not False:
        return False
    if not isinstance(data.get("intentID"), int) or data["intentID"] <= 0:
        return False
    if data.get("scope") not in WORK_SCOPES:
        return False
    return all(isinstance(data.get(field), int) and data[field] >= 0 for field in WORK_LEDGER_FIELDS)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("run_file", type=Path)
    parser.add_argument("host_update_threshold", type=int)
    parser.add_argument("--label", default="smoke")
    parser.add_argument(
        "--expect-edits",
        action="store_true",
        help=(
            "Require the run to have exercised one accepted insertion and one accepted "
            "semantic command (REQ-115). Without this the run only proves open-and-idle, so "
            "editRefused - the record that would have surfaced COR-25 and the four commands "
            "COR-26 fixed - can never fire."
        ),
    )
    parser.add_argument(
        "--allow-fault",
        action="append",
        default=[],
        metavar="EVENT",
        help=(
            "Tolerate this fault event, for a caller that provably causes it. Used by "
            "smoke-screenshot.sh for mainActorStall: screencapture freezes the captured "
            "process while reading its window surface, so the watchdog correctly reports the "
            "measurement apparatus rather than the application. Never pass this to hide an "
            "application fault — the same run without a capture must be clean."
        ),
    )
    parser.add_argument(
        "--allow-orphaned-intents",
        action="store_true",
        help=(
            "Allow only workLedger fault records whose structured data marks the intent as "
            "orphaned; ordinary faults remain fatal during intentional process shutdown."
        ),
    )
    parser.add_argument(
        "--fail-on-budget-exceeded",
        action="store_true",
        help="Fail when a performance summary exceeds its declared p95 budget.",
    )
    parser.add_argument(
        "--reconciliation-ceiling",
        type=int,
        default=None,
        metavar="N",
        help=(
            "Bound on reconciliationApplied records, for a caller that knows how many edits it "
            "drove. Defaults to 2, or 4 with --expect-edits, which suits a caller driving a "
            "handful of edits; a benchmark driving one edit per interval for several seconds "
            "reconciles once per accepted edit and must state its own bound. This is a livelock "
            "guard, so the value must stay a bound — never pass a number large enough to admit a "
            "self-feeding loop."
        ),
    )
    return parser.parse_args()


def verify(
    run_file: Path,
    host_update_threshold: int,
    allowed_faults: frozenset[str] = frozenset(),
    allow_orphaned_intents: bool = False,
    expect_edits: bool = False,
    fail_on_budget_exceeded: bool = False,
    reconciliation_ceiling: int | None = None,
) -> tuple[int, int]:
    records = [
        json.loads(line)
        for line in run_file.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]
    assert records, "run file is empty"

    header = records[0]
    assert header["v"] == 2, "unexpected schema version"
    assert header["run"]["host"] == "production", (
        f"expected production host, got {header['run'].get('host')}"
    )

    events = records[1:]
    sequences = [record["seq"] for record in events]
    for previous, current in zip(sequences, sequences[1:]):
        assert current > previous, (
            f"sequence numbers not strictly increasing: {previous} then {current}"
        )

    opened = [record for record in events if record["ev"] == "documentOpened"]
    loaded = [record for record in events if record["ev"] == "documentLoaded"]
    assert len(opened) == 1, f"expected exactly one documentOpened, got {len(opened)}"
    assert len(loaded) == 1, f"expected exactly one documentLoaded, got {len(loaded)}"
    assert opened[0].get("doc") is not None, "documentOpened has no document handle"
    assert loaded[0].get("doc") == opened[0]["doc"], (
        "documentLoaded does not belong to the opened document"
    )

    document_handles = {
        record["doc"]
        for record in events
        if record.get("doc") is not None
    }
    assert document_handles == {opened[0]["doc"]}, (
        f"expected one document handle, got {sorted(document_handles)}"
    )

    direct_updates = sum(record["ev"] == "hostUpdateEnded" for record in events)
    collapsed_updates = sum(
        record.get("data", {}).get("count", 0)
        for record in events
        if record["ev"] == "repeated"
        and record.get("of") == "hostUpdateEnded"
    )
    host_updates = direct_updates + collapsed_updates
    assert host_updates <= host_update_threshold, (
        f"host did not settle: {host_updates} updates "
        f"(threshold {host_update_threshold})"
    )

    became_editable = any(
        record["ev"] == "availabilityChanged"
        and record.get("data", {}).get("editable") is True
        and record.get("doc") == opened[0]["doc"]
        for record in events
    )
    assert became_editable, "WYSIWYG never announced becoming editable"

    reconciliations = [
        record
        for record in events
        if record["ev"] == "reconciliationApplied"
        and record.get("doc") == opened[0]["doc"]
    ]
    assert reconciliations, "no reconciliationApplied record"
    # Bounded, not exact. An `== 1` equality froze the current startup ordering into the gate: a
    # legitimate future change that applies a second reconciliation would have failed it for
    # being correct. The livelock guard is the host-update ceiling above, which is what actually
    # catches a self-feeding loop.
    # The default suits a caller that drives a handful of edits. A benchmark run drives one edit
    # every --interval-ms for --duration seconds and reconciles once per accepted edit, so the
    # fixed ceiling reported "17 applied (ceiling 4)" for a run that was behaving exactly as
    # designed — and Scripts/benchmark.sh consequently failed at the first of its 108 runs and had
    # never produced the baseline it is supposed to produce. A caller that knows how many edits it
    # drove may state the bound; it stays a real livelock guard because it is still a bound, and a
    # self-feeding loop exceeds edits-plus-slack just as it exceeded 4.
    if reconciliation_ceiling is None:
        reconciliation_ceiling = 4 if expect_edits else 2
    assert len(reconciliations) <= reconciliation_ceiling, (
        f"reconciliation did not settle: {len(reconciliations)} applied "
        f"(ceiling {reconciliation_ceiling})"
    )
    assert any(
        record["ev"] == "hostUpdateEnded"
        and record["seq"] > reconciliations[0]["seq"]
        for record in events
    ), "the host never updated after applying the projection"

    summaries = [record for record in events if record["ev"] == "performanceSummary"]
    reported_metrics = {
        record.get("data", {}).get("metric") for record in summaries
    }
    unknown_metrics = reported_metrics - KNOWN_METRICS
    # A renamed production metric must fail here rather than silently satisfying a stale
    # expectation that no code can emit any more.
    assert not unknown_metrics, (
        f"unknown performance metric(s): {sorted(str(m) for m in unknown_metrics)}"
    )
    if fail_on_budget_exceeded:
        exceeded = [
            record for record in summaries
            if record.get("data", {}).get("metric") in BUDGET_NANOS
            and record.get("data", {}).get("p95Nanos", 0)
                > BUDGET_NANOS[record["data"]["metric"]]
        ]
        assert not exceeded, "performance budgets exceeded: " + ", ".join(
            f"{record['data']['metric']}={record['data']['p95Nanos']}"
            for record in exceeded
        )

    parse_summaries = [
        record
        for record in summaries
        if record.get("data", {}).get("metric") == "parseProjection"
    ]
    assert len(parse_summaries) == 1, (
        "expected exactly one parseProjection performance summary, "
        f"got {len(parse_summaries)}"
    )
    assert parse_summaries[0].get("data", {}).get("count", 0) >= 1, (
        "parseProjection performance summary contains no samples"
    )

    if expect_edits:
        # REQ-115: the run must prove it actually edited, and that nothing refused.
        committed = [r for r in events if r["ev"] == "mutationCommitted"]
        assert len(committed) >= 2, (
            f"expected an insertion and a semantic command to commit, got {len(committed)}"
        )
        routed = [r for r in events if r["ev"] == "editRouted"]
        assert routed, "no editRouted record; the command route was never exercised"
        refused = [r for r in events if r["ev"] in ("editRefused", "mutationRefused")]
        assert not refused, (
            f"the scripted edits were refused: {[r.get('data') for r in refused]}"
        )
        # Deliberately NOT asserting nativeInputCallback samples here. That metric is sampled
        # inside the WYSIWYG text view's own input delegate, so producing it at process level
        # would mean driving an NSTextView - i.e. driving UI, which the CLAUDE.md §4 carve-out
        # forbids for this verification. The scripted edits go through EditorSession.perform,
        # the same model route the adapters call, and are proven by the mutation and routing
        # records above. The callback boundary keeps its component-test and Release evidence.

    faults = [
        record for record in events
        if record.get("lvl") in ("error", "fault")
        and record.get("ev") not in allowed_faults
        and not (
            allow_orphaned_intents
            and is_bounded_cancelled_orphan(record)
        )
    ]
    assert not faults, f"faults recorded: {[record['ev'] for record in faults]}"
    # REQ-104: the screenshot is not valid evidence unless its companion process run closes cleanly.
    assert events[-1]["ev"] == "runEnd", "no clean-exit record"

    return len(records), host_updates


def main() -> int:
    args = parse_args()
    try:
        record_count, host_updates = verify(
            args.run_file,
            args.host_update_threshold,
            frozenset(args.allow_fault),
            args.allow_orphaned_intents,
            args.expect_edits,
            args.fail_on_budget_exceeded,
            args.reconciliation_ceiling,
        )
    except (AssertionError, KeyError, TypeError, ValueError, json.JSONDecodeError) as error:
        print(f"{args.label}: diagnostics FAIL: {error}", file=sys.stderr)
        return 1
    print(
        f"{args.label}: diagnostics PASS "
        f"({record_count} records, {host_updates} host updates)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
