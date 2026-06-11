#!/usr/bin/env bash

~/private/dev/llama.cpp-diffusion/build/bin/llama-diffusion-cli \
  --model "/Users/mkuckert/ai/models/llama.cpp-diffusion/diffusiongemma-26B-A4B-it-Q4_K_M.gguf" \
  --n-gpu-layers 99 \
  --n-predict 2048 \
  --diffusion-visual \
  --conversation
