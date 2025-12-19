param(
    [string[]] $TargetProjects  # ビルドしたいプロジェクト名（複数可）
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$here     = Split-Path -Parent $MyInvocation.MyCommand.Path
$projects = Join-Path $here "projects"
$distRoot = Join-Path $here "dist"
$logDir   = Join-Path $here "log"

if (-not (Test-Path -LiteralPath $logDir)) {
    New-Item -ItemType Directory -Path $logDir | Out-Null
}

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logFile = Join-Path $logDir ("rebuild_all_{0}.log" -f $timestamp)
$transcriptStarted = $false
try {
    Start-Transcript -Path $logFile | Out-Null
    $transcriptStarted = $true
}
catch {
    Write-Host "[WARN] Start-Transcript failed: $($_.Exception.Message)"
}

try {
    # dist を作り直す
    if (Test-Path $distRoot) {
        Remove-Item -LiteralPath $distRoot -Recurse -Force
    }
    New-Item -ItemType Directory -Path $distRoot | Out-Null

    # 対象スクリプト名を固定リスト化
    $targetScriptNames = @(
        "build_linux_amd64.ps1",
        "build_linux_arm64.ps1",
        "build_windows.ps1"
    )

    $plannedScripts = @()

    # projects 直下のプロジェクトだけを走査（事前に実行リストを収集）
    Get-ChildItem -Path $projects -Directory | ForEach-Object {
        $projDir  = $_.FullName
        $projName = $_.Name

        if ($TargetProjects -and ($TargetProjects -notcontains $projName)) {
            Write-Host "[SKIP] $projName は引数で指定されていません"
            continue
        }

        foreach ($scriptName in $targetScriptNames) {
            $buildScript = Join-Path $projDir $scriptName
            $plannedScripts += [PSCustomObject]@{
                Project     = $projName
                ScriptName  = $scriptName
                BuildScript = $buildScript
                Exists      = Test-Path -LiteralPath $buildScript
            }
        }
    }

    if (-not $plannedScripts) {
        Write-Host "[WARN] 実行対象がありませんでした"
        return
    }

    Write-Host "[INFO] 実行予定スクリプト一覧:"
    foreach ($plan in $plannedScripts) {
        if ($plan.Exists) {
            Write-Host (" - {0}/{1}" -f $plan.Project, $plan.ScriptName)
        }
    }

    $results = @()
    $executableTotal = ($plannedScripts | Where-Object { $_.Exists }).Count
    $currentIndex = 0

    foreach ($plan in $plannedScripts) {
        if (-not $plan.Exists) {
            continue
        }

        $currentIndex++
        $progress = "{0}/{1}" -f $currentIndex, $executableTotal
        $timestamp = (Get-Date).ToString("yyyy/MM/dd HH:mm:ss")
        Write-Host ("[INFO][{0}][{1}] 実行中: {2} {3}" -f $progress, $timestamp, $plan.Project, $plan.ScriptName)

        $result = $null
        try {
            $result = & $plan.BuildScript
        }
        catch {
            $errMsg = $_.Exception.Message
            Write-Host "[ERROR] $($plan.Project)/$($plan.ScriptName) の実行に失敗: $errMsg"
            $results += [PSCustomObject]@{
                Project = $plan.Project
                Script  = $plan.ScriptName
                Status  = "failed"
                Detail  = "execute: $errMsg"
            }
            continue
        }

        if ($result -is [array]) {
            $result = $result[-1]
        }

        if ($null -eq $result) {
            Write-Host "[ERROR] $($plan.Project)/$($plan.ScriptName) の戻り値が空です"
            $results += [PSCustomObject]@{
                Project = $plan.Project
                Script  = $plan.ScriptName
                Status  = "failed"
                Detail  = "empty result"
            }
            continue
        }

        $artifactPath = if ($result -is [string]) { $result } else { $result.Path }
        $platformName = if ($result -isnot [string] -and $result.PSObject.Properties.Match("Platform").Count -gt 0) { $result.Platform } else { "unknown" }
        $projectName  = if ($result -isnot [string] -and $result.PSObject.Properties.Match("Project").Count -gt 0) { $result.Project }  else { $plan.Project }

        if (-not (Test-Path -LiteralPath $artifactPath)) {
            Write-Host "[ERROR] 成果物が見つかりません: $artifactPath"
            $results += [PSCustomObject]@{
                Project = $plan.Project
                Script  = $plan.ScriptName
                Status  = "failed"
                Detail  = "artifact not found"
            }
            continue
        }

        $platformDir = Join-Path $distRoot $platformName
        $destPath    = Join-Path $platformDir $projectName

        try {
            New-Item -ItemType Directory -Path $platformDir -Force | Out-Null
            if (Test-Path -LiteralPath $destPath) {
                Remove-Item -LiteralPath $destPath -Recurse -Force
            }

            if (Test-Path $artifactPath -PathType Container) {
                Copy-Item -LiteralPath $artifactPath -Destination $destPath -Recurse -Force
                Write-Host "[INFO] ディレクトリをコピーしました -> $destPath"
            }
            else {
                Copy-Item -LiteralPath $artifactPath -Destination $destPath -Force
                Write-Host "[INFO] ファイルをコピーしました -> $destPath"
            }

            $results += [PSCustomObject]@{
                Project = $plan.Project
                Script  = $plan.ScriptName
                Status  = "success"
                Detail  = $destPath
            }
        }
        catch {
            $errMsg = $_.Exception.Message
            Write-Host "[ERROR] 成果物コピーに失敗しました: $errMsg"
            $results += [PSCustomObject]@{
                Project = $plan.Project
                Script  = $plan.ScriptName
                Status  = "failed"
                Detail  = "copy: $errMsg"
            }
            continue
        }
    }

    Write-Host "[INFO] 実行結果サマリ:"
    $successTotal = 0
    foreach ($res in $results) {

        if ($res.Status == "success") {
            $successTotal += 1
        }

        Write-Host (" - {0}/{1}: {2} ({3})" -f $res.Project, $res.Script, $res.Status, $res.Detail)
    }
    Write-Host "[INFO] Success {0}/{1}" -f $successTotal, $executableTotal
    
    Write-Output $distRoot
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

exit 0
