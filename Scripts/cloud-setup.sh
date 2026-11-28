#!/bin/bash
# SessionStart hook (.claude/settings.json). Prints which environment this session is in and what
# the loop is there; in a Claude Code cloud session (CLAUDE_CODE_REMOTE=true, Ubuntu, no Xcode) it
# also makes sure the portable steps of Scripts/check.sh can run. Whatever it prints is added to
# the session's context, so it stays short. It always exits 0: a setup that fails must not stop
# the session from starting; the step that needed the missing tool fails by name when it runs.
set -uo pipefail

if [[ "${CLAUDE_CODE_REMOTE:-}" == "true" ]]; then
    missing=()
    command -v python3 >/dev/null 2>&1 || missing+=(python3)
    command -v npx >/dev/null 2>&1 || missing+=(npm)
    if (( ${#missing[@]} > 0 )); then
        sudo_cmd=()
        [[ "$(id -u)" == 0 ]] || sudo_cmd=(sudo -n)
        "${sudo_cmd[@]}" apt-get update -qq >/dev/null 2>&1 \
            && DEBIAN_FRONTEND=noninteractive "${sudo_cmd[@]}" apt-get install -y -qq --no-install-recommends "${missing[@]}" >/dev/null 2>&1 \
            || echo "cloud-setup: could not install ${missing[*]}" >&2
    fi
    cat <<'NOTE'
Environment: Claude Code cloud session (Linux, no Xcode). Scripts/check.sh runs the portable steps and ends INCOMPLETE (exit 3); the build, tests and smoke are CI's macOS job on the pushed branch, which is this change's verification. Read it with the GitHub MCP tools (actions_list, get_job_logs). CLAUDE.md "Environments".
NOTE
elif [[ "$(uname -s)" == Darwin ]]; then
    cat <<'NOTE'
Environment: a local Mac. Scripts/check.sh runs the full gate locally (build, tests, smoke); CI repeats it on push. Work in a branch, never in the main checkout's working tree. CLAUDE.md "Environments".
NOTE
fi
exit 0
