#!/bin/bash
# COR-60 / REQ-137: provenance gate failure and liveness fixtures.
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
gate="$repo_root/Scripts/check-measurement-provenance.sh"
root="$(mktemp -d)"
trap 'rm -rf -- "$root"' EXIT
mkdir -p "$root/docs/research" "$root/Markdown EditorTests"
printf 'enum PerformanceCorpus { case structured }\n' >"$root/Markdown EditorTests/PerformanceCorpus.swift"
digest="$(shasum -a 256 "$root/Markdown EditorTests/PerformanceCorpus.swift" | awk '{print $1}')"
commit="$(git -C "$repo_root" rev-parse HEAD)"

table='| scenario | corpus | size | p95 |\n| --- | --- | --- | --- |\n| typeProse | structured | 100000 | 1ms |'

write_file() {
    local body="$1"
    printf '%b\n' "$body" >"$root/docs/research/performance-baseline.md"
}

expect_failure() {
    local name="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        echo "test-check-measurement-provenance: $name unexpectedly passed" >&2
        exit 1
    fi
}

write_file "$table\nHost: \$(hostname)"
expect_failure 'unexpanded shell construct' "$gate" --research-root "$root/docs/research" --expected-corpus-digest "$digest"

write_file "$table"
expect_failure 'missing provenance block' "$gate" --research-root "$root/docs/research" --expected-corpus-digest "$digest"

write_file "$table\nHost: stub\nOS: macOS\nOS build: 1\nArchitecture: arm64\nConfiguration: Release\nXcode: Xcode\nCorpus digest: $digest\nWarmup: 1\nSamples: 1\nInterval: 1ms\nCommit: $commit\nRun ID: run"
expect_failure 'placeholder field' "$gate" --research-root "$root/docs/research" --expected-corpus-digest "$digest"

write_file "$table\nHost: host\nOS: macOS\nOS build: 1\nArchitecture: arm64\nConfiguration: Release\nXcode: Xcode\nCorpus digest: deadbeef\nWarmup: 1\nSamples: 1\nInterval: 1ms\nCommit: $commit\nRun ID: run"
expect_failure 'corpus mismatch' "$gate" --research-root "$root/docs/research" --expected-corpus-digest "$digest"

write_file "$table\nHost: host\nOS: macOS\nOS build: 1\nArchitecture: arm64\nConfiguration: Release\nXcode: Xcode\nCorpus digest: $digest\nWarmup: 1\nSamples: 1\nInterval: 1ms\nCommit: 0000000000000000000000000000000000000000\nRun ID: run"
expect_failure 'unknown commit' "$gate" --research-root "$root/docs/research" --expected-corpus-digest "$digest"

write_file "$table\nHost: host\nOS: macOS\nOS build: 1\nArchitecture: arm64\nConfiguration: Release\nXcode: Xcode\nCorpus digest: $digest\nWarmup: 1\nSamples: 1\nInterval: 1ms\nCommit: $commit\nRun ID: run"
"$gate" --research-root "$root/docs/research" --expected-corpus-digest "$digest" >/dev/null

printf '# prose only\nNo measurement table here.\n' >"$root/docs/research/prose.md"
rm "$root/docs/research/performance-baseline.md"
"$gate" --research-root "$root/docs/research" --expected-corpus-digest "$digest" >/dev/null

echo "test-check-measurement-provenance: PASS (failure and liveness fixtures observed)"
