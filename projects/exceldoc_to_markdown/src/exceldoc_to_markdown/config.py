import argparse
from dataclasses import dataclass
from pathlib import Path

from common_lib.base_config import BaseConfig


@dataclass
class Config(BaseConfig):
    excel_path: Path | None = None
    output_dir: Path = Path("output_md")

    @staticmethod
    def create_arg_parser() -> argparse.ArgumentParser:
        parser = argparse.ArgumentParser(description="ExcelをMarkdownに変換します。")
        parser.add_argument(
            "--excelPath",
            "--excel-path",
            dest="excel_path",
            type=Path,
            help="入力Excelファイルのパス",
        )
        parser.add_argument(
            "--outputDir",
            "--output-dir",
            dest="output_dir",
            type=Path,
            help="Markdownの出力ディレクトリ",
        )
        return parser

    def required_check(self) -> None:
        if self.excel_path is None:
            entered = input("Excelファイルのパスを入力してください: ").strip()
            if entered:
                self.excel_path = Path(entered)
        self.none_check(self.excel_path, "excelPath")
