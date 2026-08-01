#!/usr/bin/env python3
"""Shared structured-log verifier for both process smoke scripts."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("run_file", type=Path)
    parser.add_argument("host_update_threshold", type=int)
    parser.add_argument("--label", default="smoke")
    return parser.parse_args()


def verify(run_file: Path, host_update_threshold: int) -> tuple[int, int]:
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
    assert len(reconciliations) == 1, (
        f"expected exactly one reconciliationApplied, got {len(reconciliations)}"
    )
    assert any(
        record["ev"] == "hostUpdateEnded"
        and record["seq"] > reconciliations[0]["seq"]
        for record in events
    ), "the host never updated after applying the projection"

    reconciliation_summaries = [
        record
        for record in events
        if record["ev"] == "performanceSummary"
        and record.get("data", {}).get("metric") == "reconciliation"
    ]
    assert len(reconciliation_summaries) == 1, (
        "expected exactly one reconciliation performance summary, "
        f"got {len(reconciliation_summaries)}"
    )
    assert reconciliation_summaries[0].get("data", {}).get("count", 0) >= 1, (
        "reconciliation performance summary contains no samples"
    )

    faults = [
        record for record in events
        if record.get("lvl") in ("error", "fault")
    ]
    assert not faults, f"faults recorded: {[record['ev'] for record in faults]}"
    assert events[-1]["ev"] == "runEnd", "no clean-exit record"

    return len(records), host_updates


def main() -> int:
    args = parse_args()
    try:
        record_count, host_updates = verify(args.run_file, args.host_update_threshold)
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
