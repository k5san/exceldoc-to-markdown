import argparse
import getpass
import logging
import os
import platform
import shutil
import subprocess
from datetime import datetime, timedelta
from glob import glob
from pathlib import Path
from typing import Any, List, Optional, Tuple, Union

import chardet

if platform.system() != "Windows":
    import pwd  # type: ignore[import-untyped]


def to_timestamp(dt: datetime) -> str:
    return dt.strftime("%Y%m%d%H%M%S")


def get_timestamp() -> str:
    return datetime.now().strftime("%Y%m%d%H%M%S")

def is_sub_path(child_path_str: str, base_path_str: str) -> bool:
    child_path = Path(child_path_str).resolve()
    base_path = Path(base_path_str).resolve()

    try:
        child_path.relative_to(base_path)
        return True
    except ValueError:
        return False


def to_posix_str(path: Union[str, Path]) -> str:
    """
    Path または str を POSIX 形式の文字列に正規化する。
    - Windows の '\' は '/' に変換
    - Path は str へ変換
    """
    path_str = str(path)
    return path_str.replace("\\", "/")


def list_files_by_pattern(directory: str, pattern: str) -> List[str]:
    """指定したディレクトリ内の指定した命名規則を持つファイルを取得し、更新日時の昇順で並べる"""
    file_paths = glob(os.path.join(directory, pattern))
    file_paths = [path for path in file_paths if os.path.isfile(path)]
    sorted_files = sorted(file_paths, key=lambda file_path: os.path.getmtime(file_path))
    return sorted_files


def delete_old_files(files: List[str], keep_count: int) -> None:
    """古いファイルを削除し、同名フォルダもあれば削除"""
    if len(files) <= keep_count:
        return

    files_to_delete = files[:-keep_count]
    for file_path in files_to_delete:
        try:
            os.remove(file_path)
            logging.info("ファイルを削除しました: %s", os.path.basename(file_path))
        except OSError as error:
            logging.error("ファイル削除エラー: %s - %s", os.path.basename(file_path), error)
            continue

        folder_path = os.path.splitext(file_path)[0]
        if os.path.isdir(folder_path):
            try:
                shutil.rmtree(folder_path)
                logging.info("同名フォルダを削除しました: %s", os.path.basename(folder_path))
            except OSError as error:
                logging.error("フォルダ削除エラー: %s - %s", os.path.basename(folder_path), error)


def list_folders_by_pattern(directory: str, pattern: str) -> List[str]:
    """指定したディレクトリ内の指定した命名規則を持つフォルダを取得し、更新日時の昇順で並べる"""
    folder_paths = glob(os.path.join(directory, pattern))
    folder_paths = [path for path in folder_paths if os.path.isdir(path)]

    def get_latest_mtime(folder_path: str) -> float:
        try:
            mtimes = [os.path.getmtime(folder_path)]
            for root, _, files in os.walk(folder_path):
                for file_name in files:
                    mtimes.append(os.path.getmtime(os.path.join(root, file_name)))
            return max(mtimes)
        except Exception as error:
            logging.warning("更新日時の取得に失敗しました: %s - %s", folder_path, error)
            return 0.0

    sorted_folders = sorted(folder_paths, key=get_latest_mtime)
    return sorted_folders


def delete_old_folders(folders: List[str], keep_count: int) -> None:
    """古いフォルダを削除する（keep_count件だけ残す）"""
    if len(folders) <= keep_count:
        return

    folders_to_delete = folders[:-keep_count]
    for folder_path in folders_to_delete:
        try:
            shutil.rmtree(folder_path)
            logging.info("フォルダを削除しました: %s", os.path.basename(folder_path))
        except OSError as error:
            logging.error("フォルダ削除エラー: %s - %s", os.path.basename(folder_path), error)


def str_to_bool(value: str) -> bool:
    """argparseのtype=bool問題の回避（明示的に文字列→boolへ）"""
    if isinstance(value, bool):
        return value
    normalized = value.lower()
    if normalized in ("yes", "true", "t", "1"):
        return True
    if normalized in ("no", "false", "f", "0"):
        return False
    raise argparse.ArgumentTypeError(f"真偽値として解釈できません: {value}")
