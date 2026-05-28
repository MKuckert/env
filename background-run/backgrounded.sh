#!/usr/bin/env bash
# Slim Background Service Manager (backgrounded)
#
# A lightweight, zero-dependency POSIX shell solution for macOS (and Linux) to run any arbitrary shell command in the background, keep it running across terminal sessions, and easily stop or monitor it later.
#
# This project serves as a clean, simple alternative to complex `launchd` XML configurations or rigid Homebrew services when you just need to quickly daemonize a command using PID files.

PID_DIR="$HOME/.local/state/backgrounded"
mkdir -p "$PID_DIR"

usage() {
    echo "Usage: backgrounded <command> [args...]"
    echo "Commands:"
    echo "  start <name> <command...>  Start a background service with the given name and command."
    echo "  stop <name>                Stop the background service with the given name."
    echo "  list                       List all running background services."
    exit 1
}

start() {
    if [[ $# -lt 2 ]]; then
        echo "Error: Missing arguments." >&2
        echo "Usage: backgrounded start <name> <command...>" >&2
        return 1
    fi

    local name="$1"
    shift
    local pidfile="$PID_DIR/${name}.pid"

    # Sanity check: Ensure the name only contains alphanumeric characters, dashes, or underscores
    if [[ ! "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo "Error: Invalid service name '$name'." >&2
        echo "Only alphanumeric characters, dashes (-), and underscores (_) are allowed." >&2
        return 1
    fi

    if [[ -f "$pidfile" ]]; then
        local old_pid=$(cat "$pidfile")
        if kill -0 "$old_pid" 2>/dev/null; then
            echo "Service '$name' is already running with PID $old_pid." >&2
            return 1
        fi
    fi

    # Run in background, detach stdin/stdout/stderr properly
    nohup "$@" > /dev/null 2>&1 &
    local new_pid=$!
    echo "$new_pid" > "$pidfile"

    echo "Service '$name' started (PID $new_pid)."
}

stop() {
    if [[ -z "$1" ]]; then
        echo "Error: No service name provided." >&2
        echo "Usage: backgrounded stop <name>" >&2
        return 1
    fi

    local name="$1"
    local pidfile="$PID_DIR/${name}.pid"

    if [[ ! -f "$pidfile" ]]; then
        echo "No PID file found for service '$name'." >&2
        return 1
    fi

    local pid=$(cat "$pidfile")
    rm -f "$pidfile"

    if kill -0 "$pid" 2>/dev/null; then
        kill "$pid"
        echo "Service '$name' (PID $pid) has been terminated."
    else
        echo "Service '$name' was already dead. Cleaned up orphaned PID file."
    fi
}

list() {
    local files=("$PID_DIR"/*.pid)
    if [[ ! -e "${files[0]}" ]]; then
        echo "No services running."
        return 0
    fi

    for f in "${files[@]}"; do
        local name=$(basename "$f" .pid)
        local pid=$(cat "$f")
        if kill -0 "$pid" 2>/dev/null; then
            echo "$name (PID: $pid)"
        else
            echo "$name (PID: $pid) [DEAD - orphaned]"
        fi
    done
}

case "${1:-}" in
  start)
    shift
    start $@
    ;;
  stop)
    shift
    stop $@
    ;;
  list)
    shift
    list
    ;;
  *) usage ;;
esac
