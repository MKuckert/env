#!/usr/bin/env bash
colima model serve huggingface://unsloth/Qwen3.6-27B-GGUF -p ai --port $COLIMA_AI_PORT
