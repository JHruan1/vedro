#!/usr/bin/env bash
set -euo pipefail

# Cross-compile Rust core (`libprism_ffi.so`) for Android ABIs (arm64-v8a, armeabi-v7a, x86_64)
# and build a release Flutter APK / AAB.
# Prerequisites: Android NDK, `cargo-ndk`, Flutter SDK, rustup Android targets.

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
JNI_DIR="$ROOT_DIR/app/android/app/src/main/jniLibs"
mkdir -p "$JNI_DIR"

echo "==> Building Rust prism-ffi for Android (arm64-v8a, armeabi-v7a, x86_64)..."
cd "$ROOT_DIR"
cargo ndk \
  -t arm64-v8a \
  -t armeabi-v7a \
  -t x86_64 \
  -o "$JNI_DIR" \
  build --release -p prism-ffi

echo "==> Building Flutter Android APK (split per ABI)..."
cd "$ROOT_DIR/app"
flutter pub get
flutter build apk --release --split-per-abi
echo "Done! APKs located in: $ROOT_DIR/app/build/app/outputs/flutter-apk/"
