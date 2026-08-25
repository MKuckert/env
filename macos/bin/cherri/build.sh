#!/usr/bin/env bash

BUILDDIR=~/repos
TOOLDIR=cherri
cd $BUILDDIR

if [ ! -d $TOOLDIR ]; then
  git clone "git@github.com:electrikmilk/cherri.git"
  cd $TOOLDIR
else
  cd $TOOLDIR
  git pull --ff
fi

echo "Building cherri $(git log --pretty=tformat:"%H" -1)"

go build

echo "Built to $BUILDDIR/$TOOLDIR"
