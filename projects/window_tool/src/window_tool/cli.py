import tkinter as tk

from window_tool.window_tool import WindowTool


def main() -> None:
    root = tk.Tk()
    WindowTool(root)
    root.mainloop()


if __name__ == "__main__":
    main()
