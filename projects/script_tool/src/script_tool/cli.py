
from datetime import datetime
import sys

from script_tool.config import Config
from common_lib.common_log import CommonLogger, setup_console_logger
from common_lib.pyproject_utils import PyprojectUtils
from script_tool.script_tool import ScriptTool


def main() -> None:
    setup_console_logger()
    app_name: str = "script_tool"
    PyprojectUtils.print_version(app_name)
    config: Config = Config.from_args(default_config_file_path=f"{app_name}.yaml")
    logger = CommonLogger(config=config, log_file_header=app_name, base_timestamp=datetime.now())
    logger.setup()

    if ScriptTool.main(config):
        sys.exit(0)
    sys.exit(1)

if __name__ == "__main__":
    main()
