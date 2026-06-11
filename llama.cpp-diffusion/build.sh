#!/usr/bin/env bash

cd ~/private/dev

if [ ! -d llama.cpp-diffusion ]; then
  gh repo clone ggml-org/llama.cpp llama.cpp-diffusion
  cd llama.cpp-diffusion
else
  cd llama.cpp-diffusion
  git pull --ff
fi

gh pr checkout 24423

echo "Building llama.cpp-diffusion $(git tag --points-at HEAD)"

cmake -B build \
  -DBUILD_SHARED_LIBS=OFF \
  -DGGML_CUDA=OFF \
  -DGGML_METAL=ON \
  -DGGML_NATIVE=ON \
  -DGGML_METAL_EMBED_LIBRARY=ON \
  -DGGML_LTO=ON
cmake --build build --config Release -j 8

echo "Built to ~/private/dev/llama.cpp-diffusion/build/bin"
