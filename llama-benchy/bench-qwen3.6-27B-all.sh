#!/usr/bin/env bash

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
BASE_DIR=$(dirname "$SCRIPT_DIR")
RESULTS_DIR=$SCRIPT_DIR/$(gdate +%Y-%m-%d)/raw
mkdir -p "$RESULTS_DIR"

# llama-benchy
# Usage: bench <base-url> <name> <model> [api-key]
bench() {
	local url="$1"
	local name="$2"
	local model="$3"
	local api_key="${4:-}"

	if [[ -z "$url" || -z "$name" || -z "$model" ]]; then
		echo "Usage: bench <base-url> <name> <model> [api-key]" >&2
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
	args+=(--tg 1024)

	# List of context depths (Default: [0]).
	args+=(--depth 2048)

	# Enable prefix caching performance measurement. When enabled (and depth > 0),
	# it performs a two-step benchmark: first loading the context (reported as ctx_pp),
	# then running the prompt with the cached context.
	args+=(--enable-prefix-caching)

	# File to save results to and output format
	args+=(--save-result "$RESULTS_DIR/$(gdate +%Y-%m-%d-%H-%M)-$name.csv")
	args+=(--format csv)

	# Number of runs per test (Default: 3).
	args+=(--runs 3)

	uvx llama-benchy "${args[@]}"
}

start() {
  local name=$1
  shift
  "$BASE_DIR/background-run/backgrounded.sh" start $name "$@" || {
    echo "Failed to start inference provider. Aborting." >&2
    exit 1
  }
  sleep 20 # Wait for the server to start
}
stop() {
  "$BASE_DIR/background-run/backgrounded.sh" stop --keep-log $1 || {
    echo "Failed to stop inference provider. Aborting." >&2
    exit 1
  }
  sleep 5 # Wait for the server to stop
}

bench_mtplx() {
  echo "Benchmarking MTPLX…"
  start mtplx "$BASE_DIR/mtplx/serve.sh"
  bench "http://127.0.0.1:${MTPLX_PORT}/v1" mtplx "mtplx-qwen36-27b-optimized-speed" "${MTPLX_API_KEY}"
  stop mtplx
}

bench_mlx_lm() {
  echo "Benchmarking mlx-lm…"
  start mlxlm "$BASE_DIR/mlx-lm/serve.sh"
  bench "http://127.0.0.1:${MLXLM_PORT}/v1" mlx-lm "mlx-community/Qwen3.6-27B-4bit"
  stop mlxlm
}

bench_llama_cpp() {
  echo "Benchmarking llama.cpp…"
  start llama_cpp "$BASE_DIR/llama.cpp/serve.sh"
  bench "http://127.0.0.1:${LLAMA_ARG_PORT}/v1" llama.cpp "Qwen3.6-27B-Q4_K_M-MTP-Instruct" "${LLAMA_API_KEY}"
  stop llama_cpp
}

bench_omlx() {
  echo "Benchmarking omlx…"
  start omlx omlx serve
  bench "http://127.0.0.1:${OMLX_PORT}/v1" omlx "Jundot--Qwen3.6-27B-oQ4-mtp" "${OMLX_API_KEY}"
  stop omlx
}

usage() {
  echo "Usage: $(basename "$0") <test...>" >&2
  echo "  test: mtplx | mlx_lm | llama.cpp | omlx | all" >&2
  exit 1
}

echo "Benchmark for Qwen3.6-27B on different inference providers"

[[ $# -eq 0 ]] && usage

for arg in "$@"; do
  case "$arg" in
    mtplx)     bench_mtplx ;;
    mlx_lm)    bench_mlx_lm ;;
    llama.cpp) bench_llama_cpp ;;
    omlx)      bench_omlx ;;
    all)
      bench_mtplx
      bench_mlx_lm
      bench_llama_cpp
      bench_omlx
      ;;
    help|-h|--help)
      usage
      ;;
    *)
      echo "Unknown test: '$arg'" >&2
      usage
      ;;
  esac
done
