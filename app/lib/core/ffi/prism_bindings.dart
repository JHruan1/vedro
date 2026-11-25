import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// Opaque handle matching `PrismRuntime` in `core/prism-ffi/include/prism_ffi.h`.
final class PrismRuntime extends Opaque {}

typedef PrismInitNative = Pointer<PrismRuntime> Function(Pointer<Utf8> dbPath);
typedef PrismInitDart = Pointer<PrismRuntime> Function(Pointer<Utf8> dbPath);

typedef PrismInvokeNative = Pointer<Utf8> Function(
  Pointer<PrismRuntime> rt,
  Pointer<Utf8> method,
  Pointer<Utf8> paramsJson,
);
typedef PrismInvokeDart = Pointer<Utf8> Function(
  Pointer<PrismRuntime> rt,
  Pointer<Utf8> method,
  Pointer<Utf8> paramsJson,
);

typedef PrismPollEventsNative = Pointer<Utf8> Function(Pointer<PrismRuntime> rt);
typedef PrismPollEventsDart = Pointer<Utf8> Function(Pointer<PrismRuntime> rt);

typedef PrismVersionNative = Pointer<Utf8> Function();
typedef PrismVersionDart = Pointer<Utf8> Function();

typedef PrismFreeStringNative = Void Function(Pointer<Utf8> ptr);
typedef PrismFreeStringDart = void Function(Pointer<Utf8> ptr);

typedef PrismDestroyNative = Void Function(Pointer<PrismRuntime> rt);
typedef PrismDestroyDart = void Function(Pointer<PrismRuntime> rt);

/// Direct zero-overhead C-ABI bindings to our compiled Rust core (`libprism_ffi`).
class PrismNativeBindings {
  PrismNativeBindings(DynamicLibrary lib)
      : init = lib.lookupFunction<PrismInitNative, PrismInitDart>('prism_init'),
        invoke = lib.lookupFunction<PrismInvokeNative, PrismInvokeDart>('prism_invoke'),
        pollEvents = lib.lookupFunction<PrismPollEventsNative, PrismPollEventsDart>(
          'prism_poll_events',
        ),
        version = lib.lookupFunction<PrismVersionNative, PrismVersionDart>('prism_version'),
        freeString = lib.lookupFunction<PrismFreeStringNative, PrismFreeStringDart>(
          'prism_free_string',
        ),
        destroy = lib.lookupFunction<PrismDestroyNative, PrismDestroyDart>('prism_destroy');

  final PrismInitDart init;
  final PrismInvokeDart invoke;
  final PrismPollEventsDart pollEvents;
  final PrismVersionDart version;
  final PrismFreeStringDart freeString;
  final PrismDestroyDart destroy;

  /// Dynamically load `libprism_ffi` for Android, iOS, macOS, Windows, or Linux.
  static PrismNativeBindings load({String? overridePath}) {
    if (overridePath != null && overridePath.isNotEmpty) {
      return PrismNativeBindings(DynamicLibrary.open(overridePath));
    }
    if (Platform.isIOS) {
      return PrismNativeBindings(DynamicLibrary.process());
    }
    if (Platform.isMacOS) {
      return PrismNativeBindings(_openFirst([
        'libprism_ffi.dylib',
        '@executable_path/../Frameworks/libprism_ffi.dylib',
      ]));
    }
    if (Platform.isWindows) {
      return PrismNativeBindings(_openFirst([
        'prism_ffi.dll',
        'libprism_ffi.dll',
      ]));
    }
    if (Platform.isAndroid) {
      return PrismNativeBindings(DynamicLibrary.open('libprism_ffi.so'));
    }
    // Linux desktop / test environment
    return PrismNativeBindings(_openFirst([
      'libprism_ffi.so',
      '../target/release/libprism_ffi.so',
      '../target/debug/libprism_ffi.so',
      '/root/player/target/release/libprism_ffi.so',
      '/root/player/target/debug/libprism_ffi.so',
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
    throw StateError('Failed to load libprism_ffi ($candidates): $lastError');
  }
}
