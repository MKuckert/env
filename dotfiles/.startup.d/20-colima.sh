#!/usr/bin/env bash

set -Eeuo pipefail

echo "🖥️ Starting colima..."
colima start containerd
colima start docker-qemu
