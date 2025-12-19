# 応答方式
エージェントの応答は原則日本語とする。

# コーディング規約

## スタイル

PEP8には準拠する。
具体的には次の通り。
- 関数・変数 → snake_case
- クラス → UpperCamelCase
- 定数 → UPPER_CASE
- 内部メソッド、内部フィールドの先頭には「_」を付与し、外部から呼び出さないこと。
- インデント4スペース
- importは標準→外部→自作の順
- スペースと空行のルール
  - スペース
    - 演算子の前後にはスペース
    - カンマの後ろにはスペース
    - 関数名と括弧の間にはスペースを入れない。
  - 空行
    - トップレベルの関数・クラスは「前に2行」
    - クラス内のメソッド間は「前に1行」
- ワイルドカードimport禁止

## その他ルール
  - ロガーには`logging.error("...")`, `logging.info("...")` を使用すること。  
  - 必ず型ヒントを付与すること。
  - 型安全・null安全なコードを心掛けること。
  - クラスオブジェクトに対して、getAttを使ってフィールドの存在確認後にその値を参照する処理は実装しないこと。
    - メソッドから不完全な値が戻されることや、型ヒントで記述された型以外のインスタンスが返却されることは考慮しなくてよい。
    - 逆説的に、クラスオブジェクトは不完全な値で返却してはならないし、型ヒントで示した型以外のインスタンスを返却するメソッドを定義してはならない。

# READ and Write Rule (For AI Agent)
AIエージェントが WSL + PowerShell 混在環境で安全にファイル操作を行うための指針。
In each command, **define → use**. Do **not** escape `$`. Use generic `'path/to/file.ext'`.

## READ (UTF‑8 no BOM, line‑numbered)

```bash
bash -lc 'powershell -NoLogo -Command "
$OutputEncoding = [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false);
Set-Location -LiteralPath (Convert-Path .);
function Get-Lines { param([string]$Path,[int]$Skip=0,[int]$First=40)
  $enc=[Text.UTF8Encoding]::new($false)
  $text=[IO.File]::ReadAllText($Path,$enc)
  if($text.Length -gt 0 -and $text[0] -eq [char]0xFEFF){ $text=$text.Substring(1) }
  $ls=$text -split \"`r?`n\"
  for($i=$Skip; $i -lt [Math]::Min($Skip+$First,$ls.Length); $i++){ \"{0:D4}: {1}\" -f ($i+1), $ls[$i] }
}
Get-Lines -Path \"path/to/file.ext\" -First 120 -Skip 0
"'
```

---

## WRITE (UTF‑8 no BOM, atomic replace, backup)

```bash
bash -lc 'powershell -NoLogo -Command "
$OutputEncoding = [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false);
Set-Location -LiteralPath (Convert-Path .);
function Write-Utf8NoBom { param([string]$Path,[string]$Content)
  $dir = Split-Path -Parent $Path
  if (-not (Test-Path $dir)) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
  }
  $tmp = [IO.Path]::GetTempFileName()
  try {
    $enc = [Text.UTF8Encoding]::new($false)
    [IO.File]::WriteAllText($tmp,$Content,$enc)
    Move-Item $tmp $Path -Force
  }
  finally {
    if (Test-Path $tmp) {
      Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    }
  }
}
$file = "path/to/your_file.ext"
$enc  = [Text.UTF8Encoding]::new($false)
$old  = (Test-Path $file) ? ([IO.File]::ReadAllText($file,$enc)) : ''
Write-Utf8NoBom -Path $file -Content ($old+"`nYOUR_TEXT_HERE`n")
"'
```