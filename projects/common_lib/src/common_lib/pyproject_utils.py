from importlib.metadata import PackageNotFoundError, version as pkg_version
from pathlib import Path
import sys
import tomllib
from typing import Optional


class PyprojectUtils:

    @staticmethod
    def resolve_pyproject_dir() -> Optional[Path]:
        candidates: list[Optional[Path]] = [
            Path(__file__).resolve().parent.parent.parent,
            Path(getattr(sys, "_MEIPASS", "")) if hasattr(sys, "_MEIPASS") else None,
        ]
        for candidate in candidates:
            if candidate is None:
                continue
            pyproject_path = candidate / "pyproject.toml"
            if pyproject_path.exists():
                return candidate
        return None

    @staticmethod
    def resolve_version_from_pyproject(pyproject_dir: Path) -> str:
        pyproject_path = pyproject_dir / "pyproject.toml"
        try:
            with pyproject_path.open("rb") as file:
                config = tomllib.load(file)
            project_section = config.get("project", {})
            if not isinstance(project_section, dict):
                return "unknown"
            version = project_section.get("version")
            if isinstance(version, str) and version.strip():
                return version.strip()
        except Exception:
            return "unknown"
        return "unknown"

    @staticmethod
    def resolve_app_version(distribution_name: str) -> str:
        try:
            return pkg_version(distribution_name)
        except PackageNotFoundError:
            pass
        pyproject_dir = PyprojectUtils.resolve_pyproject_dir()
        if pyproject_dir is not None:
            version = PyprojectUtils.resolve_version_from_pyproject(pyproject_dir)
            if version != "unknown":
                return version
        return "unknown"

    @staticmethod
    def print_version(distribution_name: str) -> str:
        app_version: str = PyprojectUtils.resolve_app_version(distribution_name)
        display_name: str = distribution_name.replace("-", "_")
        title = f"{display_name} Ver.{app_version}"
        print(title)
        return title
