#!/usr/bin/env bash
set -euo pipefail
# VERSION 2

SELF="$(basename "$0")"

die() {
  local code="$1"
  shift
  echo "$SELF: $*" >&2
  exit "$code"
}

# Resolve the script's own directory, following symlinks (portable, no
# readlink -f / realpath — must work on macOS/Bash 3.2).
src="$0"
while [[ -L "$src" ]]; do
  dir="$(cd -P "$(dirname "$src")" && pwd)"
  target="$(readlink "$src")"
  case "$target" in
    /*) src="$target" ;;
    *) src="$dir/$target" ;;
  esac
done
script_dir="$(cd -P "$(dirname "$src")" && pwd)"

NONO_HERE_HOME="${NONO_HERE_HOME:-$script_dir}"

workdir=$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")

# Task 2+: workdir is echoed to stderr only when provisioning is about to
# occur (N13) — the fast path must remain silent.
