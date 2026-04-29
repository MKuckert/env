#!/usr/bin/env bash

cd ~/private/dev

if [ ! -d llama.cpp ]; then
  git clone "git@github.com:ggml-org/llama.cpp.git"
  cd llama.cpp
else
  cd llama.cpp
  git pull
fi

echo "Building llama.cpp $(git tag --points-at HEAD)"

cmake -B build \
  -DBUILD_SHARED_LIBS=OFF \
  -DGGML_METAL=ON \
  -DGGML_NATIVE=ON \
  -DGGML_METAL_EMBED_LIBRARY=ON \
  -DGGML_LTO=ON
cmake --build build --config Release -j 8

build/bin/llama-cli --completion-bash > ~/.config/bash_completion.d/llama

echo "Built to ~/private/dev/llama.cpp/build/bin"
