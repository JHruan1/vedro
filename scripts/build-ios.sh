#!/usr/bin/env bash
set -euo pipefail

# Cross-compile Rust core (`libprism_ffi.a`) into an Apple XCFramework for iOS device + simulator
# and build the Flutter iOS release archive.
# Run on macOS with Xcode & `rustup target add aarch64-apple-ios aarch64-apple-ios-sim`.

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="$ROOT_DIR/app/ios/Frameworks"
mkdir -p "$OUT_DIR"

cd "$ROOT_DIR"
echo "==> Building Rust prism-ffi for iOS (aarch64-apple-ios + aarch64-apple-ios-sim)..."
cargo build --release -p prism-ffi --target aarch64-apple-ios
cargo build --release -p prism-ffi --target aarch64-apple-ios-sim

rm -rf "$OUT_DIR/PrismFfi.xcframework"
xcodebuild -create-xcframework \
  -library "$ROOT_DIR/target/aarch64-apple-ios/release/libprism_ffi.a" \
  -headers "$ROOT_DIR/core/prism-ffi/include" \
  -library "$ROOT_DIR/target/aarch64-apple-ios-sim/release/libprism_ffi.a" \
  -headers "$ROOT_DIR/core/prism-ffi/include" \
  -output "$OUT_DIR/PrismFfi.xcframework"

echo "==> Building Flutter iOS release..."
cd "$ROOT_DIR/app"
flutter pub get
flutter build ios --release --no-codesign
echo "Done! iOS bundle + PrismFfi.xcframework ready."
