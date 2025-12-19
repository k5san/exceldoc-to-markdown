import logging
from datetime import datetime
from pathlib import Path
from typing import Callable, Optional, cast

from common_lib.base_config import BaseConfig
from common_lib.common import delete_old_files, list_files_by_pattern

LOGGING_FORMAT = "%(asctime)s - %(levelname)s - %(message)s"


class CommonLogger:
    log_directory: Path = Path("./log")
    log_file_header: str = "log"
    log_keep_count: int = 1
    base_timestamp: Optional[datetime] = None

    def __init__(self, config: BaseConfig, log_file_header: str, base_timestamp: Optional[datetime] = None):
        self.log_directory = config.log_directory
        self.log_keep_count = config.log_keep_count
        self.log_file_header = log_file_header
        self.base_timestamp = base_timestamp or datetime.now()

    def get_base_timestamp_str(self) -> str:
        timestamp = self.base_timestamp or datetime.now()
        return timestamp.strftime("%Y%m%d%H%M%S")

    def get_log_file_name_without_extension(self) -> str:
        return f"{self.log_file_header}_{self.get_base_timestamp_str()}"

    def get_log_file_name(self) -> str:
        return f"{self.get_log_file_name_without_extension()}.log"

    def get_log_file_path(self) -> Path:
        return self.log_directory.joinpath(self.get_log_file_name())

    def setup(self, callback_method: Optional[Callable[[str], None]] = None) -> None:
        if not self.log_directory.exists():
            self.log_directory.mkdir(parents=True, exist_ok=True)
        log_file_path = self.get_log_file_path()

        old_files = list_files_by_pattern(str(self.log_directory), f"{self.log_file_header}_*.log")
        delete_old_files(old_files, self.log_keep_count)

        logger = logging.getLogger()
        logger.setLevel(logging.INFO)
        logger.handlers.clear()

        file_handler = logging.FileHandler(log_file_path, encoding="utf-8")
        file_formatter = logging.Formatter(LOGGING_FORMAT)
        file_handler.setFormatter(file_formatter)
        logger.addHandler(file_handler)

        console_handler = logging.StreamHandler()
        console_handler.setFormatter(file_formatter)
        logger.addHandler(console_handler)

        if callback_method is not None:
            callback = cast(Callable[[str], None], callback_method)

            class CallbackHandler(logging.Handler):
                def emit(self, record: logging.LogRecord) -> None:
                    log_entry = self.format(record)
                    try:
                        callback(log_entry)
                    except Exception as error:
                        print(f"コールバック関数でエラーが発生しました: {error}")

            callback_handler = CallbackHandler()
            callback_handler.setFormatter(file_formatter)
            logger.addHandler(callback_handler)


def setup_console_logger() -> None:
    """
    設定読み込み前など、簡易的にコンソールだけへログを出すためのロガー設定。
    CommonLogger.setup() を呼ぶと上書きされる想定。
    """
    logger = logging.getLogger()
    logger.setLevel(logging.INFO)
    logger.handlers.clear()

    formatter = logging.Formatter(LOGGING_FORMAT)

    console_handler = logging.StreamHandler()
    console_handler.setFormatter(formatter)
    logger.addHandler(console_handler)
