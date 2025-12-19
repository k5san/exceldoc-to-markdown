param(
  # ビルドコンテキスト（workspace または projects/<pkg> のどちらでも可）
  [string]$ProjectPath = (Get-Location).Path,

  # Dockerfile のパス（省略時は ProjectPath/Dockerfile）
  [string]$DockerfilePath,

  # Docker イメージ名（:タグは不要。:latest を使う）
  [string]$ImageName = "pyapp",

  # ターゲットプラットフォーム
  [ValidateSet("linux/amd64","linux/arm64")]
  [string]$Platform = "linux/arm64",

  # エントリーパッケージ名（例: maintenance_database）
  [Parameter(Mandatory = $true)]
  [string]$EntryPackage,

  # コンテナ内の単一成果物ファイルのフルパス（例: /app/app）
  [string]$ContainerArtifactPath = "/app/app"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$script:RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:BuilderName = "tool-scripts-buildx"

# Build cache をリポジトリ外（ローカル AppData）に退避し、コンテキスト肥大を防ぐ
$script:CacheRoot = Join-Path ([Environment]::GetFolderPath("LocalApplicationData")) "tool-scripts-buildx-cache"

# ========== ログ出力 ==========
function writeInfo([string]$msg) { Write-Host "[INFO] $msg" }
function writeErrorMsg([string]$msg) { Write-Host "[ERROR] $msg" -ForegroundColor Red }

# ========== パスユーティリティ ==========
function normalizePath([string]$path) {
  try { return (Resolve-Path -LiteralPath $path).Path } catch { return [System.IO.Path]::GetFullPath($path) }
}
function toWslPath([string]$winPath) {
  $out = wsl -e wslpath -a "$winPath" 2>$null
  if ([string]::IsNullOrWhiteSpace($out)) { throw "wslpath 変換に失敗しました: $winPath" }
  return $out.Trim()
}
function ensureDirectory([string]$path) {
  if (-not (Test-Path -LiteralPath $path)) {
    New-Item -ItemType Directory -Path $path -Force | Out-Null
  }
  return (normalizePath $path)
}

# ========== 前提チェック ==========
function ensureHostRequirements() {
  writeInfo "ホスト環境確認（WSL / Docker / buildx） 開始"
  $ok = $true
  try { wsl -e bash -lc "echo ok" | Out-Null } catch { $ok = $false }
  if (-not $ok) { throw "WSL が利用できません。" }

  $dockerOk = (wsl -e bash -lc "command -v docker >/dev/null && echo OK || echo NG").Trim() -eq "OK"
  if (-not $dockerOk) { throw "WSL 内で docker が見つかりません。" }
  writeInfo "ホスト環境確認（WSL / Docker / buildx） 終了"
}

function ensurePaths() {
  if ([string]::IsNullOrWhiteSpace($DockerfilePath)) {
    $DockerfilePath = Join-Path -Path $ProjectPath -ChildPath "Dockerfile"
  }
  if (-not (Test-Path -LiteralPath $ProjectPath)) {
    throw "ProjectPath が存在しません: $ProjectPath"
  }
  if (-not (Test-Path -LiteralPath $DockerfilePath)) {
    throw "DockerfilePath が存在しません: $DockerfilePath"
  }

  if (-not $ContainerArtifactPath -or $ContainerArtifactPath -notmatch '^/[^:]+' ) {
    throw "ContainerArtifactPath が不正です: $ContainerArtifactPath（例: /app/app）"
  }

  $script:ProjectPath = normalizePath $ProjectPath
  $script:DockerfilePath = normalizePath $DockerfilePath
  $script:ContainerArtifactPath = $ContainerArtifactPath

  writeInfo "ProjectPath           = $script:ProjectPath "
  writeInfo "DockerfilePath        = $script:DockerfilePath"
  writeInfo "ImageName             = $script:ImageName"
  writeInfo "Platform              = $script:Platform"
  writeInfo "EntryPackage          = $script:EntryPackage"
  writeInfo "ContainerArtifactPath = $script:ContainerArtifactPath"
}

# ProjectPath が workspace 直下でも projects/<pkg> 直指定でも正しく解決
function getPackageDir([string]$projectRoot, [string]$pkg) {
  $rootAbs = normalizePath $projectRoot
  $leaf = Split-Path -Leaf $rootAbs
  $parentLeaf = Split-Path -Leaf (Split-Path -Parent $rootAbs)

  if ($leaf -eq $pkg -and $parentLeaf -eq "projects") { return $rootAbs }

  $candidate = Join-Path $rootAbs ("projects/{0}" -f $pkg)
  if (Test-Path -LiteralPath $candidate) { return (normalizePath $candidate) }

  throw "パッケージディレクトリを特定できません。projectPath=$rootAbs, entryPackage=$pkg"
}

# ========== Docker/WSL 操作 ==========
function ensureBinfmt() {
  $binfmtReady = (wsl -e bash -lc "test -r /proc/sys/fs/binfmt_misc/qemu-aarch64 && echo OK || echo NG").Trim() -eq "OK"
  if ($binfmtReady) {
    return
  }
  writeInfo "binfmt を登録します"
  wsl -e bash -lc "docker run --privileged --rm tonistiigi/binfmt --install all >/dev/null 2>&1 || true" | Out-Null
}
function initBuildx() {
  writeInfo "buildx / binfmt を初期化します"
  ensureBinfmt

  $builderName = $script:BuilderName
  $inspect = (wsl -e bash -lc "docker buildx inspect '$builderName' >/dev/null 2>&1 && echo OK || echo NG").Trim()
  if ($inspect -ne "OK") {
    writeInfo "buildx builder [$builderName] を作成します"
    $createCmd = "docker buildx create --name '$builderName' --driver docker-container --bootstrap >/dev/null 2>&1"
    wsl -e bash -lc "$createCmd" | Out-Null
  }
  wsl -e bash -lc "docker buildx use '$builderName' >/dev/null 2>&1" | Out-Null

  # builder が正しく起動しているか最終確認
  $validate = (wsl -e bash -lc "docker buildx inspect '$builderName' --bootstrap >/dev/null 2>&1 && echo OK || echo NG").Trim()
  if ($validate -ne "OK") {
    throw "buildx builder の初期化に失敗しました: $builderName"
  }
}

function ensureCacheDirForPlatform([string]$platform) {
  ensureDirectory $script:CacheRoot | Out-Null
  $safeName = $platform -replace '[\\/]', '_'
  $dir = Join-Path $script:CacheRoot $safeName
  return (ensureDirectory $dir)
}

function buildImage([string]$wslProjectPath, [string]$wslDockerfile) {
  writeInfo "ビルド開始"
  $cacheDir = ensureCacheDirForPlatform -platform $Platform
  $wslCacheDir = toWslPath $cacheDir
  $builderName = $script:BuilderName
  $cmd = @(
    "set -euo pipefail",
    "cd '$wslProjectPath'",
    "docker buildx build --builder '$builderName' --platform '$Platform' -t '$ImageName' --build-arg ENTRY_PACKAGE='$EntryPackage' -f '$wslDockerfile' --cache-from type=local,src='$wslCacheDir' --cache-to type=local,dest='$wslCacheDir',mode=max --load ."
  ) -join " && "
  wsl -e bash -lc "$cmd" | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "docker buildx に失敗しました（exit=$LASTEXITCODE）" }
  writeInfo "ビルド終了"
}
function createContainer([string]$image) {
  writeInfo "一時コンテナを作成します"
  $raw = wsl -e bash -lc "docker create '$image' 2>/dev/null"
  if ([string]::IsNullOrWhiteSpace($raw)) { throw "コンテナIDの取得に失敗しました（空）" }
  $cid = $raw.Trim()
  if (-not ($cid -match '^[0-9a-f]{12,}$')) { throw "コンテナIDの取得に失敗しました（値: $cid）" }
  return $cid
}
function startContainer([string]$cid) {
  # 実行中かに関わらず成功させる
  wsl -e bash -lc "docker start '$cid' >/dev/null 2>&1 || true" | Out-Null
}

