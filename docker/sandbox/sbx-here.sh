#!/usr/bin/env bash
set -euo pipefail

SBX_FILE=".sbx"
SBX_NAME=""
AGENT=""
WORKSPACE=""
IS_NEW=false

# Environment detection & state extraction
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    IN_GIT=true
    SBX_NAME=$(git config --local sbx.name 2>/dev/null || true)
    WORKSPACE=$(git rev-parse --show-toplevel)
else
    IN_GIT=false
    WORKSPACE="$PWD"
    if [[ -f "$SBX_FILE" ]]; then
        SBX_NAME=$(tr -d '\r\n' < "$SBX_FILE" | xargs)
    fi
fi

# Interactive initialization block (Only triggers if state is empty)
if [[ -z "$SBX_NAME" ]]; then
    IS_NEW=true

    # Derive a Docker-safe default name from the current directory
    CLEAN_DIR=$(basename "$PWD" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9_.-]/-/g')

    echo "No docker sandbox name found."
    echo "Select the target harness:"

    PS3="Enter choice (1-3): "
    options=("claude" "copilot" "opencode")
    select AGENT in "${options[@]}"; do
        if [[ -n "$AGENT" ]]; then
            break
        fi
        echo "Invalid selection. Pick a valid harness."
    done

    DEFAULT_NAME="${AGENT}-${CLEAN_DIR}"

    read -r -p "Enter sandbox name [$DEFAULT_NAME]: " USER_INPUT
    SBX_NAME="${USER_INPUT:-$DEFAULT_NAME}"

    # Persist tracking token based on context
    if [[ "$IN_GIT" == true ]]; then
        git config --local sbx.name "$SBX_NAME"
        echo "Context bound to local git config."
    else
        echo "$SBX_NAME" > "$SBX_FILE"
        echo "Context bound to standalone file ($SBX_FILE)."
    fi
fi

if [[ "$IS_NEW" == true ]]; then
    echo "Creating docker sandbox $SBX_NAME"
    sbx create --cpus 4 --memory 4g --name "$SBX_NAME" "$AGENT" "$WORKSPACE"
fi

exec sbx run "$SBX_NAME"
