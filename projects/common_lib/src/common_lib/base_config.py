import argparse
import logging
import re
import sys
from dataclasses import MISSING, asdict, dataclass, fields, is_dataclass
from datetime import datetime
from enum import Enum
from pathlib import Path
from typing import Any, ClassVar, Dict, List, Mapping, Optional, Type, TypeVar, Union, cast, get_args, get_origin, get_type_hints

import yaml

from common_lib.user_check import UserCheck
from common_lib.common import str_to_bool


class _YamlDumpError(RuntimeError):
    pass


T = TypeVar("T", bound="BaseConfig")


def _coerce_by_type(value: Any, anno: Any) -> Any:
    """型ヒント anno に従って value を変換する。必要ない場合はそのまま返す。"""
    if value is None:
        return None

    origin = get_origin(anno)
    args = get_args(anno)

    # Optional[T] / Union[..., None]
    if origin is Union and type(None) in args:
        inner = next(a for a in args if a is not type(None))
        return _coerce_by_type(value, inner)

    # dataclass のネスト
    if is_dataclass(anno) and isinstance(value, dict):
        return value

    # pathlib.Path
    if anno is Path:
        return value if isinstance(value, Path) else Path(str(value))

    # bool
    if anno is bool:
        if isinstance(value, bool):
            return value
        if isinstance(value, str):
            v = value.lower()
            if v in ("yes", "true", "t", "1", "on"):
                return True
            if v in ("no", "false", "f", "0", "off"):
                return False
            raise argparse.ArgumentTypeError(f"真偽値として解釈できません: {value}")
        raise argparse.ArgumentTypeError(f"真偽値として解釈できません: {value!r}")

    # 数値系
    if anno in (int, float, str):
        try:
            return anno(value)
        except Exception as e:
            raise argparse.ArgumentTypeError(f"{anno.__name__} に変換できません: {value!r} - {e}")

    # Enum
    if isinstance(anno, type) and issubclass(anno, Enum):
        if isinstance(value, anno):
            return value
        try:
            return anno[value]  # type: ignore[index]
        except Exception:
            pass
        try:
            return anno(value)
        except Exception:
            pass
        if hasattr(anno, "fromInt"):
            try:
                return anno.fromInt(value)  # type: ignore[attr-defined]
            except Exception as e:
                raise argparse.ArgumentTypeError(f"Enum {anno.__name__} へ変換できません: {value!r} - {e}")
        raise argparse.ArgumentTypeError(f"Enum {anno.__name__} へ変換できません: {value!r}")

    # List[T]
    if origin is list and len(args) == 1:
        inner = args[0]
        if not isinstance(value, list):
            raise argparse.ArgumentTypeError(f"list が必要ですが: {value!r}")
        return [_coerce_by_type(v, inner) for v in value]

    # Dict[K, V]
    if origin is dict and len(args) == 2:
        kt, vt = args
        if not isinstance(value, dict):
            raise argparse.ArgumentTypeError(f"dict が必要ですが: {value!r}")
        return {_coerce_by_type(k, kt): _coerce_by_type(v, vt) for k, v in value.items()}

    return value


def _to_snake_case(name: str) -> str:
    snake = re.sub(r"(?<!^)(?=[A-Z])", "_", name).replace("-", "_")
    return snake.lower()


def _normalize_keys(data: Mapping[str, Any]) -> Dict[str, Any]:
    """キーを snake_case に正規化する（camelCase や kebab-case を許容）。"""
    normalized: Dict[str, Any] = {}
    for key, value in data.items():
        new_key = _to_snake_case(key) if isinstance(key, str) else key
        if isinstance(value, Mapping):
            normalized[new_key] = _normalize_keys(value)
        elif isinstance(value, list):
            normalized[new_key] = [
                _normalize_keys(v) if isinstance(v, Mapping) else v for v in value
            ]
        else:
            normalized[new_key] = value
    return normalized


def _to_primitive(obj: Any) -> Any:
    """YAMLに書けるプリミティブへ再帰変換（dataclass/Path/Mapping/List対応）"""
    if is_dataclass(obj):
        result: Dict[str, Any] = {}
        for f in fields(obj):
            key = f.name
            if key.startswith("_"):
                continue
            value = getattr(obj, key)
            if value is None:
                continue
            result[key] = _to_primitive(value)
        return result

    if isinstance(obj, Path):
        return str(obj)

    if isinstance(obj, Mapping):
        return {
            str(k): _to_primitive(v)
            for k, v in obj.items()
            if not (isinstance(k, str) and k.startswith("_"))
        }

    if isinstance(obj, (list, tuple)):
        return [_to_primitive(v) for v in obj]

    if isinstance(obj, Enum):
        val = obj.value
        if isinstance(val, (int, float, bool)):
            return val
        return val

    return obj


def _ensure_parent_dir(path: Path) -> None:
    """親ディレクトリを作成（存在しなくてもOK）"""
    parent = path.parent
    if not parent.exists():
        parent.mkdir(parents=True, exist_ok=True)


