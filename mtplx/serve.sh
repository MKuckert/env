#!/usr/bin/env bash

ctx=65536
parallel=1
ctx_size=$((ctx * parallel))

mtplx serve \
  --model /Users/mkuckert/ai/models/mtplx/Youssofal--Qwen3.6-27B-MTPLX-Optimized-Speed \
  --cache-dir /Users/mkuckert/ai/models/mtplx \
  --host 0.0.0.0 \
  --port $MTPLX_PORT \
  --api-key $MTPLX_API_KEY \
  --no-stats-footer \
  --preserve-thinking on
