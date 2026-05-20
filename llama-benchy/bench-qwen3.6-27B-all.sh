#!/usr/bin/env bash

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# llama-benchy
# Usage: bench <base-url> <model> [api-key]
bench() {
	local url="$1"
	local model="$2"
	local api_key="${3:-}"

	if [[ -z "$url" || -z "$model" ]]; then
		echo "Usage: bench <base-url> <model> [api-key]" >&2
		return 1
	fi

  # url, model, api-key
	local args=(--base-url "$url" --model "$model")
	[[ -n "$api_key" ]] && args+=(--api-key "$api_key")

  # Method to measure latency:
  # - 'api' (call list models function)
  # - default, 'generation' (single token generation)
  # - 'none' (skip latency measurement).
	args+=(--latency-mode generation)

  # List of prompt processing token counts (Default: [2048]).
  args+=(--pp 2048)

	# List of token generation counts (Default: [32]).
	args+=(--tg 32 1024)

	# List of context depths (Default: [0]).
	args+=(--depth 0 1024 8192)

	#  Enable prefix caching performance measurement. When enabled (and depth > 0),
	# it performs a two-step benchmark: first loading the context (reported as ctx_pp),
	# then running the prompt with the cached context.
	args+=(--enable-prefix-caching)

	# File to save results to and output format
	args+=(--save-result $SCRIPT_DIR/$(gdate +%Y-%m-%d-%H-%M).csv)
	args+=(--format csv)

	# Number of runs per test (Default: 3).
	args+=(--runs 3)

	uvx llama-benchy "${args[@]}"
}

instruct_user() {
  read -n 1 -s -r -p "$*" && echo
}

echo "Benchmark for Qwen3.6-27B on different inference providers"

# MTPLX
instruct_user "Start MTPLX server and press any key to continue..."
echo "Benchmarking MTPLX…"
bench "http://127.0.0.1:${MTPLX_PORT}/v1" "mtplx-qwen36-27b-optimized-speed" "${MTPLX_API_KEY}"
instruct_user "Stop MTPLX server and press any key to continue..."

# mlx-lm
instruct_user "Start mlx-lm server and press any key to continue..."
echo "Benchmarking mlx-lm…"
bench "http://127.0.0.1:${MLXLM_PORT}/v1" "mlx-community/Qwen3.6-27B-4bit"
instruct_user "Stop mlx-lm server and press any key to continue..."

# llama.cpp
instruct_user "Start llama.cpp server and press any key to continue..."
echo "Benchmarking llama.cpp…"
bench "http://127.0.0.1:${LLAMA_ARG_PORT}/v1" "Qwen3.6-27B-Q4_K_M-MTP-Instruct" "${LLAMA_API_KEY}"
instruct_user "Stop llama.cpp server and press any key to continue..."
