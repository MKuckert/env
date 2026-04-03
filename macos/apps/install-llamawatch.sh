#!/usr/bin/env bash
BUILDDIR=$TMPDIR/llamawatch
mkdir -p $BUILDDIR
cd $BUILDDIR
git clone git@github.com:MKuckert/LlamaWatch.git
cd LlamaWatch
make
cp -r $BUILDDIR/LlamaWatch/build/LlamaWatch.app /Applications
