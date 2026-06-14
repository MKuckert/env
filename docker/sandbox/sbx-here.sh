#!/usr/bin/env bash
set -euo pipefail

SBX_FILE=".sbx"
SBX_NAME=""
AGENT=""
WORKSPACE=""
CREATE=false
REMOVE=false

# Parse CLI flags
while [[ $# -gt 0 ]]; do
    case "$1" in
        --recreate)
            CREATE=true
            REMOVE=true
            shift
            ;;
        *)
            echo "Unknown flag: $1"
            exit 1
            ;;
    esac
done

# Environment detection & state extraction
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    IN_GIT=true
    SBX_NAME=$(git config --local sbx.name 2>/dev/null || true)
    AGENT=$(git config --local sbx.agent 2>/dev/null || true)
    WORKSPACE=$(git rev-parse --show-toplevel)
else
    IN_GIT=false
    WORKSPACE="$PWD"
    if [[ -f "$SBX_FILE" ]]; then
        SBX_NAME=$(tr -d '\r\n' < "$SBX_FILE" | xargs)
    fi
fi

# Prompt user to select an agent harness
select_harness() {
    PS3="Enter choice (1-3): "
    options=("claude" "copilot" "opencode")
    select agent in "${options[@]}"; do
        if [[ -n "$agent" ]]; then
            echo "$agent"
            return 0
        fi
        echo "Invalid selection. Pick a valid harness."
    done
    PS3=""
}

# Interactive initialization block (Only triggers if state is empty)
if [[ -z "$SBX_NAME" ]]; then
    CREATE=true

    # Derive a Docker-safe default name from the current directory
    CLEAN_DIR=$(basename "$PWD" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9_.-]/-/g')

    echo "No docker sandbox name found."
    echo "Select the target harness:"

    AGENT=$(select_harness)

    DEFAULT_NAME="${AGENT}-${CLEAN_DIR}"

    read -r -p "Enter sandbox name [$DEFAULT_NAME]: " USER_INPUT
    SBX_NAME="${USER_INPUT:-$DEFAULT_NAME}"

    # Persist tracking token based on context
    if [[ "$IN_GIT" == true ]]; then
        git config --local sbx.name "$SBX_NAME"
        git config --local sbx.agent "$AGENT"
        echo "Context bound to local git config."
    else
        echo "$SBX_NAME" > "$SBX_FILE"
        echo "Context bound to standalone file ($SBX_FILE)."
    fi
fi

# REMOVE sandbox
if [[ "$REMOVE" == true ]]; then
    echo "Removing existing sandbox: $SBX_NAME"
    sbx rm "$SBX_NAME" || echo "Sandbox not found or already removed."
fi

# Create sandbox and copy config files if new
if [[ "$CREATE" == true ]]; then
    # Ensure AGENT is set before creating
    if [[ -z "$AGENT" ]]; then
        echo "Select the harness for this sandbox:"
        AGENT=$(select_harness)
    fi

    echo "Creating docker sandbox $SBX_NAME"
    sbx create --cpus 4 --memory 4g --name "$SBX_NAME" "$AGENT" "$WORKSPACE"
fi

exec sbx run "$SBX_NAME"
