from dataclasses import dataclass
import logging


@dataclass
class UserCheck:
    nocheck: bool

    def ask(self, message: str) -> bool:
        if self.nocheck:
            return True

        while True:
            user_input = input(f"{message} [y/n]: ").strip().lower()
            if user_input in {"y", "yes", ""}:
                return True
            if user_input in {"n", "no"}:
                return False
            logging.error("無効な入力です。'y' または 'n' を入力してください。")

    def careful_ask(self, message: str, passcode: str = "ENTRY") -> bool:
        """
        危険な操作などで二重確認が必要な場合に使用。
        passcode に正しい文字列を入力しないと実行されない。
        """
        if self.nocheck:
            return False

        if not self.ask(message):
            return False

        user_input = input(f"続行するには「{passcode}」と入力してください: ").strip()
        if user_input == passcode:
            return True
        logging.warning("入力されたパスコードが一致しません。操作を中断します。")
        return False

    def wait(self, message: str) -> None:
        if self.nocheck:
            return
        input(f"{message}")
