$ErrorActionPreference = 'Stop'

function Confirm-Administrator {
    $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($currentIdentity)
    $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-Error '[ERROR] Please run this script as Administrator.'
        exit 1
    }
}

function Invoke-WslDockerCleanup {
    Write-Host '[INFO] Start docker cleanup inside WSL'

    & wsl -e bash -lc 'docker system prune -af'
    if ($LASTEXITCODE -ne 0) {
        throw 'docker system prune failed.'
    }

    & wsl -e bash -lc 'docker builder prune -af'
    if ($LASTEXITCODE -ne 0) {
        throw 'docker builder prune failed.'
    }
}

function Get-WslBasePaths {
    [OutputType([string[]])]
    param()

    $lxssPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss'
    $keys = Get-ChildItem -Path $lxssPath -ErrorAction SilentlyContinue
    $basePaths = @()

    foreach ($key in $keys) {
        $prop = Get-ItemProperty -Path $key.PSPath -Name 'BasePath' -ErrorAction SilentlyContinue
        $basePath = $prop.BasePath
        if ([string]::IsNullOrWhiteSpace($basePath)) {
            continue
        }
        $basePaths += $basePath
    }

    return $basePaths
}

function Wait-WslShutdown {
    param(
        [int]$TimeoutSeconds = 30,
        [int]$IntervalSeconds = 1
    )

    $elapsed = 0
    while ($elapsed -lt $TimeoutSeconds) {
        $running = & wsl --list --running 2>$null
        if ($LASTEXITCODE -eq 0) {
            if (-not $running -or $running.Count -eq 0 -or ($running -join ' ') -match 'has no installed distributions') {
                return
            }
        }

        Start-Sleep -Seconds $IntervalSeconds
        $elapsed += $IntervalSeconds
    }

    throw 'Timeout waiting WSL shutdown.'
}

function Compact-Vhdx {
    param(
        [string]$BasePath,
        [string]$ScriptPath
    )

    if ([string]::IsNullOrWhiteSpace($BasePath)) {
        return
    }

    $vhdPath = Join-Path -Path $BasePath -ChildPath 'ext4.vhdx'
    if (-not (Test-Path -LiteralPath $vhdPath)) {
        Write-Warning ("[WARN] Skip: ""{0}"" not found." -f $vhdPath)
        return
    }

    Write-Host ("[INFO] Compact ""{0}""" -f $vhdPath)
    $lines = @(
        ("select vdisk file=""{0}""" -f $vhdPath)
        'attach vdisk readonly'
        'compact vdisk'
        'detach vdisk'
    )
    Set-Content -Path $ScriptPath -Value $lines -Encoding ASCII

    & diskpart /s $ScriptPath *> $null
    if ($LASTEXITCODE -ne 0) {
        throw ("diskpart failed for ""{0}""" -f $vhdPath)
    }
}

function Remove-HostBuildCache {
    $cacheRoot = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'tool-scripts-buildx-cache'
    if (-not (Test-Path -LiteralPath $cacheRoot)) {
        Write-Host '[INFO] Host buildx cache not found. Skip.'
        return
    }

    Write-Host ("[INFO] Remove host buildx cache -> {0}" -f $cacheRoot)
    try {
        Remove-Item -LiteralPath $cacheRoot -Recurse -Force -ErrorAction Stop
    }
    catch {
        Write-Warning ("[WARN] Failed to remove host buildx cache: {0}" -f $_.Exception.Message)
    }
}

try {
    Confirm-Administrator
    Invoke-WslDockerCleanup

    Write-Host '[INFO] Shutdown all WSL instances'
    & wsl --shutdown
    if ($LASTEXITCODE -ne 0) {
        throw 'Failed to shutdown WSL.'
    }

    Wait-WslShutdown

    Remove-HostBuildCache

    $diskpartScript = Join-Path -Path $env:TEMP -ChildPath 'diskpart_wsl.txt'
    try {
        $basePaths = Get-WslBasePaths
        foreach ($path in $basePaths) {
            Compact-Vhdx -BasePath $path -ScriptPath $diskpartScript
        }
    }
    finally {
        if (Test-Path -LiteralPath $diskpartScript) {
            Remove-Item -LiteralPath $diskpartScript -Force -ErrorAction SilentlyContinue
        }
    }

    Write-Host '[INFO] Finished.'
    exit 0
}
catch {
    Write-Error ("[ERROR] Cleanup failed. {0}" -f $_.Exception.Message)
    exit 1
}
