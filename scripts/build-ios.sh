#!/usr/bin/env bash
set -euo pipefail

# Cross-compile Rust core (`libprism_ffi.a`) for iOS arm64, link statically into the
# Flutter iOS Runner binary, and package an unsigned installable IPA into dist/.

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="$ROOT_DIR/app/ios/Frameworks"
DIST_DIR="$ROOT_DIR/dist"
mkdir -p "$OUT_DIR" "$DIST_DIR"

cd "$ROOT_DIR"
echo "==> Building Rust prism-ffi for iOS (aarch64-apple-ios)..."
cargo build --release -p prism-ffi --target aarch64-apple-ios

cp -f "$ROOT_DIR/target/aarch64-apple-ios/release/libprism_ffi.a" "$OUT_DIR/libprism_ffi.a"
ls -lh "$OUT_DIR/libprism_ffi.a"

# Ensure Release.xcconfig force-loads libprism_ffi.a so DynamicLibrary.process() resolves all prism_* symbols
XCCONFIG="$ROOT_DIR/app/ios/Flutter/Release.xcconfig"
if ! grep -q "libprism_ffi.a" "$XCCONFIG"; then
  printf '\nOTHER_LDFLAGS = $(inherited) -force_load $(PROJECT_DIR)/Frameworks/libprism_ffi.a\n' >> "$XCCONFIG"
fi

echo "==> Building Flutter iOS release (no-codesign)..."
cd "$ROOT_DIR/app"
flutter pub get
flutter build ios --release --no-codesign

echo "==> Packaging unsigned IPA for TrollStore / Sideloadly / AltStore..."
STAGE_DIR="$(mktemp -d)"
mkdir -p "$STAGE_DIR/Payload"
cp -R "$ROOT_DIR/app/build/ios/iphoneos/Runner.app" "$STAGE_DIR/Payload/"
(cd "$STAGE_DIR" && zip -qry "$DIST_DIR/prism-player-ios-unsigned.ipa" Payload)
rm -rf "$STAGE_DIR"

ls -lh "$DIST_DIR/prism-player-ios-unsigned.ipa"
