#!/usr/bin/env bash

set -Eeuo pipefail

echo "🔑 Loading ssh keys..."
ssh-add "${HOME}/private/sec/id_ed25519"
ssh-add "${HOME}/work/sec/id_ed25519"
