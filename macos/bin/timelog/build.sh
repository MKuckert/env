#!/usr/bin/env bash

cd ~/private/dev

if [ ! -d timelog ]; then
  git clone "git@github.com:qbart/timelog.git"
  cd timelog
else
  cd timelog
  git pull
fi

echo "Building timelog $(git log --pretty=tformat:"%H" -1)"

make build

bin/timelog autocomplete install > ~/.config/bash_completion.d/timelog

echo "Built to ~/private/dev/timelog/bin"
