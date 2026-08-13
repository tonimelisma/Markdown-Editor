#!/bin/bash
# COR-58 / REQ-135: hermetic fixtures for observed trace-vocabulary coverage.
set -euo pipefail

root="$(mktemp -d)"
trap 'rm -rf "$root"' EXIT
cases="$root/cases.txt"
exemptions="$root/exemptions.md"
routes="$root/routes.json"
logs="$root/logs"
mkdir -p "$logs" "$root/Markdown Editor"
cat > "$root/Markdown Editor/FixtureOwner.swift" <<'EOF'
final class FixtureOwner {
    func fixtureAlpha() { trace.record(route: .alpha, .alpha) }
    final class Coordinator {
        func fixtureBeta() {}
        func fixtureBeta(_ value: Int) { trace.record(route: .beta, .beta) }
        func fixtureGamma() { trace.record(route: .gamma, .gamma) }
    }
}
EOF
printf 'alpha\nbeta\ngamma\n' > "$cases"
cat > "$exemptions" <<'EOF'
| Event | Reason | Removal plan |
| --- | --- | --- |
| `gamma` | terminal-only fixture route is not exercised by this run | COR-58 behavioral route |
EOF
cat > "$routes" <<'EOF'
{"version":1,"events":{
  "alpha":{"owner":"FixtureOwner","entry":"fixtureAlpha","expectedRecord":"alpha","allowedHarness":"component"},
  "beta":{"owner":"FixtureOwner.Coordinator","entry":"fixtureBeta","expectedRecord":"beta","allowedHarness":"component"},
  "gamma":{"owner":"FixtureOwner.Coordinator","entry":"fixtureGamma","expectedRecord":"gamma","allowedHarness":"component"}
}}
EOF
gate="$(dirname "$0")/check-instrumentation-coverage.sh"
write_log() {
    local path="$1"; local origin="${2:-productionRoute}"; shift 2
    : > "$path"
    for event in "$@"; do
        if [[ "$origin" == productionRoute ]]; then
            printf '{"v":2,"ev":"%s","origin":"%s","route":"%s","channel":"productionRoutePipe","harness":"component"}\n' \
                "$event" "$origin" "$event" >> "$path"
        else
            printf '{"v":2,"ev":"%s","origin":"%s"}\n' "$event" "$origin" >> "$path"
        fi
    done
}
expect_fail() {
    if "$@" >/dev/null 2>&1; then
        echo "expected failure: $*" >&2
        exit 1
    fi
}

write_log "$logs/complete.jsonl" productionRoute alpha beta
    ("$gate" --cases-file "$cases" --exemptions "$exemptions" --routes "$routes" --log-dir "$logs") >/dev/null

write_log "$logs/missing.jsonl" productionRoute alpha
expect_fail "$gate" --cases-file "$cases" --exemptions "$exemptions" --routes "$routes" --log-dir "$logs/missing.jsonl"

: > "$logs/empty.jsonl"
expect_fail "$gate" --cases-file "$cases" --exemptions "$exemptions" --routes "$routes" --log-dir "$logs/empty.jsonl"

write_log "$logs/unknown.jsonl" productionRoute alpha beta delta
expect_fail "$gate" --cases-file "$cases" --exemptions "$exemptions" --routes "$routes" --log-dir "$logs/unknown.jsonl"

# A complete encoding probe is deliberately not production reachability evidence.
write_log "$logs/encoding.jsonl" encodingProbe alpha beta
expect_fail "$gate" --cases-file "$cases" --exemptions "$exemptions" --routes "$routes" --log-dir "$logs/encoding.jsonl"

# Missing provenance fails closed, even when the event name is otherwise valid.
printf '{"v":2,"ev":"alpha"}\n{"v":2,"ev":"beta","origin":"productionRoute"}\n' > "$logs/missing-origin.jsonl"
expect_fail "$gate" --cases-file "$cases" --exemptions "$exemptions" --routes "$routes" --log-dir "$logs/missing-origin.jsonl"

# Rehearsal of the COR-44 defeat: a nil-bound source call cannot add an emitted event. The new
# gate ignores that source text and therefore still rejects the observed log.
printf 'let trace: (any EditorTraceSink)? = nil\ntrace?.record(.beta)\n' > "$root/defeated.swift"
write_log "$logs/rehearsal.jsonl" productionRoute alpha
expect_fail "$gate" --cases-file "$cases" --exemptions "$exemptions" --routes "$routes" --log-dir "$logs/rehearsal.jsonl"

# A forged production origin without the gate-owned channel fails closed.
printf '{"v":2,"ev":"alpha","origin":"productionRoute","route":"alpha","harness":"component"}\n' \
    > "$logs/forged-origin.jsonl"
expect_fail "$gate" --cases-file "$cases" --exemptions "$exemptions" --routes "$routes" --log-dir "$logs/forged-origin.jsonl"

# A production record cannot claim a different reviewed route, even on the channel.
printf '{"v":2,"ev":"alpha","origin":"productionRoute","route":"beta","channel":"productionRoutePipe","harness":"component"}\n' \
    > "$logs/misrouted.jsonl"
expect_fail "$gate" --cases-file "$cases" --exemptions "$exemptions" --routes "$routes" --log-dir "$logs/misrouted.jsonl"

echo "check-instrumentation-coverage fixtures: PASS"
