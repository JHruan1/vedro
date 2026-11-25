import 'dart:async';
import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'vedro_bindings.dart';

class VedroCoreException implements Exception {
  VedroCoreException(this.message);
  final String message;

  @override
  String toString() => 'VedroCoreException: $message';
}

/// Abstract client interface so the UI runs natively over Rust `dart:ffi`
/// AND supports deterministic mock implementations in Flutter widget tests.
abstract class VedroCoreClient {
  Future<dynamic> invoke(String method, [Map<String, dynamic> params = const {}]);
  List<Map<String, dynamic>> pollEvents();
  String get coreVersion;
  void dispose();
}

/// Production FFI bridge calling our Rust `VedroRuntime` directly.
class VedroFfiBridge implements VedroCoreClient {
  VedroFfiBridge._(this._bindings, this._handle);

  final VedroNativeBindings _bindings;
  Pointer<VedroRuntime> _handle;
  bool _disposed = false;

  static VedroFfiBridge open({String? dbPath, String? libraryPath}) {
    final bindings = VedroNativeBindings.load(overridePath: libraryPath);
    final pathPtr = dbPath == null ? nullptr : dbPath.toNativeUtf8();
    try {
      final handle = bindings.init(pathPtr);
      if (handle == nullptr) {
        throw VedroCoreException('vedro_init returned null handle');
      }
      return VedroFfiBridge._(bindings, handle);
    } finally {
      if (pathPtr != nullptr) {
        calloc.free(pathPtr);
      }
    }
  }

  @override
  String get coreVersion => _bindings.version().toDartString();

  @override
  Future<dynamic> invoke(String method, [Map<String, dynamic> params = const {}]) async {
    if (_disposed) {
      throw VedroCoreException('VedroFfiBridge already disposed');
    }
    final methodPtr = method.toNativeUtf8();
    final paramsPtr = jsonEncode(params).toNativeUtf8();
    Pointer<Utf8> resultPtr = nullptr;
    try {
      resultPtr = _bindings.invoke(_handle, methodPtr, paramsPtr);
      final raw = resultPtr.toDartString();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      if (decoded['ok'] == true) {
        return decoded['data'];
      }
      throw VedroCoreException(decoded['error']?.toString() ?? 'Unknown Rust core error');
    } finally {
      calloc.free(methodPtr);
      calloc.free(paramsPtr);
      if (resultPtr != nullptr) {
        _bindings.freeString(resultPtr);
      }
    }
  }

  @override
  List<Map<String, dynamic>> pollEvents() {
    if (_disposed) return const [];
    final ptr = _bindings.pollEvents(_handle);
    try {
      final raw = ptr.toDartString();
      final list = jsonDecode(raw) as List<dynamic>;
      return list.whereType<Map<String, dynamic>>().toList();
    } finally {
      _bindings.freeString(ptr);
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _bindings.destroy(_handle);
    _handle = nullptr;
  }
}