function stopContainer([string]$cid) {
  wsl -e bash -lc "docker stop '$cid' >/dev/null 2>&1 || true" | Out-Null
}

function removeContainer([string]$cid) {
  if ([string]::IsNullOrWhiteSpace($cid)) {
    writeInfo "削除対象のコンテナはありません（cid 未取得）"
    return
  }
  writeInfo "一時コンテナ削除 開始"
  wsl -e bash -lc "docker rm '$cid' >/dev/null 2>&1 || true" | Out-Null
  writeInfo "一時コンテナ削除 終了"
}

function containerFileExists([string]$cid, [string]$containerPath) {
  startContainer $cid

  # リテラル here-string で作成し、bash -lc には "..." で1引数として渡す
  $script = @'
docker exec '__CID__' sh -c 'test -f "__PATH__"'
'@
  $script = $script.Replace('__CID__', $cid).Replace('__PATH__', $containerPath)

  wsl -e bash -lc "$script" | Out-Null
  $rc = $LASTEXITCODE

  stopContainer $cid
  return ($rc -eq 0)
}

# ========== 成果物の配置 ==========
# 出力先は <pkgDir>/.target/dist/<pkg>（最後は単一ファイル）
function prepareArtifactDirs([string]$pkgDir, [string]$pkg) {
  $targetRoot = Join-Path $pkgDir ".target"
  if (Test-Path -LiteralPath $targetRoot) {
    Remove-Item -LiteralPath $targetRoot -Recurse -Force
  }

  # 例: linux/amd64 -> dist-linux-amd64
  $platformTag = ($Platform -replace '/', '-')
  $distDirName = "dist-$platformTag"
  $distDir = Join-Path $targetRoot $distDirName

  New-Item -ItemType Directory -Path $distDir -Force | Out-Null

  $targetFile = Join-Path $distDir $pkg
  return @{
    pkgDir     = (normalizePath $pkgDir)
    targetRoot = (normalizePath $targetRoot)
    distDir    = (normalizePath $distDir)
    targetFile = $targetFile
  }
}

