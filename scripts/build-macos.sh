#!/usr/bin/env bash
set -euo pipefail

# Build Universal macOS binary (Apple Silicon arm64 + Intel x86_64) for Rust core (`libvedro_ffi.dylib`),
# bundle into Vedro.app, and package a ready-to-install DMG into dist/.

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${VEDRO_VERSION:-$(awk -F': *' '/^version:/{print $2; exit}' "$ROOT_DIR/app/pubspec.yaml" | cut -d'+' -f1 | tr -d '\r')}"
VERSION="${VERSION#v}"
OUT_DIR="$ROOT_DIR/app/macos/Frameworks"
DIST_DIR="$ROOT_DIR/dist"
mkdir -p "$OUT_DIR" "$DIST_DIR"

cd "$ROOT_DIR"
export MACOSX_DEPLOYMENT_TARGET=12.0
echo "==> Building Rust vedro-ffi universal dylib (arm64 + x86_64, min macOS $MACOSX_DEPLOYMENT_TARGET)..."
cargo build --release -p vedro-ffi --target aarch64-apple-darwin
cargo build --release -p vedro-ffi --target x86_64-apple-darwin

lipo -create \
  "$ROOT_DIR/target/aarch64-apple-darwin/release/libvedro_ffi.dylib" \
  "$ROOT_DIR/target/x86_64-apple-darwin/release/libvedro_ffi.dylib" \
  -output "$OUT_DIR/libvedro_ffi.dylib"

install_name_tool -id "@rpath/libvedro_ffi.dylib" "$OUT_DIR/libvedro_ffi.dylib"
ls -lh "$OUT_DIR/libvedro_ffi.dylib"

echo "==> Building Flutter macOS release app..."
cd "$ROOT_DIR/app"
flutter pub get
flutter build macos --release

APP_BUNDLE="$ROOT_DIR/app/build/macos/Build/Products/Release/Vedro.app"
mkdir -p "$APP_BUNDLE/Contents/Frameworks"
cp -f "$OUT_DIR/libvedro_ffi.dylib" "$APP_BUNDLE/Contents/Frameworks/libvedro_ffi.dylib"
# Inside-out ad-hoc signing that preserves Release.entitlements and keeps nested framework seals valid
codesign --force --sign - "$APP_BUNDLE/Contents/Frameworks/libvedro_ffi.dylib"
codesign --force --entitlements "$ROOT_DIR/app/macos/Runner/Release.entitlements" --sign - "$APP_BUNDLE"
codesign --verify --deep --strict "$APP_BUNDLE"
lipo -info "$APP_BUNDLE/Contents/MacOS/Vedro" "$APP_BUNDLE/Contents/Frameworks/libvedro_ffi.dylib"

echo "==> Packaging macOS DMG..."
DMG_STAGE="$(mktemp -d)"
cp -R "$APP_BUNDLE" "$DMG_STAGE/Vedro.app"
ln -s /Applications "$DMG_STAGE/Applications"
DMG_PATH="$DIST_DIR/vedro-v${VERSION}-macos-universal.dmg"
hdiutil create -volname "Vedro" -srcfolder "$DMG_STAGE" -ov -format UDZO "$DMG_PATH"
rm -rf "$DMG_STAGE"

ls -lh "$DMG_PATH"
