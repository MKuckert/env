#!/usr/bin/env bash

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
"${SCRIPT_DIR}/setup.sh"

cd ~/private/dev/manifest/docker
nerdctl compose up -d --pull always
