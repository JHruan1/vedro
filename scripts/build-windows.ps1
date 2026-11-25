$ErrorActionPreference = "Stop"

# Build Rust core (`prism_ffi.dll`) and Flutter Windows release application.
# Run on Windows x64 with Visual Studio C++ Build Tools, Rust MSVC toolchain, and Flutter SDK.

$RootDir = Split-Path -Parent $PSScriptRoot
Set-Location $RootDir

Write-Host "==> Building Rust prism-ffi (x86_64-pc-windows-msvc)..."
cargo build --release -p prism-ffi

Write-Host "==> Building Flutter Windows release..."
Set-Location "$RootDir\app"
flutter pub get
flutter build windows --release

$ReleaseDir = "$RootDir\app\build\windows\x64\runner\Release"
Copy-Item "$RootDir\target\release\prism_ffi.dll" "$ReleaseDir\prism_ffi.dll" -Force
Write-Host "Done! Windows release ready in $ReleaseDir"
