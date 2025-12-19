Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# この ps1 の場所基準
$root = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$projects  = Join-Path $root "projects"
if (-not (Test-Path -LiteralPath $projects)) { throw "[ERROR] projects ディレクトリが見つかりません: $projects" }

function Initialize-Venv([string]$projectDir) {
    Write-Host ("[INFO] セットアップ開始: {0}" -f $projectDir)

    Push-Location -LiteralPath $projectDir
    try {
        if (-not (Test-Path -LiteralPath ".\pyproject.toml")) {
            Write-Host ("[SKIP] pyproject.toml が無いためスキップ: {0}" -f $projectDir)
            return
        }

        uv --native-tls venv --clear --python 3.11
        . .\.venv\Scripts\Activate.ps1
        uv --native-tls sync --active
    }
    finally {
        deactivate 2>$null
        $env:VIRTUAL_ENV = $null
        Pop-Location
    }

    Write-Host ("[INFO] セットアップ完了: {0}" -f $projectDir)
}

# projects 直下のサブディレクトリを列挙して順次処理
Get-ChildItem -LiteralPath $projects -Directory -ErrorAction Stop |
    Sort-Object Name |
    ForEach-Object { Initialize-Venv $_.FullName }