function copyArtifactAsFile([string]$cid, [string]$containerPath, [string]$targetFile) {
  # コンテナから単一ファイルを取り出す。停止中コンテナからの docker cp は可能。
  writeInfo ("成果物コピー 開始")
  writeInfo ("cid           = $cid")
  writeInfo ("containerPath = $containerPath")
  writeInfo ("targetFile    = $targetFile")

  # 出力先ディレクトリを必ず先に作る（toWslPath は存在しないパスだと失敗しやすい）
  $parentDir = Split-Path -Parent $targetFile
  if (-not (Test-Path -LiteralPath $parentDir)) {
    New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
  }

  # Windows → WSL パスに変換（ここで必ず代入しておく）
  $wslTargetFile = toWslPath $targetFile
  if ([string]::IsNullOrWhiteSpace($wslTargetFile)) {
    throw "toWslPath の変換に失敗しました: $targetFile"
  }

  writeInfo ("成果物をコピーします -> {0}" -f (normalizePath $targetFile))

  # 停止中コンテナから直接コピー。存在しない場合は rc != 0 で分かる
  $cpScript = ("docker cp '{0}':'{1}' '{2}'" -f $cid, $containerPath, $wslTargetFile)
  wsl -e bash -lc "$cpScript" | Out-Null
  if ($LASTEXITCODE -ne 0) {
    # 追加情報：イメージ内に本当にあるかをワンショットで確認（ENTRYPOINTを上書き）
    $probe = ("docker run --rm --entrypoint sh '{0}' -lc 'ls -l ""{1%/*}""; file ""{1}"" || true'" -f $ImageName, $ContainerArtifactPath)
    writeErrorMsg ("docker cp に失敗しました（rc={0} / path={1}）。イメージ内確認: {2}" -f $LASTEXITCODE, $containerPath, $probe)
    throw "docker cp に失敗しました（rc=$LASTEXITCODE / path=$containerPath）"
  }

  # 反映待ち（ファイルが見えるまで少し待つ）
  $ok = $false
  for ($i=0; $i -lt 30; $i++) {
    if (Test-Path -LiteralPath $targetFile) { $ok = $true; break }
    Start-Sleep -Milliseconds 100
  }
  if (-not $ok) { throw "成果物のコピー後にファイルが見つかりません: $targetFile" }

  writeInfo ("成果物コピー 終了")
}

# 追加同梱（src/other と src/others 両対応）: コピー前に存在確認
function copyExtrasIfAny([string]$pkgDir, [string]$distDir) {
  $candidates = @(
    (Join-Path $pkgDir "src/other"),
    (Join-Path $pkgDir "src/others")
  )
  $copied = $false
  foreach ($dir in $candidates) {
    if (-not (Test-Path -LiteralPath $dir)) { continue }
    # 存在確認（中身があるか）
    $hasAny = @(Get-ChildItem -LiteralPath $dir -Force -Recurse -ErrorAction SilentlyContinue | Where-Object { -not $_.PSIsContainer }).Count -gt 0
    if ($hasAny) {
      Copy-Item -Path (Join-Path $dir "*") -Destination $distDir -Recurse -Force -ErrorAction Stop
      $copied = $true
    }
  }
  if ($copied) {
    writeInfo ("追加ファイルをコピーしました -> {0}" -f $distDir)
  } else {
    writeInfo "追加ファイルはありません（src/other または src/others 未検出）"
  }
}

# ========== 実行フロー ==========
try {
  ensureHostRequirements
  ensurePaths

  $pkgDir = getPackageDir -projectRoot $ProjectPath -pkg $EntryPackage

  $wslProjectPath = toWslPath $ProjectPath
  $wslDockerfile  = toWslPath $DockerfilePath

  initBuildx
  buildImage -wslProjectPath $wslProjectPath -wslDockerfile $wslDockerfile

  $cid = createContainer -image $ImageName
  try {
    $dirs = prepareArtifactDirs -pkgDir $pkgDir -pkg $EntryPackage
    copyArtifactAsFile -cid $cid -containerPath $ContainerArtifactPath -targetFile $dirs.targetFile
  }
  finally {
    removeContainer -cid $cid
  }

  # ここは $dirs が作れた前提。try 内で失敗したらここへ来ないようにする
  if ($null -ne $dirs -and $dirs.ContainsKey('distDir')) {
    copyExtrasIfAny -pkgDir $pkgDir -distDir $dirs.distDir
    writeInfo ("完了しました。成果物: {0}" -f (normalizePath $dirs.targetFile))
  }
  Write-Output $dirs.distDir
  exit 0
}
catch {
  writeErrorMsg ($_.Exception.Message)
  exit 1
}
