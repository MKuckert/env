#!/usr/bin/env bash

mlx_lm.server \
  --model /Users/mkuckert/ai/models/omlx/mlx-community-Qwen3.6-27B-4bit \
  --host 0.0.0.0 \
  --port $MLXLM_PORT \
  --use-default-chat-template \
  --temp 0.7 \
  --top-p 0.80 \
  --top-k 20 \
  --min-p 0 \
  --chat-template-args '{"preserve_thinking": true}'
