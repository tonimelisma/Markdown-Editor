#!/usr/bin/env python3
"""Shared structured-log verifier for both process smoke scripts."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


# Mirrors PerformanceSampler.Metric. Kept explicit so a production rename that this file does
# not follow fails the smoke run instead of quietly matching nothing.
KNOWN_METRICS = {
    "nativeInputCallback",
    "modeTransition",
    "parseProjection",
    "imageResolution",
    "authoritativeApplication",
    "layoutApplication",
    "sourceHighlightApplication",
}


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
    return parser.parse_args()


def verify(
    run_file: Path,
    host_update_threshold: int,
    allowed_faults: frozenset[str] = frozenset(),
    expect_edits: bool = False,
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
    ]
    assert not faults, f"faults recorded: {[record['ev'] for record in faults]}"
    assert events[-1]["ev"] == "runEnd", "no clean-exit record"

    return len(records), host_updates


def main() -> int:
    args = parse_args()
    try:
        record_count, host_updates = verify(
            args.run_file,
            args.host_update_threshold,
            frozenset(args.allow_fault),
            args.expect_edits,
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
