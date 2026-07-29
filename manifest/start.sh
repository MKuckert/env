#!/usr/bin/env bash

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
"${SCRIPT_DIR}/setup.sh"

cd ~/repos/manifest/docker
nerdctl compose up -d --pull always
