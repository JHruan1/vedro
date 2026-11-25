#!/usr/bin/env bash
set -euo pipefail

# Build Universal macOS binary (Apple Silicon arm64 + Intel x86_64) for Rust core (`libprism_ffi.dylib`)
# and bundle into the Flutter macOS app.

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="$ROOT_DIR/app/macos/Frameworks"
mkdir -p "$OUT_DIR"

cd "$ROOT_DIR"
echo "==> Building Rust prism-ffi universal dylib (arm64 + x86_64)..."
cargo build --release -p prism-ffi --target aarch64-apple-darwin
cargo build --release -p prism-ffi --target x86_64-apple-darwin

lipo -create \
  "$ROOT_DIR/target/aarch64-apple-darwin/release/libprism_ffi.dylib" \
  "$ROOT_DIR/target/x86_64-apple-darwin/release/libprism_ffi.dylib" \
  -output "$OUT_DIR/libprism_ffi.dylib"

install_name_tool -id "@rpath/libprism_ffi.dylib" "$OUT_DIR/libprism_ffi.dylib"

echo "==> Building Flutter macOS release app..."
cd "$ROOT_DIR/app"
flutter pub get
flutter build macos --release
cp "$OUT_DIR/libprism_ffi.dylib" "$ROOT_DIR/app/build/macos/Build/Products/Release/prism_player.app/Contents/Frameworks/"
echo "Done! macOS .app ready."
