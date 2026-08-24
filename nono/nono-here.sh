#!/usr/bin/env bash
set -euo pipefail

VERSION="0.1"

usage() {
    local cmd=$(basename "$0")
    cat <<EOF
Usage: $cmd [OPTIONS] [-- <command> AGENT_ARGS...]

Run <command> in the current workspace using .nono/profile.json.

OPTIONS:
  --help, -h     Show this help message
  --version      Show version information

EXAMPLES:
  $cmd -- opencode

EOF
}

case "${1:-}" in
    -h|--help)
        usage
        exit 0
        ;;
    --version)
        echo "nono-here v$VERSION"
        exit 0
        ;;
    --)
        shift
        ;;
esac

if ! command -v nono >/dev/null 2>&1; then
    echo "nono-here: nono is not installed or not in PATH" >&2
    exit 127
fi

if WORKSPACE=$(git rev-parse --show-toplevel 2>/dev/null); then
    :
else
    WORKSPACE=$PWD
fi

profile="$WORKSPACE/.nono/profile.json"
if [[ ! -r "$profile" ]]; then
    echo "nono-here: profile not found or unreadable: $profile" >&2
    exit 1
fi

run_hook() {
    local hook_name="$1"
    local hook_script="$WORKSPACE/.nono/hooks/$hook_name"

    if [[ -x "$hook_script" ]]; then
        # Run in a subshell to prevent hook failures/exits from killing this wrapper prematurely
        ( "$hook_script" ) || echo "Warning: Hook $hook_name exited with a non-zero status." >&2
    fi
}

cd "$WORKSPACE"
run_hook before
trap 'run hook after' EXIT

exec nono wrap \
  --profile "$profile" \
  --workdir "$WORKSPACE" \
  --allow-cwd \
  -- "$@"
