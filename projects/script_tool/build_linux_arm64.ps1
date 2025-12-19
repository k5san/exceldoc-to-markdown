Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = "$here\..\.."
$entryPackage = Split-Path $here -Leaf

$artifactDirPath = & "$projectRoot\build_project_linux.ps1" `
                        -ProjectPath $projectRoot `
                        -DockerfilePath $here\Dockerfile `
                        -Platform linux/arm64 `
                        -ImageName ${entryPackage}:al9-arm64 `
                        -EntryPackage $entryPackage

# 成果物パスとプラットフォームを返す
[PSCustomObject]@{
    Path      = $artifactDirPath
    Platform  = "linux-arm64"
    Project   = $entryPackage
}
