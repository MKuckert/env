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

	local FORMAT=json

	local fmodel=$(echo "$model" | tr '/' '-')
	local RESULTS_FILE="$RESULTS_DIR/$(gdate +%Y-%m-%d-%H-%M)-$name-$fmodel.$FORMAT"

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
	#args+=(--depth 2048)
	args+=(--depth 0)

	# Enable prefix caching performance measurement. When enabled (and depth > 0),
	# it performs a two-step benchmark: first loading the context (reported as ctx_pp),
	# then running the prompt with the cached context.
	args+=(--enable-prefix-caching)

	# File to save results to and output format
	args+=(--save-result "$RESULTS_FILE")
	args+=(--format "$FORMAT")

	# Number of runs per test (Default: 3).
	args+=(--runs 3)

	uvx llama-benchy "${args[@]}" >&2

  echo -n "$name: "
	jq -r '.benchmarks[]
	  | select(.is_context_prefill_phase==false)
		| ( "pp \(.pp_throughput.mean|tostring), tg \(.tg_throughput.mean|tostring)" )' \
		"$RESULTS_FILE"
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

bench_omlx() {
  start omlx /Applications/oMLX.app/Contents/MacOS/omlx-cli serve
  bench "http://127.0.0.1:${OMLX_PORT}/v1" omlx $1 "${OMLX_API_KEY}"
  stop omlx
}

bench_splash() {
  start splash splash serve --model $1 --host 0.0.0.0 --max-context 150K --no-webui
  bench "http://127.0.0.1:${SPLASH_PORT}/v1" splash $1 "${SPLASH_API_KEY}"
  stop splash
}

usage() {
  echo "Usage: $(basename "$0") <test...>" >&2
  echo "  test: all" >&2
  exit 1
}

[[ $# -eq 0 ]] && usage

for arg in "$@"; do
  case "$arg" in
    all)
      bench_splash incoai/Qwen3.8-27B-Splash
      bench_splash SiliconSpecies/Swift-Qwen3.8-27B-Splash
      bench_omlx qwen3.8-27B-oQ4e
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
