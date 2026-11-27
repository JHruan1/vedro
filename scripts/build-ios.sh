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
export IPHONEOS_DEPLOYMENT_TARGET=15.0
echo "==> Building Rust vedro-ffi for iOS (aarch64-apple-ios, min iOS $IPHONEOS_DEPLOYMENT_TARGET)..."
cargo build --release -p vedro-ffi --target aarch64-apple-ios

cp -f "$ROOT_DIR/target/aarch64-apple-ios/release/libvedro_ffi.a" "$OUT_DIR/libvedro_ffi.a"
ls -lh "$OUT_DIR/libvedro_ffi.a"

# Ensure Release.xcconfig force-loads libvedro_ffi.a AND pins every vedro_* FFI symbol via -u
# so ld64 -dead_strip NEVER drops them (required for Dart DynamicLibrary.process() dlsym lookups!)
XCCONFIG="$ROOT_DIR/app/ios/Flutter/Release.xcconfig"
if ! grep -q "libvedro_ffi.a" "$XCCONFIG"; then
  printf '\nOTHER_LDFLAGS = $(inherited) -force_load $(PROJECT_DIR)/Frameworks/libvedro_ffi.a -Wl,-u,_vedro_init -Wl,-u,_vedro_invoke -Wl,-u,_vedro_poll_events -Wl,-u,_vedro_proxy_speed_bps -Wl,-u,_vedro_version -Wl,-u,_vedro_free_string -Wl,-u,_vedro_destroy\n' >> "$XCCONFIG"
elif ! grep -q "_vedro_init" "$XCCONFIG"; then
  printf '\nOTHER_LDFLAGS = $(inherited) -Wl,-u,_vedro_init -Wl,-u,_vedro_invoke -Wl,-u,_vedro_poll_events -Wl,-u,_vedro_proxy_speed_bps -Wl,-u,_vedro_version -Wl,-u,_vedro_free_string -Wl,-u,_vedro_destroy\n' >> "$XCCONFIG"
fi

echo "==> Building Flutter iOS release (no-codesign)..."
cd "$ROOT_DIR/app"
flutter pub get
flutter build ios --release --no-codesign

echo "==> Verifying exported Rust FFI symbols in iOS Runner binary..."
RUNNER_BIN="$ROOT_DIR/app/build/ios/iphoneos/Runner.app/Runner"
for sym in _vedro_init _vedro_invoke _vedro_poll_events _vedro_proxy_speed_bps _vedro_version _vedro_free_string _vedro_destroy; do
  if ! nm -gU "$RUNNER_BIN" | grep -q " ${sym}$"; then
    echo "ERROR: Missing exported FFI symbol ${sym} in iOS Runner binary!" >&2
    exit 1
  fi
done
echo "All 7 vedro_* FFI symbols verified present in iOS Runner binary."

echo "==> Packaging unsigned IPA for TrollStore / Sideloadly / AltStore..."
STAGE_DIR="$(mktemp -d)"
mkdir -p "$STAGE_DIR/Payload"
cp -R "$ROOT_DIR/app/build/ios/iphoneos/Runner.app" "$STAGE_DIR/Payload/"
IPA_PATH="$DIST_DIR/vedro-v${VERSION}-ios-unsigned.ipa"
rm -f "$IPA_PATH"
(cd "$STAGE_DIR" && zip -qry "$IPA_PATH" Payload)
rm -rf "$STAGE_DIR"

ls -lh "$IPA_PATH"
