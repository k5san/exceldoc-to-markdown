from __future__ import annotations

import os
import sys
from pathlib import Path

# PyInstaller onefile 展開時に Tk が init.tcl を見つけられない場合がある。
# uv 配布の Python では lib/tcl8.6 ではなく tcl/tcl8.6 配下にあるため、
# runtime hook で _MEIPASS か base_prefix 直下の tcl を環境変数に流し込む。
# exe 実行時のみ使う前提のため、最小限の処理に留める。


def setEnvIfDir(envName: str, targetDir: Path) -> None:
    if targetDir.is_dir():
        os.environ[envName] = str(targetDir)


def resolveTclRoot() -> Path:
    baseDir = getattr(sys, "_MEIPASS", None)
    if baseDir:
        return Path(baseDir) / "tcl"
    return Path(sys.base_prefix) / "tcl"


tclRoot = resolveTclRoot()
setEnvIfDir("TCL_LIBRARY", tclRoot / "tcl8.6")
setEnvIfDir("TK_LIBRARY", tclRoot / "tk8.6")