@dataclass
class BaseConfig:
    """
    設定読込の共通基底クラス。
    """

    config_file_path: Path = Path("./config.yaml")
    no_check: bool = False
    log_directory: Path = Path("./log")
    log_keep_count: int = 1

    error_detected: ClassVar[bool] = False

    @classmethod
    def set_error(cls) -> None:
        cls.error_detected = True

    @classmethod
    def is_error(cls) -> bool:
        return cls.error_detected

    @classmethod
    def create_arg_parser(cls) -> argparse.ArgumentParser:
        raise NotImplementedError("create_arg_parser をサブクラスで実装してください。")

    def required_check(self) -> None:
        pass

    @classmethod
    def from_args(cls: Type[T], default_config_file_path: Path | str) -> T:
        """
        --configFilePath の YAML を読み込み、CLI（ドット区切り）で上書きして、ネストdataclassを安全生成します。
        """
        parser = cls.create_arg_parser()

        parser.add_argument(
            "--configFilePath",
            "--config-file-path",
            dest="config_file_path",
            type=Path,
            default=default_config_file_path,
            help="設定yamlファイルのパス。以降パラメータは全てyamlファイル内にも定義できます。但し実行時パラメータが優先されます。",
        )
        parser.add_argument(
            "--noCheck",
            "--no-check",
            dest="no_check",
            type=str_to_bool,
            help="1を渡すことでユーザー確認しない",
        )
        parser.add_argument(
            "--logDirectory",
            "--log-directory",
            dest="log_directory",
            type=Path,
            help="ログの出力先",
        )
        parser.add_argument(
            "--logFileHeader",
            "--log-file-header",
            dest="log_file_header",
            type=str,
            help="ログファイル名のヘッダー",
        )
        parser.add_argument(
            "--logKeepCount",
            "--log-keep-count",
            dest="log_keep_count",
            type=int,
            help="ログの保持数",
        )

        args = vars(parser.parse_args())

        file_config: Dict[str, Any] = {}
        config_file_arg = args.get("config_file_path")
        cls.config_file_path = Path(config_file_arg) if config_file_arg is not None else Path(default_config_file_path)

        if cls.config_file_path:
            try:
                path = Path(cls.config_file_path)
                if not path.exists():
                    pass
                elif yaml is None:
                    logging.error("PyYAML が見つかりません。pip install pyyaml を実行してください。")
                else:
                    file_config = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
                    logging.info("YAML設定を読み込みました: %s", cls.config_file_path)
            except Exception as e:
                logging.error("設定ファイル読み込み失敗: %s - %s", cls.config_file_path, str(e))

        cli_dict: Dict[str, Any] = {}
        for key, value in args.items():
            if key == "config_file_path":
                continue
            if value is not None:
                cls.set_nested_dict(cli_dict, key.split("."), value)

        merged = cls.deep_merge_dicts(file_config or {}, cli_dict)
        normalized = _normalize_keys(merged)

        try:
            obj = cast(T, cls._build_dataclass(cls, normalized))

            obj.required_check()
            obj.config_file_path = Path(cls.config_file_path)
            if obj.is_error():
                UserCheck(nocheck=cls.no_check).wait("")
                raise RuntimeError("必須入力チェックでエラーを検知しました。")

            return obj
        except Exception as e:
            logging.error("Config生成失敗: %s", str(e))
            raise

    @classmethod
    def none_check(cls, value: Any, value_name: str) -> None:
        if not value:
            cls.set_error()
            logging.error(f"{value_name}は必須入力です。")

    @staticmethod
    def set_nested_dict(data: Dict[str, Any], keys: List[str], value: Any) -> None:
        """ネスト辞書に値をセット（中間が無ければ辞書を生成）"""
        current = data
        for key in keys[:-1]:
            if not key:
                continue
            if key not in current or not isinstance(current[key], dict):
                current[key] = {}
            current = current[key]
        if keys[-1]:
            current[keys[-1]] = value

    @staticmethod
    def deep_merge_dicts(base: Dict[str, Any], override: Dict[str, Any]) -> Dict[str, Any]:
        """辞書の再帰マージ（override が優先）"""
        result = base.copy()
        for key, value in override.items():
            if key in result and isinstance(result[key], dict) and isinstance(value, dict):
                result[key] = BaseConfig.deep_merge_dicts(result[key], value)
            else:
                result[key] = value
        return result

    @classmethod
    def _build_dataclass(cls: Type["BaseConfig"], dc_type: Type[Any], data: Dict[str, Any]) -> Any:
        """ネストdataclassを辞書から再帰的に構築（List/Dict/Optional 内の dataclass も対応）。"""

        if not is_dataclass(dc_type):
            raise TypeError("サブクラスは dataclass である必要があります。")

        kwargs: Dict[str, Any] = {}
        data = data or {}

        try:
            mod_globals = sys.modules[dc_type.__module__].__dict__
            type_hints = get_type_hints(dc_type, globalns=mod_globals, localns=mod_globals)
        except Exception:
            type_hints = {}

        for field in fields(dc_type):
            name = field.name
            anno = type_hints.get(name, field.type)

            if name not in data:
                if field.default is not MISSING:
                    kwargs[name] = field.default
                elif field.default_factory is not MISSING:  # type: ignore[attr-defined]
                    kwargs[name] = field.default_factory()  # type: ignore[misc]
                continue

            raw = data[name]
            if raw is None:
                kwargs[name] = None
                continue

            origin = get_origin(anno)
            args = get_args(anno)

            def build_dc(target_dc: Type[Any], src: Dict[str, Any]) -> Any:
                return cls._build_dataclass(target_dc, src)

            def resolve_annotation(dc_cls: Type[Any], field_name: str) -> Type[Any] | None:
                hints = get_type_hints(dc_cls)
                return hints.get(field_name)

            if origin is Union and type(None) in args:
                non_none = next(a for a in args if a is not type(None))
                if is_dataclass(non_none) and isinstance(raw, dict):
                    kwargs[name] = build_dc(cast(Type[Any], non_none), raw)
                else:
                    kwargs[name] = _coerce_by_type(raw, non_none)
                continue

            if origin is list and len(args) == 1:
                inner = args[0]
                if not isinstance(raw, list):
                    raise argparse.ArgumentTypeError(f"list が必要ですが: {raw!r}")
                if is_dataclass(inner):
                    kwargs[name] = [build_dc(cast(Type[Any], inner), x) if isinstance(x, dict) else x for x in raw]
                else:
                    kwargs[name] = [_coerce_by_type(x, inner) for x in raw]
                continue

            if origin is dict and len(args) == 2:
                key_type, value_type = args
                if not isinstance(raw, dict):
                    raise argparse.ArgumentTypeError(f"dict が必要ですが: {raw!r}")
                if is_dataclass(value_type):
                    kwargs[name] = {
                        _coerce_by_type(k, key_type): build_dc(cast(Type[Any], value_type), v) if isinstance(v, dict) else v
                        for k, v in raw.items()
                    }
                else:
                    kwargs[name] = {_coerce_by_type(k, key_type): _coerce_by_type(v, value_type) for k, v in raw.items()}
                continue

            anno_resolved = resolve_annotation(dc_type, name)

            if anno_resolved and is_dataclass(anno_resolved) and isinstance(raw, dict):
                kwargs[name] = build_dc(anno_resolved, raw)
                continue

            kwargs[name] = _coerce_by_type(raw, anno)

        return dc_type(**kwargs)

    def to_dict(self) -> Dict[str, Any]:
        """
        自分自身（ネスト含む）を YAML 向けのプリミティブ辞書へ変換する。
        - None値は省略
        - Path は文字列へ
        """
        data = _to_primitive(self)
        data.pop("error_detected", None)
        return data

    def save_to_yaml(self, path: Optional[Path] = None) -> Path:
        if yaml is None:
            raise _YamlDumpError("PyYAML が見つかりません。pip install pyyaml を実行してください。")

        target = path or getattr(self, "config_file_path", None)
        if not isinstance(target, Path):
            raise _YamlDumpError("保存先パスを指定してください（save_to_yaml(path=...) か config_file_path を設定）。")

        _ensure_parent_dir(target)

        def _to_primitive_nested(obj: Any) -> Any:
            if is_dataclass(obj) and not isinstance(obj, type):
                return _to_primitive_nested(asdict(obj))
            if isinstance(obj, dict):
                return {
                    str(_to_primitive_nested(k)): _to_primitive_nested(v)
                    for k, v in obj.items()
                    if not (isinstance(k, str) and k.startswith("_"))
                }
            if isinstance(obj, (list, tuple, set)):
                return [_to_primitive_nested(x) for x in obj]
            if isinstance(obj, Enum):
                val = obj.value
                if isinstance(val, (int, float, bool)):
                    return val
                return val
            if isinstance(obj, Path):
                return str(obj)
            if isinstance(obj, datetime):
                return obj.isoformat()
            try:
                from zoneinfo import ZoneInfo

                if isinstance(obj, ZoneInfo):
                    return obj.key
            except Exception:
                pass
            return obj

        try:
            raw = self.to_dict()
            primitive = _to_primitive_nested(raw)

            text = yaml.safe_dump(
                primitive,
                sort_keys=False,
                allow_unicode=True,
                default_flow_style=False,
            )
            target.write_text(text, encoding="utf-8")
            logging.info("設定をYAMLとして保存しました: %s", str(target))
            return target
        except Exception as e:
            logging.error("設定のYAML保存に失敗しました: %s", str(e))
            raise _YamlDumpError(str(e))

    def input_default(self, label: str, default_value: str) -> str:
        if self.no_check:
            return default_value

        value = input(f"[INPUT] {label} default='{default_value}': ")

        if value:
            return value
        return default_value
