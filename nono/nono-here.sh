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

# Task 4: template resolution and validation. Probe order: user overrides
# beat bundled templates, harness-specific beats default. Stop at the first
# existing directory. Nothing on disk is created, copied or deleted here.
template=""
for candidate in \
  "${HOME:-}/.nono-here/templates/$harness" \
  "${HOME:-}/.nono-here/templates/default" \
  "$NONO_HERE_HOME/templates/$harness" \
  "$NONO_HERE_HOME/templates/default"; do
  if [[ -d "$candidate" ]]; then
    template="$candidate"
    break
  fi
done

if [[ -z "$template" ]]; then
  die 5 "no template directory found; probed in order:
${HOME:-}/.nono-here/templates/$harness
${HOME:-}/.nono-here/templates/default
$NONO_HERE_HOME/templates/$harness
$NONO_HERE_HOME/templates/default"
fi

echo "$SELF: workdir: $workdir" >&2
echo "$SELF: template: $template" >&2

for required in run_harness.sh start.sh; do
  if [[ ! -f "$template/$required" ]]; then
    die 7 "template '$template' is missing required file '$required'"
  fi
  if [[ ! -x "$template/$required" ]]; then
    die 7 "template '$template' has '$required' without the executable bit; run: chmod +x \"$template/$required\""
  fi
done

# Task 5: stale .sandbox handling. Reached only when $workdir/run_harness.sh
# is entirely absent (Task 2) and $template is fully validated (Task 4), so
# the deletion below can never leave the user with neither a sandbox nor a
# replacement.
if [[ -e "$workdir/.sandbox" ]]; then
  if [[ ! -t 0 ]]; then
    die 6 "$workdir/.sandbox exists but is incomplete; remove it manually and re-run: rm -r \"$workdir/.sandbox\""
  fi

  echo -e "\033[33mWarning: '$workdir/.sandbox' exists but 'run_harness.sh' is missing — the sandbox is incomplete.\033[0m" >&2
  echo -e "\033[33mIt will be re-created from template '$template'.\033[0m" >&2
  echo -e "\033[33mThis is self-healing: it is the expected result of a previous run interrupted between the copy and completion; re-creating from the template repairs it.\033[0m" >&2

  reply=""
  read -r -p "delete .sandbox and re-create from $template? [y/N] " reply || reply=""
  case "$reply" in
    y | Y) ;;
    *) die 6 "aborted; '$workdir/.sandbox' left untouched" ;;
  esac

  rm -r "$workdir/.sandbox"
fi

# Task 6-8: provisioning continues here with $template validated (both
# run_harness.sh and start.sh present and executable) and $harness set to a
# validated entry from HARNESSES.

# T5-S1: a dangling symlink named .sandbox is invisible to Task 5's `-e`
# test (which is false for a broken symlink), so it reaches here untouched.
# Without this guard, `mkdir -p` would fail with a bare `File exists` /
# `Not a directory` and abort via `set -e` as an unexplained exit 1. Every
# other kind of pre-existing `.sandbox` (regular file, socket, symlink to
# either) is intercepted earlier by Task 5's `-e` test with exit 6.
if [[ -e "$workdir/.sandbox" || -L "$workdir/.sandbox" ]] && [[ ! -d "$workdir/.sandbox" ]]; then
  die 9 "$workdir/.sandbox exists but is not a directory"
fi

mkdir -p "$workdir/.sandbox"
cp -R "$template/." "$workdir/.sandbox/"

# Task 7-8: provisioning continues here with $workdir/.sandbox populated
# from $template.
