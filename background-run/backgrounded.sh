#!/usr/bin/env bash
# Slim Background Service Manager (backgrounded)
#
# A lightweight, zero-dependency bash solution for macOS (and Linux) to run any arbitrary shell command in the
# background, keep it running across terminal sessions, and easily stop or monitor it later.
#
# This project serves as a clean, simple alternative to complex `launchd` XML configurations or rigid Homebrew services
# when you just need to quickly daemonize a command using PID files.
#
# Features:
# - Start any command as a background service with a unique name
# - Automatically manage PID files and logs in a user-specific directory
# - Stop services gracefully with a configurable timeout before force-killing
# - List all running services with their PIDs
# - Check the status of services and tail their logs
#
# Non-Features:
# - No automatic restarts e.g. on failure or system reboot
# - No manual restarts (you have to call `backgrounded stop <name>` followed by `backgrounded start <name> <command>` to restart)
# - No security features (services run with the same permissions as the user who started them)
# - No dependency management
# - No locking. If you hammer `backgrounded start <name>` in parallel, it will start the process multiple times and
#   overwrite the PID file, leaving orphaned processes. Simply don't do that.
# - No log file handling beyond simple stdout/stderr redirection (no log rotation, compression, archiving, etc.)
# - No user permissions or system-level services (runs entirely in user space)
# - No configuration files (all settings are via environment variables or command-line flags)
# - No windows
# - No linux (or at least not tested on linux, but could work in theory)
# - No progress group handling. If the started process spawns child processes, they will not be tracked or managed by
#   `backgrounded` e.g. not killed by `stop`.
# - No support for running multiple instances of the same service name (service names must be unique)
# - No environment variable management (services inherit the environment of the shell that started them)
# - No advanced logging features (logs are simple stdout/stderr redirection to a file)
# - No resource monitoring (CPU, memory, etc.), limiting or alerting

set -euo pipefail

PID_DIR="$HOME/.local/state/backgrounded"

# Timeout in seconds to wait for a service to stop gracefully before sending SIGKILL
# Can be overridden with `backgrounded stop --timeout N <name>`
STOP_TIMEOUT=10

pidfile() { echo "$PID_DIR/${1}.pid"; }
logfile() { echo "$PID_DIR/${1}.log"; }

