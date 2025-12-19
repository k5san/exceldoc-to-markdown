import logging

from script_tool.config import Config

class ScriptTool:
    @staticmethod
    def main(config: Config) -> bool:
        logging.info(f"hello world! {config.sample}")
        return True
