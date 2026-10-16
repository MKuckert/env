#!/usr/bin/env bash

set -Eeuo pipefail

echo "🖥️ Starting colima containerd..."
colima start containerd
