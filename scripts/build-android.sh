#!/usr/bin/env bash
set -euo pipefail

# Cross-compile Rust core (`libprism_ffi.so`) for Android ABIs (arm64-v8a, armeabi-v7a, x86_64)
# and build release Flutter APKs (split-per-abi + universal) into dist/.

export PATH="/root/.cargo/bin:/opt/flutter/bin:$PATH"
export ANDROID_HOME="${ANDROID_HOME:-/opt/android-sdk}"
export ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-$ANDROID_HOME}"
export ANDROID_NDK_HOME="${ANDROID_NDK_HOME:-$ANDROID_HOME/ndk/27.0.12077973}"

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
JNI_DIR="$ROOT_DIR/app/android/app/src/main/jniLibs"
DIST_DIR="$ROOT_DIR/dist"
mkdir -p "$JNI_DIR" "$DIST_DIR"

echo "==> Building Rust prism-ffi for Android (arm64-v8a, armeabi-v7a, x86_64)..."
cd "$ROOT_DIR"
cargo ndk \
  -P 24 \
  -t arm64-v8a \
  -t armeabi-v7a \
  -t x86_64 \
  -o "$JNI_DIR" \
  build --release -p prism-ffi

ls -lh "$JNI_DIR"/arm64-v8a/libprism_ffi.so "$JNI_DIR"/armeabi-v7a/libprism_ffi.so "$JNI_DIR"/x86_64/libprism_ffi.so

echo "==> Building Flutter Android release APKs (split-per-abi)..."
cd "$ROOT_DIR/app"
flutter config --android-sdk "$ANDROID_HOME" >/dev/null 2>&1 || true
flutter pub get
flutter build apk --release --split-per-abi

cp -f "$ROOT_DIR/app/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk" "$DIST_DIR/prism-player-android-arm64-v8a.apk"
cp -f "$ROOT_DIR/app/build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk" "$DIST_DIR/prism-player-android-armeabi-v7a.apk"
cp -f "$ROOT_DIR/app/build/app/outputs/flutter-apk/app-x86_64-release.apk" "$DIST_DIR/prism-player-android-x86_64.apk"

echo "==> Done! Release APKs ready in $DIST_DIR:"
ls -lh "$DIST_DIR"/prism-player-android-*.apk
