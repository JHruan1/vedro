import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

/// Opaque handle matching `VedroRuntime` in `core/vedro-ffi/include/vedro_ffi.h`.
final class VedroRuntime extends Opaque {}

typedef VedroInitNative = Pointer<VedroRuntime> Function(Pointer<Utf8> dbPath);
typedef VedroInitDart = Pointer<VedroRuntime> Function(Pointer<Utf8> dbPath);

typedef VedroLastInitErrorNative = Pointer<Utf8> Function();
typedef VedroLastInitErrorDart = Pointer<Utf8> Function();

typedef VedroInvokeNative = Pointer<Utf8> Function(
  Pointer<VedroRuntime> rt,
  Pointer<Utf8> method,
  Pointer<Utf8> paramsJson,
);
typedef VedroInvokeDart = Pointer<Utf8> Function(
  Pointer<VedroRuntime> rt,
  Pointer<Utf8> method,
  Pointer<Utf8> paramsJson,
);

typedef VedroPollEventsNative = Pointer<Utf8> Function(Pointer<VedroRuntime> rt);
typedef VedroPollEventsDart = Pointer<Utf8> Function(Pointer<VedroRuntime> rt);

typedef VedroProxySpeedBpsNative = Uint64 Function(Pointer<VedroRuntime> rt);
typedef VedroProxySpeedBpsDart = int Function(Pointer<VedroRuntime> rt);

typedef VedroFaceDetectRawNative = Pointer<Utf8> Function(
  Pointer<VedroRuntime> rt,
  Pointer<Utf8> modelPath,
  Pointer<Uint8> pixelsPtr,
  IntPtr pixelsLen,
  IntPtr width,
  IntPtr height,
  IntPtr rowStride,
  Uint8 isBgra,
  IntPtr inferW,
  IntPtr inferH,
  Float scoreThreshold,
  IntPtr maxFaces,
);
typedef VedroFaceDetectRawDart = Pointer<Utf8> Function(
  Pointer<VedroRuntime> rt,
  Pointer<Utf8> modelPath,
  Pointer<Uint8> pixelsPtr,
  int pixelsLen,
  int width,
  int height,
  int rowStride,
  int isBgra,
  int inferW,
  int inferH,
  double scoreThreshold,
  int maxFaces,
);

typedef VedroVersionNative = Pointer<Utf8> Function();
typedef VedroVersionDart = Pointer<Utf8> Function();

typedef VedroFreeStringNative = Void Function(Pointer<Utf8> ptr);
typedef VedroFreeStringDart = void Function(Pointer<Utf8> ptr);

typedef VedroDestroyNative = Void Function(Pointer<VedroRuntime> rt);
typedef VedroDestroyDart = void Function(Pointer<VedroRuntime> rt);

/// Direct zero-overhead C-ABI bindings to our compiled Rust core (`libvedro_ffi`).
class VedroNativeBindings {
  VedroNativeBindings(DynamicLibrary lib)
      : init = lib.lookupFunction<VedroInitNative, VedroInitDart>('vedro_init'),
        lastInitError = _lookupLastInitErrorOptional(lib),
        invoke = lib.lookupFunction<VedroInvokeNative, VedroInvokeDart>('vedro_invoke'),
        pollEvents = lib.lookupFunction<VedroPollEventsNative, VedroPollEventsDart>(
          'vedro_poll_events',
        ),
        proxySpeedBps = _lookupSpeedOptional(lib),
        faceDetectRaw = _lookupFaceDetectRawOptional(lib),
        version = lib.lookupFunction<VedroVersionNative, VedroVersionDart>('vedro_version'),
        freeString = lib.lookupFunction<VedroFreeStringNative, VedroFreeStringDart>(
          'vedro_free_string',
        ),
        destroy = lib.lookupFunction<VedroDestroyNative, VedroDestroyDart>('vedro_destroy');

  static VedroLastInitErrorDart? _lookupLastInitErrorOptional(DynamicLibrary lib) {
    try {
      return lib.lookupFunction<VedroLastInitErrorNative, VedroLastInitErrorDart>(
        'vedro_last_init_error',
      );
    } catch (_) {
      return null;
    }
  }

  static VedroProxySpeedBpsDart? _lookupSpeedOptional(DynamicLibrary lib) {
    try {
      return lib.lookupFunction<VedroProxySpeedBpsNative, VedroProxySpeedBpsDart>(
        'vedro_proxy_speed_bps',
      );
    } catch (_) {
      return null;
    }
  }

  static VedroFaceDetectRawDart? _lookupFaceDetectRawOptional(DynamicLibrary lib) {
    try {
      return lib.lookupFunction<VedroFaceDetectRawNative, VedroFaceDetectRawDart>(
        'vedro_face_detect_raw',
      );
    } catch (_) {
      return null;
    }
  }

  final VedroInitDart init;
  final VedroLastInitErrorDart? lastInitError;
  final VedroInvokeDart invoke;
  final VedroPollEventsDart pollEvents;
  final VedroProxySpeedBpsDart? proxySpeedBps;
  final VedroFaceDetectRawDart? faceDetectRaw;
  final VedroVersionDart version;
  final VedroFreeStringDart freeString;
  final VedroDestroyDart destroy;

  /// Dynamically load `libvedro_ffi` for Android, iOS, macOS, Windows, or Linux.
  /// Release builds strictly load from the signed app bundle / executable directory.
  static VedroNativeBindings load({String? overridePath}) {
    if (overridePath != null && overridePath.isNotEmpty) {
      return VedroNativeBindings(DynamicLibrary.open(overridePath));
    }
    if (Platform.isIOS) {
      return VedroNativeBindings(DynamicLibrary.process());
    }
    if (Platform.isMacOS) {
      return VedroNativeBindings(_openFirst([
        '@executable_path/../Frameworks/libvedro_ffi.dylib',
        'libvedro_ffi.dylib',
      ]));
    }
    if (Platform.isWindows) {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      return VedroNativeBindings(_openFirst([
        '$exeDir\\vedro_ffi.dll',
        '$exeDir\\libvedro_ffi.dll',
        if (!kReleaseMode) 'vedro_ffi.dll',
        if (!kReleaseMode) 'libvedro_ffi.dll',
      ]));
    }
    if (Platform.isAndroid) {
      return VedroNativeBindings(DynamicLibrary.open('libvedro_ffi.so'));
    }
    // Linux desktop / test environment
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final envPath = kReleaseMode ? null : Platform.environment['VEDRO_FFI_PATH'];
    return VedroNativeBindings(_openFirst([
      if (envPath != null && envPath.isNotEmpty) envPath,
      '$exeDir/lib/libvedro_ffi.so',
      'libvedro_ffi.so',
      if (!kReleaseMode) '../target/release/libvedro_ffi.so',
      if (!kReleaseMode) '../target/debug/libvedro_ffi.so',
      if (!kReleaseMode) 'target/release/libvedro_ffi.so',
      if (!kReleaseMode) 'target/debug/libvedro_ffi.so',
    ]));
  }

  static DynamicLibrary _openFirst(List<String> candidates) {
    Object? lastError;
    for (final path in candidates) {
      try {
        return DynamicLibrary.open(path);
      } catch (e) {
        lastError = e;
      }
    }
    throw StateError('Failed to load libvedro_ffi ($candidates): $lastError');
  }
}
