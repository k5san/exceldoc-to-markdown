Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = $here
$entryPackage = Split-Path $here -Leaf

$artifactDirPath = & "$here\..\..\build_project_windows.ps1" `
                    -ProjectRoot $projectRoot `
                    -SpecFile "build.spec"

# 成果物パスとプラットフォームを返す
[PSCustomObject]@{
    Path      = $artifactDirPath
    Platform  = "windows"
    Project   = $entryPackage
}