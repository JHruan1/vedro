#!/usr/bin/env bash
set -euo pipefail

# Cross-compile Rust core (`libvedro_ffi.so`) for Android ABIs (arm64-v8a, armeabi-v7a, x86_64)
# and build release Flutter APKs (split-per-abi + universal) into dist/.

export PATH="$HOME/.cargo/bin:/opt/flutter/bin:$PATH"
if [ -z "${ANDROID_HOME:-}" ]; then
  if [ -d "/opt/android-sdk" ]; then
    export ANDROID_HOME="/opt/android-sdk"
  elif [ -d "/usr/local/lib/android/sdk" ]; then
    export ANDROID_HOME="/usr/local/lib/android/sdk"
  fi
fi
export ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
if [ -z "${ANDROID_NDK_HOME:-}" ] && [ -d "${ANDROID_HOME:-}/ndk" ]; then
  export ANDROID_NDK_HOME="$(ls -d "${ANDROID_HOME}/ndk/"* | sort -V | tail -n 1)"
fi

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${VEDRO_VERSION:-$(awk -F': *' '/^version:/{print $2; exit}' "$ROOT_DIR/app/pubspec.yaml" | cut -d'+' -f1 | tr -d '\r')}"
VERSION="${VERSION#v}"
JNI_DIR="$ROOT_DIR/app/android/app/src/main/jniLibs"
DIST_DIR="$ROOT_DIR/dist"
mkdir -p "$JNI_DIR" "$DIST_DIR"

echo "==> Building Rust vedro-ffi for Android (NDK: ${ANDROID_NDK_HOME:-auto}, 16KB page aligned)..."
cd "$ROOT_DIR"
export CARGO_TARGET_AARCH64_LINUX_ANDROID_RUSTFLAGS="-C link-arg=-Wl,-z,max-page-size=16384"
export CARGO_TARGET_X86_64_LINUX_ANDROID_RUSTFLAGS="-C link-arg=-Wl,-z,max-page-size=16384"
cargo ndk \
  -P 24 \
  -t arm64-v8a \
  -t armeabi-v7a \
  -t x86_64 \
  -o "$JNI_DIR" \
  build --release -p vedro-ffi

ls -lh "$JNI_DIR"/arm64-v8a/libvedro_ffi.so "$JNI_DIR"/armeabi-v7a/libvedro_ffi.so "$JNI_DIR"/x86_64/libvedro_ffi.so

echo "==> Building Flutter Android release APKs..."
cd "$ROOT_DIR/app"
flutter pub get
flutter build apk --release --split-per-abi
flutter build apk --release

cp -f "$ROOT_DIR/app/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk" "$DIST_DIR/vedro-v${VERSION}-android-arm64-v8a.apk"
cp -f "$ROOT_DIR/app/build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk" "$DIST_DIR/vedro-v${VERSION}-android-armeabi-v7a.apk"
cp -f "$ROOT_DIR/app/build/app/outputs/flutter-apk/app-x86_64-release.apk" "$DIST_DIR/vedro-v${VERSION}-android-x86_64.apk"
cp -f "$ROOT_DIR/app/build/app/outputs/flutter-apk/app-release.apk" "$DIST_DIR/vedro-v${VERSION}-android-universal.apk"

ls -lh "$DIST_DIR"/vedro-v"${VERSION}"-android-*.apk
