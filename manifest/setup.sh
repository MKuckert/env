#!/usr/bin/env bash

cd ~/private/dev

if [ ! -d manifest ]; then
  git clone "git@github.com:mnfst/manifest.git"
  cd manifest
else
  cd manifest
  git pull
fi

echo "ℹ️ Ensure to create and edit ~/private/dev/manifest/docker/.env before running"
echo "Setup to ~/private/dev/manifest"
