from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass
from pathlib import Path

import pandas as pd

REQUIRED_TPS_COLUMNS: tuple[str, ...] = (
    "model",
    "test_name",
    "t_s_mean",
    "t_s_std",
    "t_s_req_mean",
    "t_s_req_std",
    "peak_ts_mean",
    "peak_ts_std",
    "peak_ts_req_mean",
    "peak_ts_req_std",
)
NUMERIC_TPS_COLUMNS: tuple[str, ...] = REQUIRED_TPS_COLUMNS[2:]
NORMALIZED_COLUMNS: tuple[str, ...] = (
    "source_root",
    "source_path",
    "source_file",
    "engine",
    "source_row",
    *REQUIRED_TPS_COLUMNS,
)
TIMESTAMPED_FILENAME_RE = re.compile(
    r"^\d{4}-\d{2}-\d{2}-\d{2}-\d{2}-(?P<remainder>.+)$"
)
KNOWN_ENGINE_PREFIXES: tuple[str, ...] = (
    "llama.cpp",
    "mlx-lm",
    "mlx_lm",
    "mtplx",
    "omlx",
)


@dataclass(frozen=True)
class CsvIssue:
    path: Path
    message: str


@dataclass(frozen=True)
class RootScan:
    root: Path
    csv_files: list[Path]


@dataclass
class AnalysisResult:
    roots: list[RootScan]
    normalized_rows: pd.DataFrame
    errors: list[CsvIssue]

    @property
    def total_csv_files(self) -> int:
        return sum(len(root_scan.csv_files) for root_scan in self.roots)

    @property
    def invalid_csv_files(self) -> int:
        return len(self.errors)

    @property
    def valid_csv_files(self) -> int:
        return self.total_csv_files - self.invalid_csv_files


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Recursively discover benchmark CSV files below one or more root "
            "directories and normalize TPS-relevant benchmark rows."
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


def empty_normalized_frame() -> pd.DataFrame:
    return pd.DataFrame(columns=list(NORMALIZED_COLUMNS))


def extract_engine_from_filename(path: Path) -> str:
    stem = path.stem
    match = TIMESTAMPED_FILENAME_RE.match(stem)
    remainder = match.group("remainder") if match else stem

    for engine in KNOWN_ENGINE_PREFIXES:
        if remainder == engine or remainder.startswith(f"{engine}-"):
            return engine.replace("_", "-")

    return remainder


def read_csv_file(csv_path: Path) -> pd.DataFrame:
    return pd.read_csv(csv_path)


def normalize_csv_file(
    csv_path: Path, root: Path
) -> tuple[pd.DataFrame | None, CsvIssue | None]:
    try:
        raw_frame = read_csv_file(csv_path)
    except (
        OSError,
        UnicodeDecodeError,
        pd.errors.EmptyDataError,
        pd.errors.ParserError,
    ) as exc:
        return None, CsvIssue(csv_path, f"unable to read CSV: {exc}")

    missing_columns = [
        column for column in REQUIRED_TPS_COLUMNS if column not in raw_frame.columns
    ]
    if missing_columns:
        missing_columns_text = ", ".join(missing_columns)
        return None, CsvIssue(
            csv_path,
            f"missing required TPS columns: {missing_columns_text}",
        )

    normalized = raw_frame.loc[:, REQUIRED_TPS_COLUMNS].copy()
    normalized.insert(0, "source_row", range(2, len(normalized) + 2))
    normalized.insert(0, "engine", extract_engine_from_filename(csv_path))
    normalized.insert(0, "source_file", csv_path.name)
    normalized.insert(0, "source_path", format_path(csv_path, root))
    normalized.insert(0, "source_root", str(root))

    normalized["model"] = normalized["model"].astype("string")
    normalized["test_name"] = normalized["test_name"].astype("string")

    for column in NUMERIC_TPS_COLUMNS:
        normalized[column] = pd.to_numeric(normalized[column], errors="coerce")

    return normalized.loc[:, NORMALIZED_COLUMNS], None


def analyze_roots(roots: list[Path]) -> AnalysisResult:
    root_scans: list[RootScan] = []
    normalized_frames: list[pd.DataFrame] = []
    errors: list[CsvIssue] = []

    for root in roots:
        csv_files = discover_csv_files(root)
        root_scans.append(RootScan(root=root, csv_files=csv_files))

        for csv_file in csv_files:
            normalized, issue = normalize_csv_file(csv_file, root)
            if issue is not None:
                errors.append(issue)
                continue
            if normalized is not None and not normalized.empty:
                normalized_frames.append(normalized)

    normalized_rows = (
        pd.concat(normalized_frames, ignore_index=True)
        if normalized_frames
        else empty_normalized_frame()
    )
    return AnalysisResult(
        roots=root_scans,
        normalized_rows=normalized_rows,
        errors=errors,
    )


def print_report(result: AnalysisResult) -> None:
    for root_scan in result.roots:
        print(f"root: {root_scan.root}")
        print(f"csv_files_found: {len(root_scan.csv_files)}")
        for csv_file in root_scan.csv_files:
            print(f"  - {format_path(csv_file, root_scan.root)}")

    for issue in result.errors:
        print(f"error: {issue.path}: {issue.message}", file=sys.stderr)

    print(f"total_csv_files_found: {result.total_csv_files}")
    print(f"valid_csv_files: {result.valid_csv_files}")
    print(f"invalid_csv_files: {result.invalid_csv_files}")
    print(f"normalized_rows: {len(result.normalized_rows)}")


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)

    try:
        roots = [validate_root(root_arg) for root_arg in args.roots]
    except (FileNotFoundError, NotADirectoryError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2

    result = analyze_roots(roots)
    print_report(result)
    return 1 if result.errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
