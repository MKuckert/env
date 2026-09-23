#!/usr/bin/env bash

# offical model
#MODEL=incoai/Qwen3.8-27B-Splash
# "better" Swift optimized model
MODEL=SiliconSpecies/Swift-Qwen3.8-27B-Splash

CONTEXT=150K

# hf download $MODEL
splash serve --model $MODEL \
  --host 0.0.0.0 \
  --max-context $CONTEXT \
  --no-webui