validate_name() {
    local name="$1"
    if [[ ! "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo "Error: Invalid service name '$name'." >&2
        echo "Only alphanumeric characters, dashes (-), and underscores (_) are allowed." >&2
        return 1
    fi
}

read_pid() {
    local name="$1"
    local pf=$(pidfile "$name")

    if [[ ! -f "$pf" ]]; then
        echo "No PID file found for service '$name'." >&2
        return 1
    fi

    local pid
    pid=$(cat "$pf")
    if [[ ! "$pid" =~ ^[0-9]+$ ]]; then
        echo "Corrupt PID file for '$name': '$pid'. Expected a number." >&2
        return 1
    fi

    echo "$pid"
}

remove_service() {
    local name="$1"
    rm -f "$(pidfile "$name")"
    rm -f "$(logfile "$name")"
}

usage() {
    echo "Usage: backgrounded <command> [args...]"
    echo "Commands:"
    echo "  start [--no-log] <name> <command...>   Start a background service with the given name and command."
    echo "  stop [--timeout N] <name>              Stop the background service with the given name"
    echo "                                         (Removes the log file too. Persist before calling stop!)"
    echo "  status <name>                          Show the status of a specific service."
    echo "  logs <name>                            Tail the log file of a running service."
    echo "  list [--clean]                         List all background services."
}

start() {
    local log=true
    if [[ "${1:-}" == "--no-log" ]]; then
        log=false
        shift
    fi

    if [[ $# -lt 2 ]]; then
        echo "Error: Missing arguments." >&2
        echo "Usage: backgrounded start <name> <command...>" >&2
        return 1
    fi

    local name="$1"
    shift
    validate_name "$name" || return 1

    mkdir -p "$PID_DIR"
    local pf=$(pidfile "$name")
    local lf=$(logfile "$name")

    if [[ -f "$pf" ]]; then
        local old_pid=$(cat "$pf")
        if kill -0 "$old_pid" 2>/dev/null; then
            echo "Service '$name' is already running with PID $old_pid." >&2
            return 1
        fi
    fi

    # Run in background, fully detached from the terminal session
    if $log; then
        "$@" >> "$lf" 2>&1 &
    else
        "$@" > /dev/null 2>&1 &
    fi
    local new_pid=$!
    echo "$new_pid" > "$pf"
    disown "$new_pid"

    echo "Service '$name' started (PID $new_pid)."
}

stop() {
    local timeout="$STOP_TIMEOUT"
    if [[ "${1:-}" == "--timeout" ]]; then
        if [[ -z "${2:-}" || -z "${3:-}" ]]; then
            echo "Error: --timeout requires a value (and the service name)." >&2
            return 1
        fi
        timeout="$2"
        shift 2
    fi

    if [[ -z "${1:-}" ]]; then
        echo "Error: No service name provided." >&2
        echo "Usage: backgrounded stop <name>" >&2
        return 1
    fi

    local name="$1"
    validate_name "$name" || return 1
    local pid
    pid=$(read_pid "$name") || return 1

    if kill -0 "$pid" 2>/dev/null; then
        kill "$pid"

        # Wait for graceful shutdown
        local ticks=$(( timeout * 10 ))
        local i=0
        while (( i < ticks )); do
            printf '.' >&2
            kill -0 "$pid" 2>/dev/null || break
            sleep 0.1
            i=$(( i + 1 ))
        done
        echo >&2

        # Still alive? Force kill.
        if kill -0 "$pid" 2>/dev/null; then
            kill -9 "$pid"
            echo "Service '$name' (PID $pid) did not stop gracefully, sent SIGKILL."
        else
            echo "Service '$name' (PID $pid) has been terminated."
        fi
    else
        echo "Service '$name' was already dead. Cleaned up orphaned PID file."
    fi
    remove_service "$name"
}

logs() {
    if [[ -z "${1:-}" ]]; then
        echo "Error: No service name provided." >&2
        echo "Usage: backgrounded logs <name>" >&2
        return 1
    fi

    local name="$1"
    validate_name "$name" || return 1
    local lf=$(logfile "$name")

    if [[ ! -f "$lf" ]]; then
        echo "No log file for service '$name'." >&2
        return 1
    fi

    tail -f "$lf"
}

status() {
    if [[ -z "${1:-}" ]]; then
        echo "Error: No service name provided." >&2
        echo "Usage: backgrounded status <name>" >&2
        return 1
    fi

    local name="$1"
    validate_name "$name" || return 1
    local lf=$(logfile "$name")
    local pid
    pid=$(read_pid "$name") || return 1

    if kill -0 "$pid" 2>/dev/null; then
        echo "Service '$name' is running (PID: $pid)"
    else
        echo "Service '$name' is dead (PID: $pid)"
    fi

    if [[ -f "$lf" ]]; then
        echo "Log: $lf"
        echo " or call 'backgrounded logs $name'"
    else
        echo "No logfile"
    fi
}

list() {
    local clean=false
    if [[ "${1:-}" == "--clean" ]]; then
        clean=true
    fi

    local files=("$PID_DIR"/*.pid)
    if [[ ! -e "${files[0]}" ]]; then
        echo "No services running."
        return 0
    fi

    for f in "${files[@]}"; do
        local name=$(basename "$f" .pid)
        local pid
        pid=$(read_pid "$name") || continue

        if kill -0 "$pid" 2>/dev/null; then
            echo "$name (PID: $pid)"
        else
            echo "$name (PID: $pid) [DEAD]"
            if $clean; then
                remove_service "$name"
            fi
        fi
    done
}

case "${1:-}" in
  start)
    shift
    start "$@"
    ;;
  stop)
    shift
    stop "$@"
    ;;
  logs)
    shift
    logs "$@"
    ;;
  status)
    shift
    status "$@"
    ;;
  list)
    shift
    list "$@"
    ;;
  help|--help|-h|-?)
    usage
    ;;
  *)
    usage
    exit 1
    ;;
esac
