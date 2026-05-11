#!/usr/bin/env bash

BUILDDIR=~/private/dev
TOOLDIR=llamawatch
cd $BUILDDIR

if [ ! -d $TOOLDIR ]; then
  git clone "git@github.com:MKuckert/LlamaWatch.git"
  cd $TOOLDIR
else
  cd $TOOLDIR
  git pull
fi

echo "Building LlamaWatch $(git log --pretty=tformat:"%H" -1)"

make

cp -r $BUILDDIR/LlamaWatch/build/LlamaWatch.app /Applications

echo "Built to $BUILDDIR/$TOOLDIR/LlamaWatch/build/LlamaWatch.app and installed to /Applications"
