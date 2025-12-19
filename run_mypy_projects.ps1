param (
    [string] $ProjectFilter
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectsRoot = Join-Path $repoRoot "projects"
$logDir = Join-Path $repoRoot "log"
if (-not (Test-Path -LiteralPath $logDir)) {
    New-Item -ItemType Directory -Path $logDir | Out-Null
}
# 直近ログを before へリネームし、今回のログを after で保存
$existingLogs = @(Get-ChildItem -Path $logDir -Filter "mypy_after*.log" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
if ($existingLogs.Count -gt 0) {
    $latest = $existingLogs[0]
    $beforePath = Join-Path $logDir "mypy_before.log"
    try {
        Move-Item -LiteralPath $latest.FullName -Destination $beforePath -Force
    }
    catch {
        Write-Host "[WARN] rename to before failed: $($_.Exception.Message)"
    }
}
$logPath = Join-Path $logDir "mypy_after.log"
$transcriptStarted = $false
try {
    Start-Transcript -Path $logPath | Out-Null
    $transcriptStarted = $true
}
catch {
    Write-Host "[WARN] Start-Transcript failed: $($_.Exception.Message)"
}

function ensureUvExists {
    try {
        Get-Command uv -ErrorAction Stop | Out-Null
    }
    catch {
        Write-Error "[ERROR] uv コマンドが見つかりません。PATH を確認してください。"
        throw
    }
}

function runMypyForProject {
    param(
        [string] $ProjectPath,
        [string] $ProjectName
    )

    $srcPath = Join-Path $ProjectPath "src"
    if (-not (Test-Path -LiteralPath $srcPath)) {
        Write-Host "[SKIP] ${ProjectName}: src ディレクトリが見つかりません。"
        return "Skipped"
    }

    Write-Host "[INFO] ${ProjectName}: mypy 開始"
    Push-Location -LiteralPath $ProjectPath
    $oldPref = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $oldVenv = $env:VIRTUAL_ENV
    $oldPath = $env:Path
    $venvPath = Join-Path $ProjectPath ".venv"
    $venvPython = Join-Path $venvPath "Scripts\\python.exe"
    if (-not (Test-Path -LiteralPath $venvPython)) {
        Write-Host "[WARN] ${ProjectName}: .venv が見つからないためスキップ"
        $ErrorActionPreference = $oldPref
        Pop-Location
        return "Skipped"
    }
    $env:VIRTUAL_ENV = $venvPath
    $env:Path = "$(Join-Path $venvPath 'Scripts');$oldPath"
    try {
        $output = & uv --native-tls run --active mypy "./src" --check-untyped-defs 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "[OK] ${ProjectName}: 成功"
            return "Success"
        }

        Write-Host "[FAIL] ${ProjectName}: mypy がエラー終了 (exit=$LASTEXITCODE)"
        if ($output) {
            foreach ($line in $output) {
                Write-Host $line
            }
        }
        return "Failed"
    }
    catch {
        Write-Host "[ERROR] ${ProjectName}: $($_.Exception.Message)"
        return "Failed"
    }
    finally {
        $ErrorActionPreference = $oldPref
        $env:VIRTUAL_ENV = $oldVenv
        $env:Path = $oldPath
        Pop-Location
    }
}

if (-not (Test-Path -LiteralPath $projectsRoot)) {
    Write-Error "[ERROR] projects ディレクトリが見つかりません: $projectsRoot"
    throw
}

$exitCode = 0
try {
    ensureUvExists

    $results = @()
    Get-ChildItem -Path $projectsRoot -Directory | ForEach-Object {
        $projName = $_.Name
        if ($ProjectFilter -and ($projName -notlike "*$ProjectFilter*")) {
            return
        }

        $status = runMypyForProject -ProjectPath $_.FullName -ProjectName $projName
        $results += [PSCustomObject]@{
            Project = $projName
            Status  = $status
        }
    }

    $failed = @($results | Where-Object { $_.Status -eq "Failed" })
    if ($failed.Count -gt 0) {
        Write-Host "[SUMMARY] mypy 失敗プロジェクト:"
        $failed | ForEach-Object { Write-Host (" - {0}" -f $_.Project) }
        $exitCode = 1
    }
    else {
        Write-Host "[SUMMARY] すべての mypy が成功しました。"
    }
}
finally {
    if ($transcriptStarted) {
        try {
            Stop-Transcript | Out-Null
        }
        catch {
            Write-Host "[WARN] Stop-Transcript failed: $($_.Exception.Message)"
        }
    }
}

exit $exitCode
