#!/usr/bin/env bash
BUILDDIR=~/work/dev
mkdir -p $BUILDDIR
cd $BUILDDIR
git clone https://github.com/gety-ai/apple-on-device-openai.git
cd apple-on-device-openai
open AppleOnDeviceOpenAI.xcodeproj
