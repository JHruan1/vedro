#!/usr/bin/env bash
set -euo pipefail

# Cross-compile Rust core (`libvedro_ffi.a`) for Apple tvOS arm64 (`aarch64-apple-tvos`),
# generate the native SwiftUI tvOS Xcode project via xcodegen, build an unsigned appletvos
# Release bundle, and package an installable unsigned IPA into dist/.

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${VEDRO_VERSION:-$(awk -F': *' '/^version:/{print $2; exit}' "$ROOT_DIR/app/pubspec.yaml" | cut -d'+' -f1 | tr -d '\r')}"
BUILD_NUM="${VEDRO_BUILD_NUMBER:-$(awk -F': *' '/^version:/{print $2; exit}' "$ROOT_DIR/app/pubspec.yaml" | cut -d'+' -f2 | tr -d '\r')}"
VERSION="${VERSION#v}"
BUILD_NUM="${BUILD_NUM:-1}"
TVOS_DIR="$ROOT_DIR/tvos"
VENDOR_DIR="$TVOS_DIR/VedroTV/Vendor"
DIST_DIR="$ROOT_DIR/dist"
mkdir -p "$VENDOR_DIR" "$DIST_DIR"

cd "$ROOT_DIR"
export TVOS_DEPLOYMENT_TARGET=16.0
export SDKROOT="$(xcrun --sdk appletvos --show-sdk-path)"
export CC_aarch64_apple_tvos="$(xcrun --sdk appletvos --find clang)"
export AR_aarch64_apple_tvos="$(xcrun --sdk appletvos --find ar)"
export CFLAGS_aarch64_apple_tvos="-arch arm64 -mtvos-version-min=${TVOS_DEPLOYMENT_TARGET} -isysroot ${SDKROOT}"

echo "==> Building Rust vedro-ffi for tvOS (aarch64-apple-tvos, min tvOS $TVOS_DEPLOYMENT_TARGET)..."
cargo +nightly build --release -p vedro-ffi \
  --target aarch64-apple-tvos \
  -Z build-std=std,panic_abort

cp -f "$ROOT_DIR/target/aarch64-apple-tvos/release/libvedro_ffi.a" "$VENDOR_DIR/libvedro_ffi.a"
cp -f "$ROOT_DIR/core/vedro-ffi/include/vedro_ffi.h" "$VENDOR_DIR/vedro_ffi.h"
ls -lh "$VENDOR_DIR/libvedro_ffi.a"

echo "==> Generating VedroTV.xcodeproj with xcodegen..."
cd "$TVOS_DIR"
xcodegen generate --spec "$TVOS_DIR/project.yml"

DERIVED_DIR="$(mktemp -d)"
trap 'rm -rf "$DERIVED_DIR"' EXIT

echo "==> Building VedroTV Release (appletvos, unsigned)..."
xcodebuild \
  -project "$TVOS_DIR/VedroTV.xcodeproj" \
  -scheme VedroTV \
  -sdk appletvos \
  -configuration Release \
  -derivedDataPath "$DERIVED_DIR" \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_NUM" \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  build

APP_BUNDLE="$DERIVED_DIR/Build/Products/Release-appletvos/VedroTV.app"
if [ ! -d "$APP_BUNDLE" ]; then
  echo "ERROR: VedroTV.app not found at $APP_BUNDLE" >&2
  exit 1
fi

echo "==> Verifying exported Rust FFI symbols in VedroTV binary..."
TV_BIN="$APP_BUNDLE/VedroTV"
for sym in _vedro_init _vedro_last_init_error _vedro_invoke _vedro_poll_events _vedro_proxy_speed_bps _vedro_version _vedro_free_string _vedro_destroy; do
  if ! nm -gU "$TV_BIN" | grep -q " ${sym}$"; then
    echo "ERROR: Missing exported FFI symbol ${sym} in VedroTV binary!" >&2
    exit 1
  fi
done
echo "All 8 vedro_* FFI symbols verified present in VedroTV binary."

echo "==> Packaging unsigned tvOS IPA..."
STAGE_DIR="$(mktemp -d)"
mkdir -p "$STAGE_DIR/Payload"
cp -R "$APP_BUNDLE" "$STAGE_DIR/Payload/"
IPA_PATH="$DIST_DIR/vedro-v${VERSION}-tvos-unsigned.ipa"
rm -f "$IPA_PATH"
(cd "$STAGE_DIR" && zip -qry "$IPA_PATH" Payload)
rm -rf "$STAGE_DIR"

ls -lh "$IPA_PATH"
