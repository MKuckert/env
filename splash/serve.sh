#!/usr/bin/env bash

MODEL=ukisai/Swift-1.5-Qwen3.8-27b
CONTEXT=150K

# hf download $MODEL
splash serve --model $MODEL \
  --host 0.0.0.0 \
  --max-context $CONTEXT \
  --no-webui
