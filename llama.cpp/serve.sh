#!/usr/bin/env bash

ctx=102400
parallel=1
ctx_size=$((ctx * parallel))

llama-server \
  --models-dir "/Users/mkuckert/ai/models/llama.cpp" \
  --models-preset "/Users/mkuckert/ai/models/llama.cpp/preset.ini" \
  --no-webui \
  --n-gpu-layers all \
  --flash-attn on \
  --ctx-size $ctx_size \
  --batch-size 2048 \
  --ubatch-size 1024 \
  --mlock \
  --parallel $parallel \
  --threads 12 \
  --cache-type-k q8_0 \
  --cache-type-v q8_0 \
  --mmproj-offload \
  --jinja
