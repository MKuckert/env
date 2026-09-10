#!/usr/bin/env bash
set -euo pipefail
# VERSION 2

SELF="$(basename "$0")"

# Documented extension point: adding a harness is a one-token edit to this
# array and nothing else.
HARNESSES=(claude opencode codex copilot pi)

die() {
  local code="$1"
  shift
  echo "$SELF: $*" >&2
  exit "$code"
}

# Resolve the script's own directory, following symlinks (portable, no
# readlink -f / realpath — must work on macOS/Bash 3.2). Bounded to guard
# against symlink cycles (e.g. a -> b -> a).
resolve_script_dir() {
  local src dir target hops
  src="$0"
  hops=0
  while [[ -L "$src" ]]; do
    hops=$((hops + 1))
    if [[ "$hops" -gt 40 ]]; then
      die 1 "symlink resolution exceeded 40 hops (possible cycle) for '$0'"
    fi
    dir="$(cd -P "$(dirname "$src")" && pwd)"
    target="$(readlink "$src")"
    case "$target" in
      /*) src="$target" ;;
      *) src="$dir/$target" ;;
    esac
  done
  cd -P "$(dirname "$src")" && pwd
}

# Keep this assignment bare (no `local`/`export`): with `set -e`, a failure
# inside resolve_script_dir must abort the script. Wrapping it would replace
# $? with the local/export builtin's exit status, masking the failure.
script_dir="$(resolve_script_dir)"

# Exported so a future child process can inherit the resolved home; nothing
# consumes it yet.
export NONO_HERE_HOME="${NONO_HERE_HOME:-$script_dir}"

workdir=$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")

# Task 2+: workdir is echoed to stderr only when provisioning is about to
# occur (N13) — the fast path must remain silent.

# The single exec site. Invoked identically from the fast path and from the
# end of provisioning so both paths are indistinguishable in argument
# handling and CWD (resolves reviewer blocker B5).
handover() {
  cd "$workdir" || die 1 "cannot enter $workdir"
  exec ./run_harness.sh "$@"
}

if [[ -e "$workdir/run_harness.sh" || -L "$workdir/run_harness.sh" ]] && [[ ! -f "$workdir/run_harness.sh" ]]; then
  die 9 "$workdir/run_harness.sh exists but is not a regular file"
elif [[ -f "$workdir/run_harness.sh" ]] && [[ ! -x "$workdir/run_harness.sh" ]]; then
  die 2 "$workdir/run_harness.sh is not executable; run: chmod +x \"$workdir/run_harness.sh\""
elif [[ -f "$workdir/run_harness.sh" ]] && [[ -x "$workdir/run_harness.sh" ]]; then
  if [[ ! -x "$workdir/.sandbox/start.sh" ]]; then
    die 3 "$workdir/.sandbox/start.sh is missing or not executable; run: chmod +x \"$workdir/.sandbox/start.sh\""
  fi
  handover "$@"
fi

# Task 3: provisioning continues here when $workdir/run_harness.sh does
# not exist at all (fall-through from the branch ladder above). No
# filesystem mutation happens until a valid harness is selected.

if [[ -n "${NONO_HERE_HARNESS:-}" ]]; then
  harness=""
  for h in "${HARNESSES[@]}"; do
    if [[ "$h" == "$NONO_HERE_HARNESS" ]]; then
      harness="$h"
      break
    fi
  done
  if [[ -z "$harness" ]]; then
    die 8 "invalid NONO_HERE_HARNESS '$NONO_HERE_HARNESS'; valid values: ${HARNESSES[*]}"
  fi
elif [[ ! -t 0 ]]; then
  die 4 "no TTY for interactive harness selection; set NONO_HERE_HARNESS to one of: ${HARNESSES[*]}"
else
  PS3="harness> "
  select harness in "${HARNESSES[@]}"; do
    if [[ -n "${harness:-}" ]]; then
      break
    fi
    echo "$SELF: invalid selection '$REPLY'; choose a number from the list" >&2
  done
  if [[ -z "${harness:-}" ]]; then
    die 10 "no harness selected (input closed)"
  fi
fi

# Task 4-8: provisioning continues here with $harness set to a validated
# entry from HARNESSES.
