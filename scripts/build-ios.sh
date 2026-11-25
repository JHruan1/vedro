#!/usr/bin/env bash
set -euo pipefail

# Cross-compile Rust core (`libvedro_ffi.a`) for iOS arm64, link statically into the
# Flutter iOS Runner binary, and package an unsigned installable IPA into dist/.

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${VEDRO_VERSION:-$(awk -F': *' '/^version:/{print $2; exit}' "$ROOT_DIR/app/pubspec.yaml" | cut -d'+' -f1 | tr -d '\r')}"
VERSION="${VERSION#v}"
OUT_DIR="$ROOT_DIR/app/ios/Frameworks"
DIST_DIR="$ROOT_DIR/dist"
mkdir -p "$OUT_DIR" "$DIST_DIR"

cd "$ROOT_DIR"
echo "==> Building Rust vedro-ffi for iOS (aarch64-apple-ios)..."
cargo build --release -p vedro-ffi --target aarch64-apple-ios

cp -f "$ROOT_DIR/target/aarch64-apple-ios/release/libvedro_ffi.a" "$OUT_DIR/libvedro_ffi.a"
ls -lh "$OUT_DIR/libvedro_ffi.a"

# Ensure Release.xcconfig force-loads libvedro_ffi.a so DynamicLibrary.process() resolves all vedro_* symbols
XCCONFIG="$ROOT_DIR/app/ios/Flutter/Release.xcconfig"
if ! grep -q "libvedro_ffi.a" "$XCCONFIG"; then
  printf '\nOTHER_LDFLAGS = $(inherited) -force_load $(PROJECT_DIR)/Frameworks/libvedro_ffi.a\n' >> "$XCCONFIG"
fi

echo "==> Building Flutter iOS release (no-codesign)..."
cd "$ROOT_DIR/app"
flutter pub get
flutter build ios --release --no-codesign

echo "==> Packaging unsigned IPA for TrollStore / Sideloadly / AltStore..."
STAGE_DIR="$(mktemp -d)"
mkdir -p "$STAGE_DIR/Payload"
cp -R "$ROOT_DIR/app/build/ios/iphoneos/Runner.app" "$STAGE_DIR/Payload/"
IPA_PATH="$DIST_DIR/vedro-v${VERSION}-ios-unsigned.ipa"
rm -f "$IPA_PATH"
(cd "$STAGE_DIR" && zip -qry "$IPA_PATH" Payload)
rm -rf "$STAGE_DIR"

ls -lh "$IPA_PATH"
