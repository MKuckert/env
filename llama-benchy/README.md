# Benchmark local Qwen3.6-27B

## Quick Start

1. **Run Benchmarks**: Use Bash script to generate benchmark CSV files:
   ```bash
   bench-qwen3.6-27B-all.sh
   ```
2. **Analyze Results**: Run Python analysis script to process the generated CSV files, identify issues, and create a TPS comparison plot:
   ```bash
   python3 -m venv .venv
   source .venv/bin/activate
   python -m pip install -r requirements.txt
   python analyze_benchmarks.py $(pwd)/<your-export>/raw
   ```
