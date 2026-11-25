$ErrorActionPreference = "Stop"

# Build Rust core (`vedro_ffi.dll`) and Flutter Windows x64 release ZIP into dist/.

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

$ZipPath = Join-Path $DistDir "vedro-v$Version-windows-x64.zip"
if (Test-Path $ZipPath) { Remove-Item $ZipPath -Force }
Compress-Archive -Path "$ReleaseDir\*" -DestinationPath $ZipPath -CompressionLevel Optimal

Write-Host "==> Done! Windows package ready:"
Get-Item $ZipPath | Select-Object Name, Length
