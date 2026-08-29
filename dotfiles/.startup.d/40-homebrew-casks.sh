#!/usr/bin/env bash

set -Eeuo pipefail

echo "📦 Upgrading outdated brew casks..."
brew upgrade --cask --greedy --no-ask --verbose
