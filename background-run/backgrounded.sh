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
# - Check the status of services and tail their logs
# - List all running services with their PIDs
#
# Non-Features:
# - No automatic restarts e.g. on failure or system reboot
# - No manual restarts (you have to call `backgrounded stop <name>` followed by `backgrounded start <name> <command>` to restart)
# - No security features (services run with the same permissions as the user who started them)
# - No dependency management
# - No user permissions or system-level services (runs entirely in user space)
# - No configuration files (all settings are via environment variables or command-line flags)
# - No windows (Unix-like systems only)
# - No support for running multiple instances of the same service name (service names must be unique)
# - No environment variable management (services inherit the environment of the shell that started them)
# - No advanced logging features (logs are simple stdout/stderr redirection to a file)
# - No resource monitoring (CPU, memory, etc.), limiting or alerting

PID_DIR="$HOME/.local/state/backgrounded"

# Timeout in seconds to wait for a service to stop gracefully before sending SIGKILL
# Can be overridden with `backgrounded stop --timeout N <name>`
STOP_TIMEOUT=10

usage() {
    echo "Usage: backgrounded <command> [args...]"
    echo "Commands:"
    echo "  start [--no-log] <name> <command...>   Start a background service with the given name and command."
    echo "  stop [--timeout N] <name>              Stop the background service with the given name."
    echo "  status <name>                          Show the status of a specific service."
    echo "  logs <name>                            Tail the log file of a running service."
    echo "  list                                   List all running background services."
}

start() {
    if [[ $# -lt 2 ]]; then
        echo "Error: Missing arguments." >&2
        echo "Usage: backgrounded start <name> <command...>" >&2
        return 1
    fi

    local log=true
    if [[ "$1" == "--no-log" ]]; then
        log=false
        shift
    fi

    local name="$1"
    shift

    mkdir -p "$PID_DIR"
    local pidfile="$PID_DIR/${name}.pid"
    local logfile="$PID_DIR/${name}.log"

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

    # Run in background, fully detached from the terminal session
    # setsid is preferred for proper daemonization, but if it's not available, we can still background and disown
    if command -v setsid > /dev/null 2>&1; then
        if $log; then
            setsid "$@" >> "$logfile" 2>&1 &
        else
            setsid "$@" > /dev/null 2>&1 &
        fi
        local new_pid=$!
        echo "$new_pid" > "$pidfile"
    else
        if $log; then
            "$@" >> "$logfile" 2>&1 &
        else
            "$@" > /dev/null 2>&1 &
        fi
        local new_pid=$!
        echo "$new_pid" > "$pidfile"
        disown "$new_pid"
    fi

    echo "Service '$name' started (PID $new_pid)."
}

stop() {
    if [[ -z "$1" ]]; then
        echo "Error: No service name provided." >&2
        echo "Usage: backgrounded stop <name>" >&2
        return 1
    fi

    local timeout="$STOP_TIMEOUT"
    if [[ "$1" == "--timeout" ]]; then
        timeout="$2"
        shift 2
    fi

    local name="$1"
    local pidfile="$PID_DIR/${name}.pid"

    if [[ ! -f "$pidfile" ]]; then
        echo "No PID file found for service '$name'." >&2
        return 1
    fi

    local pid=$(cat "$pidfile")

    if kill -0 "$pid" 2>/dev/null; then
        kill "$pid"

        # Wait for graceful shutdown
        local ticks=$(( timeout * 10 ))
        for i in $(seq 1 "$ticks"); do
            echo -n .
            kill -0 "$pid" 2>/dev/null || break
            sleep 0.1
        done
        echo

        # Still alive? Force kill.
        if kill -0 "$pid" 2>/dev/null; then
            kill -9 "$pid"
            echo "Service '$name' (PID $pid) did not stop gracefully, sent SIGKILL."
        else
            echo "Service '$name' (PID $pid) has been terminated."
        fi
        rm "$pidfile"
        rm "$PID_DIR/${name}.log"
    else
        echo "Service '$name' was already dead. Cleaned up orphaned PID file."
        rm "$pidfile"
        rm "$PID_DIR/${name}.log"
    fi
}

logs() {
    if [[ -z "$1" ]]; then
        echo "Error: No service name provided." >&2
        echo "Usage: backgrounded logs <name>" >&2
        return 1
    fi

    local name="$1"
    local logfile="$PID_DIR/${name}.log"

    if [[ ! -f "$logfile" ]]; then
        echo "No log file for service '$name'." >&2
        return 1
    fi

    tail -f "$logfile"
}

status() {
    if [[ -z "$1" ]]; then
        echo "Error: No service name provided." >&2
        echo "Usage: backgrounded status <name>" >&2
        return 1
    fi

    local name="$1"
    local pidfile="$PID_DIR/${name}.pid"
    local logfile="$PID_DIR/${name}.log"

    if [[ ! -f "$pidfile" ]]; then
        echo "Service '$name' is unknown." >&2
        return 1
    fi

    local pid=$(cat "$pidfile")
    if kill -0 "$pid" 2>/dev/null; then
        echo "Service '$name' is running (PID: $pid)"
    else
        echo "Service '$name' is dead (PID: $pid)"
    fi

    if [[ -f "$logfile" ]]; then
        echo "Log: $logfile"
        echo "or call 'backgrounded logs $name'"
    else
        echo "No logfile"
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
            echo "$name (PID: $pid) [DEAD]"
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
    list
    ;;
  *) usage ;;
esac
