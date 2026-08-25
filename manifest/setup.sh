#!/usr/bin/env bash

cd ~/repos

if [ ! -d manifest ]; then
  git clone "git@github.com:mnfst/manifest.git"
  cd manifest
else
  cd manifest
  git pull --ff
fi

echo "ℹ️ Ensure to create and edit ~/repos/manifest/docker/.env before running"
echo "Setup to ~/repos/manifest"
