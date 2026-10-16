#!/usr/bin/env bash

set -Eeuo pipefail

echo "🤖 Starting AI services..."
backgrounded.sh start omlx omlx serve
