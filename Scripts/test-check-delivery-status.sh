#!/bin/bash
# REQ-136: fixture matrix for the ROADMAP/plan delivery-status gate.
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
checker="$repo_root/Scripts/check-delivery-status.sh"
fixture_root="$(mktemp -d)"
trap 'rm -rf -- "$fixture_root"' EXIT

make_fixture() {
    local status="$1" delivers="$2" requirement_status="$3" plan_state="$4"
    local link_state="${5:-matching}" plan_delivers="${6:-}"
    [[ -n "$plan_delivers" ]] || plan_delivers="$delivers"
    rm -rf -- "$fixture_root/docs"
    mkdir -p "$fixture_root/docs/plans"
    cat >"$fixture_root/docs/ROADMAP.md" <<EOF
# ROADMAP

1. $status **COR-99 — Fixture.** (Delivers: $delivers) $([[ "$link_state" == matching ]] && echo '([plan](plans/COR-99-fixture.md))' || [[ "$link_state" == wrong ]] && echo '([plan](plans/COR-98-fixture.md))')
EOF
    cat >"$fixture_root/docs/REQUIREMENTS.md" <<EOF
| REQ-001 | fixture | COR-99 | $requirement_status | implementation | Scripts/test-check-delivery-status.sh |
EOF
    case "$plan_state" in
        present)
            cat >"$fixture_root/docs/plans/COR-99-fixture.md" <<EOF
# COR-99 — Fixture
- **Delivers:** $plan_delivers
EOF
            ;;
        absent|none) ;;
        *) echo "unknown plan state: $plan_state" >&2; exit 2 ;;
    esac
}

expect_failure() {
    local name="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        echo "test-check-delivery-status: $name unexpectedly passed" >&2
        exit 1
    fi
}

make_fixture "✅" "REQ-001" "Correction" absent
expect_failure "Correction delivery" "$checker" --fixture-root "$fixture_root" --fixture-proof-status pass

make_fixture "✅" "REQ-001" "Done" absent
expect_failure "unexecuted proof" "$checker" --fixture-root "$fixture_root" --fixture-proof-status fail

make_fixture "✅" "" "Done" absent
expect_failure "missing none declaration" "$checker" --fixture-root "$fixture_root" --fixture-proof-status pass

make_fixture "✅" "REQ-001" "Done" present
expect_failure "undeleted plan" "$checker" --fixture-root "$fixture_root" --fixture-proof-status pass

make_fixture "⚪" "REQ-001" "Planned" absent
expect_failure "active row without plan" "$checker" --fixture-root "$fixture_root" --fixture-proof-status pass

make_fixture "⚪" "REQ-001" "Planned" present missing
expect_failure "active row missing plan link" "$checker" --fixture-root "$fixture_root" --fixture-proof-status pass

make_fixture "⚪" "REQ-001" "Planned" present wrong
expect_failure "active row wrong plan link" "$checker" --fixture-root "$fixture_root" --fixture-proof-status pass

make_fixture "⚪" "REQ-001" "Planned" present matching none
expect_failure "ROADMAP and plan Delivers mismatch" "$checker" --fixture-root "$fixture_root" --fixture-proof-status pass

make_fixture "⚪" "REQ-001" "Done" present matching REQ-001
expect_failure "active row already-Done requirement" "$checker" --fixture-root "$fixture_root" --fixture-proof-status pass

make_fixture "✅" "none (refactor)" "Planned" absent
expect_failure "deleted plan without production change" "$checker" --fixture-root "$fixture_root" --fixture-proof-status pass --fixture-deletion-change none

make_fixture "✅" "none (refactor)" "Planned" absent
"$checker" --fixture-root "$fixture_root" --fixture-proof-status pass --fixture-deletion-change production >/dev/null

make_fixture "⚪" "REQ-001" "Planned" present
"$checker" --fixture-root "$fixture_root" --fixture-proof-status pass >/dev/null

echo "test-check-delivery-status: PASS (failure and liveness fixtures observed)"
