#!/usr/bin/env bash

set -Eeuo pipefail

echo "🤖 Starting AI services..."
"${HOME}/env/manifest/start.sh"
backgrounded.sh start omlx omlx serve
