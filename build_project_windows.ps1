param(
    [string]$ProjectRoot,                   # 未指定なら手入力を要求
    [string]$SpecFile = "Build.spec",       # 指定が無ければ手入力を要求（デフォルトは無視して上書き）
    [switch]$ClearVenv
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# --- 入力受付（候補表示なし・未入力なら即エラー） ---
if (-not $PSBoundParameters.ContainsKey('ProjectRoot')) {
    $inputPath = Read-Host "プロジェクトのルートディレクトリを入力してください（相対/絶対可）"
    if ([string]::IsNullOrWhiteSpace($inputPath)) {
        throw "[ERROR] ProjectRoot が指定されていません。"
    }
    $ProjectRoot = $inputPath
}

if (-not $PSBoundParameters.ContainsKey('SpecFile')) {
    $specInput = Read-Host "spec ファイル名（またはパス）を入力してください（例: Build.spec）"
    if ([string]::IsNullOrWhiteSpace($specInput)) {
        throw "[ERROR] SpecFile が指定されていません。"
    }
    $SpecFile = $specInput
}

# --- ProjectRoot を安全に正規化（ファイルでもディレクトリでもOK） ---
try {
    $item = Get-Item -LiteralPath $ProjectRoot -ErrorAction Stop
} catch {
    throw "[ERROR] ProjectRoot が不正です: $ProjectRoot`n$($_.Exception.Message)"
}
if (-not $item.PSIsContainer) {
    $ProjectRoot = $item.Directory.FullName
} else {
    $ProjectRoot = $item.FullName
}

# Spec は ProjectRoot 基準に解決（相対なら結合、絶対ならそのまま）
$Spec = if ([IO.Path]::IsPathRooted($SpecFile)) {
    $SpecFile
} else {
    Join-Path -Path $ProjectRoot -ChildPath $SpecFile
}

# 以降は常にディレクトリとして安全な $ProjectRoot を用いる
$Venv    = Join-Path $ProjectRoot ".venv"
$Target  = Join-Path $ProjectRoot ".target"
$WorkDir = Join-Path $Target "work"
$DistDir = Join-Path $Target "dist"
$SrcDir  = Join-Path $ProjectRoot "src"
$Other   = Join-Path $ProjectRoot "src/other"

# .target をクリーン
if (Test-Path -LiteralPath $Target) {
    Remove-Item -LiteralPath $Target -Recurse -Force
}

# venv 準備
if ($ClearVenv -or -not (Test-Path $Venv)) {
    if (Test-Path $Venv) { Remove-Item -Recurse -Force $Venv }
    Write-Host "[WORN] venv が見つかりません（または作り直し）。作成します..."
    uv --native-tls venv --python 3.11 $Venv
}

# venv を有効化
. (Join-Path $Venv "Scripts/Activate.ps1")

# 依存同期
Write-Host "[INFO] 依存を同期します（active venv）"
uv --native-tls sync --active

# 構文チェック（src 配下のみ、Warning はログ表示 → ユーザー確認）
Write-Host "[INFO] 構文チェックを開始します（compileall）"
if (-not (Test-Path $SrcDir)) {
    throw "[ERROR] src ディレクトリが見つかりません: $SrcDir"
} else {
    $pyArgs = @("run","--active","python","-W","default","-m","compileall","-q","-f",$SrcDir)
    $out = uv --native-tls @pyArgs 2>&1
    $out | ForEach-Object { if ($_){ Write-Host $_ } }
    if ($LASTEXITCODE -ne 0) {
        throw "[ERROR] 構文エラーが検出されました。修正してから再実行してください。"
    }
    if ($out -match "Warning") {
        Write-Host "[WORN] Warning が検出されました。続行しますか？ (y/n)"
        $answer = Read-Host
        if ($answer -ne "y") { throw "[INFO] ユーザーがキャンセルしました。" }
    }
    Write-Host "[INFO] 構文チェックを通過しました"
}

# PyInstaller 準備
[string]$PyExe = Join-Path $Venv "Scripts/pyinstaller.exe"
if (-not (Test-Path $PyExe)) {
    Write-Host "[WORN] PyInstaller が見つかりません。インストールします..."
    uv --native-tls add --dev pyinstaller --active
    uv --native-tls sync --active
}

# PyInstaller 実行（呼び出し元プロジェクトの spec を使用）
if (-not (Test-Path $Spec)) {
    throw "[ERROR] Spec ファイルが見つかりません: $Spec"
}
Write-Host "[INFO] PyInstaller を実行します: $Spec"
uv --native-tls run --active pyinstaller `
    --workpath $WorkDir `
    --distpath $DistDir `
    $Spec

# 追加ファイルコピー（任意）
if (Test-Path $Other) {
    Copy-Item -Path (Join-Path $Other "*") -Destination $DistDir -Recurse -Force
}

Write-Host "[INFO] 完了しました。出力: $DistDir"
Write-Output $DistDir