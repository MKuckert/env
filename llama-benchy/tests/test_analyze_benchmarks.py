from __future__ import annotations

import importlib.util
import io
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path

import pandas as pd

MODULE_PATH = Path(__file__).resolve().parents[1] / "analyze_benchmarks.py"
MODULE_NAME = "analyze_benchmarks"
SPEC = importlib.util.spec_from_file_location(MODULE_NAME, MODULE_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"Unable to load module from {MODULE_PATH}")
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules[MODULE_NAME] = MODULE
SPEC.loader.exec_module(MODULE)

REQUIRED_COLUMNS = list(MODULE.REQUIRED_TPS_COLUMNS)


class AnalyzeBenchmarksTests(unittest.TestCase):
    def write_csv(self, directory: Path, filename: str, header: list[str], rows: list[list[str]]) -> Path:
        csv_path = directory / filename
        lines = [",".join(header)]
        lines.extend(",".join("" if value is None else str(value) for value in row) for row in rows)
        csv_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
        return csv_path

    def test_normalize_csv_file_accepts_extra_columns_and_coerces_missing_numeric_values(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            root = Path(tmp_dir)
            csv_path = self.write_csv(
                root,
                "2026-05-28-13-49-mlx-lm.csv",
                REQUIRED_COLUMNS + ["ttfr_mean"],
                [[
                    "mlx-community/Qwen3.6-27B-4bit",
                    "tg32",
                    "67.9",
                    "1.6",
                    "67.9",
                    "1.6",
                    "",
                    "",
                    "",
                    "",
                    "123.4",
                ]],
            )

            normalized, issue = MODULE.normalize_csv_file(csv_path, root)

            self.assertIsNone(issue)
            self.assertIsNotNone(normalized)
            assert normalized is not None
            self.assertEqual(list(normalized.columns), list(MODULE.NORMALIZED_COLUMNS))
            self.assertEqual(normalized.loc[0, "source_root"], str(root))
            self.assertEqual(normalized.loc[0, "source_path"], csv_path.name)
            self.assertEqual(normalized.loc[0, "source_file"], csv_path.name)
            self.assertEqual(normalized.loc[0, "engine"], "mlx-lm")
            self.assertEqual(normalized.loc[0, "model"], "mlx-community/Qwen3.6-27B-4bit")
            self.assertEqual(normalized.loc[0, "test_name"], "tg32")
            self.assertEqual(normalized.loc[0, "source_row"], 2)
            self.assertTrue(pd.isna(normalized.loc[0, "peak_ts_mean"]))
            self.assertEqual(normalized.loc[0, "t_s_mean"], 67.9)

    def test_normalize_csv_file_reports_missing_required_columns(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            root = Path(tmp_dir)
            header = REQUIRED_COLUMNS[:-1]
            csv_path = self.write_csv(
                root,
                "2026-05-28-13-37-mtplx.csv",
                header,
                [["model-a", "pp2048", "1", "2", "3", "4", "5", "6", "7"]],
            )

            normalized, issue = MODULE.normalize_csv_file(csv_path, root)

            self.assertIsNone(normalized)
            self.assertIsNotNone(issue)
            assert issue is not None
            self.assertIn("missing required TPS columns", issue.message)
            self.assertIn("peak_ts_req_std", issue.message)

    def test_normalize_csv_file_reports_unreadable_csv(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            root = Path(tmp_dir)
            csv_path = root / "2026-05-28-13-37-broken.csv"
            csv_path.write_text(
                'model,test_name,t_s_mean,t_s_std,t_s_req_mean,t_s_req_std,peak_ts_mean,peak_ts_std,peak_ts_req_mean,peak_ts_req_std\n"broken,tg32,1,2,3,4,5,6,7,8\n',
                encoding="utf-8",
            )

            normalized, issue = MODULE.normalize_csv_file(csv_path, root)

            self.assertIsNone(normalized)
            self.assertIsNotNone(issue)
            assert issue is not None
            self.assertIn("unable to read CSV", issue.message)

    def test_main_returns_non_zero_when_any_csv_is_invalid(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            root = Path(tmp_dir)
            self.write_csv(
                root,
                "2026-05-28-13-37-mtplx.csv",
                REQUIRED_COLUMNS,
                [["model-a", "pp2048", "1", "2", "3", "4", "5", "6", "7", "8"]],
            )
            self.write_csv(
                root,
                "2026-05-28-13-38-invalid.csv",
                REQUIRED_COLUMNS[:-1],
                [["model-b", "tg32", "1", "2", "3", "4", "5", "6", "7"]],
            )

            stdout_buffer = io.StringIO()
            stderr_buffer = io.StringIO()
            with redirect_stdout(stdout_buffer), redirect_stderr(stderr_buffer):
                exit_code = MODULE.main([str(root)])

            self.assertEqual(exit_code, 1)
            self.assertIn("missing required TPS columns", stderr_buffer.getvalue())
            self.assertIn("normalized_rows: 1", stdout_buffer.getvalue())


if __name__ == "__main__":
    unittest.main()
