# この ps1 自身のフルパスを取得
$scriptPath = $MyInvocation.MyCommand.Path

# 拡張子を .exe に差し替え
$exePath = [System.IO.Path]::ChangeExtension($scriptPath, "exe")
$yamlPath = [System.IO.Path]::ChangeExtension($scriptPath, "yaml")

# exe が存在するかチェック
if (Test-Path $exePath) {
    & $exePath --configFilePath=$yamlPath
} else {
    Write-Error "対応する exe が見つかりません: $exePath"
}

Pause