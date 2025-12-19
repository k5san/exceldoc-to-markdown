import argparse
from dataclasses import dataclass

from common_lib.base_config import BaseConfig


@dataclass
class Config(BaseConfig):
    sample: int = 1234

    @staticmethod
    def create_arg_parser() -> argparse.ArgumentParser:
        parser = argparse.ArgumentParser(description="スクリプトツール")
        parser.add_argument("--sample", type=int, help="サンプル引数")
        return parser
