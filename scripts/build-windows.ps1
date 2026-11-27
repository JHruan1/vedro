$ErrorActionPreference = "Stop"

# Build Rust core (`vedro_ffi.dll`), Flutter Windows x64 release bundle,
# and native Inno Setup `.exe` installer (`dist/vedro-v<Version>-windows-x64-setup.exe`).

$RootDir = Split-Path -Parent $PSScriptRoot
$Version = if ($env:VEDRO_VERSION) {
  $env:VEDRO_VERSION.TrimStart('v')
} else {
  $PubspecLine = Select-String -Path (Join-Path $RootDir "app\pubspec.yaml") -Pattern '^version:\s*([^\s+]+)' | Select-Object -First 1
  $PubspecLine.Matches[0].Groups[1].Value.Trim()
}
$DistDir = Join-Path $RootDir "dist"
New-Item -ItemType Directory -Force -Path $DistDir | Out-Null

Set-Location $RootDir
Write-Host "==> Building Rust vedro-ffi (x86_64-pc-windows-msvc)..."
cargo build --release -p vedro-ffi

Write-Host "==> Building Flutter Windows release..."
Set-Location (Join-Path $RootDir "app")
flutter pub get
flutter build windows --release

$ReleaseDir = Join-Path $RootDir "app\build\windows\x64\runner\Release"
Copy-Item (Join-Path $RootDir "target\release\vedro_ffi.dll") (Join-Path $ReleaseDir "vedro_ffi.dll") -Force

# Bundle MSVC runtime DLLs alongside Vedro.exe so clean Windows 10/11 machines need zero separate VC++ redist install
foreach ($VcDll in @(
  "vcruntime140.dll",
  "vcruntime140_1.dll",
  "msvcp140.dll",
  "msvcp140_1.dll",
  "msvcp140_2.dll",
  "msvcp140_atomic_wait.dll",
  "concrt140.dll"
)) {
  $SysDll = Join-Path $env:SystemRoot "System32\$VcDll"
  $DestDll = Join-Path $ReleaseDir $VcDll
  if ((Test-Path $SysDll) -and -not (Test-Path $DestDll)) {
    Copy-Item $SysDll $DestDll -Force
  }
}

# Locate Inno Setup 6 compiler (ISCC.exe) — pre-installed on GitHub Actions windows-latest
$IsccCandidates = @(
  "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
  "$env:ProgramFiles\Inno Setup 6\ISCC.exe",
  "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe"
)
$IsccExe = $IsccCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $IsccExe) {
  $Cmd = Get-Command iscc -ErrorAction SilentlyContinue
  if ($Cmd) { $IsccExe = $Cmd.Source }
}
if (-not $IsccExe) {
  Write-Host "==> Installing Inno Setup via Chocolatey..."
  choco install innosetup --no-progress -y
  $IsccExe = $IsccCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
}
if (-not $IsccExe) {
  throw "ISCC.exe (Inno Setup 6) not found!"
}

$IsccDir = Split-Path -Parent $IsccExe
$ChineseIsl = Join-Path $IsccDir "Languages\ChineseSimplified.isl"
if (-not (Test-Path $ChineseIsl)) {
  $UnofficialIsl = Join-Path $IsccDir "Languages\Unofficial\ChineseSimplified.isl"
  if (Test-Path $UnofficialIsl) {
    $ChineseIsl = $UnofficialIsl
  } else {
    $DownloadedIsl = Join-Path $env:TEMP "ChineseSimplified.isl"
    try {
      Invoke-WebRequest -Uri "https://raw.githubusercontent.com/jrsoftware/issrc/main/Files/Languages/Unofficial/ChineseSimplified.isl" -OutFile $DownloadedIsl -UseBasicParsing -TimeoutSec 15
      if ((Test-Path $DownloadedIsl) -and ((Get-Item $DownloadedIsl).Length -gt 1024)) {
        $ChineseIsl = $DownloadedIsl
      }
    } catch {
      Write-Host "Note: ChineseSimplified.isl download skipped, falling back to Default.isl"
    }
  }
}

$IssPath = Join-Path $RootDir "scripts\vedro-windows-installer.iss"
$IconPath = Join-Path $RootDir "app\windows\runner\resources\app_icon.ico"
$IsccArgs = @(
  "/DMyAppVersion=$Version",
  "/DMyReleaseDir=$ReleaseDir",
  "/DMyOutputDir=$DistDir",
  "/DMyIconFile=$IconPath"
)
if (Test-Path $ChineseIsl) {
  $IsccArgs += "/DHasChineseSimplified=1"
  $IsccArgs += "/DChineseIslPath=$ChineseIsl"
}
$IsccArgs += $IssPath

Write-Host "==> Compiling Windows Setup .exe with Inno Setup ($IsccExe)..."
& $IsccExe @IsccArgs
if ($LASTEXITCODE -ne 0) {
  throw "ISCC failed with exit code $LASTEXITCODE"
}

$ExePath = Join-Path $DistDir "vedro-v$Version-windows-x64-setup.exe"
if (-not (Test-Path $ExePath)) {
  throw "Expected installer output not found: $ExePath"
}

Write-Host "==> Done! Windows Setup .exe ready:"
Get-Item $ExePath | Select-Object Name, Length
