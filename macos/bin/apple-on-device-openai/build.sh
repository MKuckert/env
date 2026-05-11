#!/usr/bin/env bash

BUILDDIR=~/private/dev
TOOLDIR=apple-on-device-openai
cd $BUILDDIR

if [ ! -d $TOOLDIR ]; then
  git clone "git@github.com:MKuckert/apple-on-device-openai.git"
  cd $TOOLDIR
else
  cd $TOOLDIR
  git pull
fi

echo "Opening project in xcode so you can build it from there"

open AppleOnDeviceOpenAI.xcodeproj
