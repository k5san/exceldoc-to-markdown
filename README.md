# exceldoc_to_markdown

Excelで書かれているドキュメント（表計算ソフトではなくドキュメント生成アプリとしてExcelを使っているタイプのファイル）を、シート毎にMarkdownにしつつ、中に入っている画像ファイルも取り出すツールです。  
Windows環境想定。

# 前提
Pythonの実行環境とuvのインストールが必要となります。

uvのインストール
```
pip install uv
```

# 構成

```
uv_workspace/
├─ pyproject.toml                   ← ワークスペース定義
├─ sync_all.ps1                     ← ワークスペース内の全てのプロジェクトに関して依存関係を更新する。
├─ rebuild_all.ps1                  ← ワークスペース内の全てのプロジェクトに関してpyinstallerによるビルドを行う。
├─ build_project_windows.ps1        ← 単一のプロジェクトに対してpyinstallerによるビルドを行う(Windows向け)
├─ build_project_linux.ps1          ← 単一のプロジェクトに対してpyinstallerによるビルドを行う(Linux向け)
└─ projects/
    ├─ app1/
    |   ├─ pyproject.toml           ← プロジェクト定義
    |   ├─ build_windows.ps1        ← ../../build_project_windows.ps1を呼び出してプロジェクト単位のビルドを行う。
    |   ├─ build_linux.ps1          ← ../../build_project_linux.ps1  を呼び出してプロジェクト単位のビルドを行う。
    |   ├─ Dockerfile               ← Linux向けビルド時に使用されるDocker設定ファイル。
    |   ├─ build.spec               ← ビルド時の設定ファイル。
    |   └─ src/
    |       └─ app1/
    |           ├─ __init__.py
    |           ├─ __main__.py      ← python -m app1 の入口 cliのmain()を呼び出す。
    |           ├─ cli.py           ← 引数処理・ロガー初期化。
    |           └─ app1.py          ← app1の実処理（ユースケース）
    ├─ app2/
    |   ├─ pyproject.toml
    |   ├─ build.ps1
    |   ├─ build.spec
    |   └─ src/...
    └─ lib1/
        ├─ pyproject.toml
        └─ src/
            └─ lib1/
                ├─ __init__.py
                └─ common.py        ← 共通処理など。
```

`uv venv`を行うことで各プロジェクト内に仮想環境を構築してその中で依存関係は完結させる。  

# 開発開始方法

```
cd ./<開発対象のプロジェクトフォルダ>
uv --native-tls venv 
.\.venv\Scripts\Activate.ps1
uv --native-tls sync --active
```

全プロジェクトに関してsyncしたい場合は

## 依存関係を追加する場合

activateした状態で次のコマンドを使って追加する。 

```
uv --native-tls --active add <パッケージ名>
```

## デバッグする場合

`launch.json`に次のように記述する。  

```
{
  "configurations": [
    {
      "name": "現在のモジュール (__main__)",
      "type": "debugpy",
      "request": "launch",
      "module": "${fileDirnameBasename}",
      "python": "${workspaceFolder}/projects/${fileDirnameBasename}/.venv/Scripts/python.exe",
      "console": "integratedTerminal",
      "env": { "PYTHONPATH": "${workspaceFolder}/projects/${fileDirnameBasename}/src" },
      "args": [
        "--configFilePath",
        "${workspaceFolder}/projects/${fileDirnameBasename}/src/other/${fileDirnameBasename}.yaml"
      ],
      "justMyCode": true
    }
  ]
}
```

`${fileDirnameBasename}`は、デバッグを開始した時点でエディタで開いていたファイルの親フォルダ名となる。  
そのため、前述の構成であれば`app1.py`や同階層にある`cli.py`を開いた状態でデバッグを開始すれば、その時のエントリーはapp1の`__main__.py`にできる。  

`"python":`によって、使用するインタープリタを切り替える。

## ビルドに関して

build_windows.ps1を実行するとPyInstallerによってexe化されます。