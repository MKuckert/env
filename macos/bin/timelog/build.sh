#!/usr/bin/env bash

BUILDDIR=~/private/dev
TOOLDIR=timelog
cd $BUILDDIR

if [ ! -d $TOOLDIR ]; then
  git clone "git@github.com:qbart/timelog.git"
  cd $TOOLDIR
else
  cd $TOOLDIR
  git pull
fi

echo "Building timelog $(git log --pretty=tformat:"%H" -1)"

make build

bin/timelog autocomplete install > ~/.config/bash_completion.d/timelog

echo "Built to $BUILDDIR/$TOOLDIR/bin"
