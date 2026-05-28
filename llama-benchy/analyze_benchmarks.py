#!/usr/bin/env python3
from __future__ import annotations

import argparse
import sys
from pathlib import Path


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Recursively discover benchmark CSV files below one or more root directories."
        )
    )
    parser.add_argument(
        "roots",
        metavar="ROOT",
        nargs="+",
        help="one or more root directories to scan recursively for *.csv files",
    )
    return parser.parse_args(argv)


def discover_csv_files(root: Path) -> list[Path]:
    return sorted(path for path in root.rglob("*.csv") if path.is_file())


def validate_root(root_arg: str) -> Path:
    root = Path(root_arg).expanduser().resolve()
    if not root.exists():
        raise FileNotFoundError(f"Root directory does not exist: {root}")
    if not root.is_dir():
        raise NotADirectoryError(f"Root path is not a directory: {root}")
    return root


def format_path(path: Path, root: Path) -> str:
    try:
        return str(path.relative_to(root))
    except ValueError:
        return str(path)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)

    try:
        roots = [validate_root(root_arg) for root_arg in args.roots]
    except (FileNotFoundError, NotADirectoryError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2

    total_csv_files = 0

    for root in roots:
        csv_files = discover_csv_files(root)
        total_csv_files += len(csv_files)

        print(f"root: {root}")
        print(f"csv_files_found: {len(csv_files)}")

        for csv_file in csv_files:
            print(f"  - {format_path(csv_file, root)}")

    print(f"total_csv_files_found: {total_csv_files}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
