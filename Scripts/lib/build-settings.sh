# Build settings every verification build passes (Scripts/check.sh, smoke-test.sh,
# smoke-screenshot.sh). Sourced; sets the array `verification_build_settings`.
#
# Compilation caching (Xcode 26+) keeps every compile job's output in one content-addressed store,
# so the smoke build replays what the test build just compiled, and CI replays what main's newest
# run left (it restores the store; only a push to main saves it). Measured in Otos (its ADR 0044);
# here, check.sh's `duration:` line is read against the five-minute budget (docs/DECISIONS.md,
# 2026-11-26).
#
# Deliberately without Otos's prefix mapping: it rewrites #filePath, which the tests use to find
# fixtures and production source. CI's checkout path is the same on every run, so its cache hits
# without it; a local worktree at another path keeps its own entries.
#
# Index-while-building feeds only an IDE, and these builds have none.
verification_build_settings=(
    COMPILATION_CACHE_ENABLE_CACHING=YES
    "COMPILATION_CACHE_CAS_PATH=$HOME/Library/Developer/Xcode/DerivedData/CompilationCache.noindex"
    COMPILER_INDEX_STORE_ENABLE=NO
)
