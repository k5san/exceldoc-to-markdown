 

import tkinter as tk
from tkinter import ttk


class WindowTool:
    def __init__(self, root: tk.Tk) -> None:
        self._root: tk.Tk = root
        self._root.title("WindowTool")
        self._root.geometry("540x320")

        self._input_var: tk.StringVar = tk.StringVar()
        self._message_label: ttk.Label

        self._build_layout()

    def _build_layout(self) -> None:
        """ウィジェットを中央配置で構築する。"""
        container = ttk.Frame(self._root)
        container.place(relx=0.5, rely=0.5, anchor="center")

        entry = ttk.Entry(container, textvariable=self._input_var, width=40)
        entry.pack(pady=(0, 12))
        entry.focus()

        confirm_button = ttk.Button(
            container,
            text="Confirm",
            command=self.handle_confirm,
        )
        confirm_button.pack()

        self._message_label = ttk.Label(container, text="")
        self._message_label.pack(pady=(12, 0))

    def handle_confirm(self) -> None:
        """確認ボタン押下時にメッセージを表示する。"""
        message = self._input_var.get()
        self._message_label.config(text=message)

