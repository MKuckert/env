#!/usr/bin/env bash

cd ~/repos

INSTALLDIR=hound-mcp

if [ ! -d $INSTALLDIR ]; then
  gh repo clone MKuckert/master-fetch $INSTALLDIR
  cd $INSTALLDIR
else
  cd $INSTALLDIR
  git pull --ff
fi
