
from datetime import datetime
import sys

from common_lib.common_log import CommonLogger, setup_console_logger
from common_lib.pyproject_utils import PyprojectUtils

from exceldoc_to_markdown.config import Config
from exceldoc_to_markdown.exceldoc_to_markdown import ExceldocToMarkdown


def main() -> None:
    setup_console_logger()
    app_name: str = "exceldoc_to_markdown"
    PyprojectUtils.print_version(app_name)
    config: Config = Config.from_args(default_config_file_path=f"{app_name}.yaml")
    logger = CommonLogger(config=config, log_file_header=app_name, base_timestamp=datetime.now())
    logger.setup()

    if ExceldocToMarkdown.main(config):
        sys.exit(0)
    sys.exit(1)

if __name__ == "__main__":
    main()
