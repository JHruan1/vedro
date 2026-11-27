import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';

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
  int get proxySpeedBps => 0;
  String get coreVersion;
  void dispose();
}

/// Persistent background FFI worker isolate so `VedroNativeBindings` is loaded ONCE
/// instead of spawning a new Dart Isolate + `DynamicLibrary.open` on every single RPC!
class _FfiWorker {
  _FfiWorker._(this._isolate, this._sendPort, this._exitPort);

  final Isolate _isolate;
  final SendPort _sendPort;
  final ReceivePort _exitPort;
  bool _closed = false;

  static Future<_FfiWorker> spawn(String? libraryPath) async {
    final readyPort = ReceivePort();
    final exitPort = ReceivePort();
    Isolate? iso;
    try {
      iso = await Isolate.spawn(
        _workerMain,
        <String, dynamic>{
          'ready': readyPort.sendPort,
          'lib_path': libraryPath,
        },
        onExit: exitPort.sendPort,
      );
      final msg = await readyPort.first.timeout(const Duration(seconds: 15));
      if (msg is Map && msg['error'] != null) {
        iso.kill(priority: Isolate.immediate);
        exitPort.close();
        throw VedroCoreException(msg['error'].toString());
      }
      if (msg is SendPort) {
        return _FfiWorker._(iso, msg, exitPort);
      }
      iso.kill(priority: Isolate.immediate);
      exitPort.close();
      throw VedroCoreException('FFI worker failed to start');
    } catch (_) {
      iso?.kill(priority: Isolate.immediate);
      exitPort.close();
      rethrow;
    } finally {
      readyPort.close();
    }
  }

  Future<dynamic> call(int handleAddr, String method, Map<String, dynamic> params) async {
    if (_closed) {
      throw VedroCoreException('FFI worker closed');
    }
    final reply = ReceivePort();
    try {
      _sendPort.send(<String, dynamic>{
        'cmd': 'invoke',
        'handle': handleAddr,
        'method': method,
        'params': params,
        'reply': reply.sendPort,
      });
      final resp = await reply.first;
      if (resp is Map) {
        if (resp['ok'] == true) {
          return resp['data'];
        }
        throw VedroCoreException(resp['error']?.toString() ?? 'Unknown Rust core error');
      }
      throw VedroCoreException('Invalid FFI worker response');
    } finally {
      reply.close();
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    try {
      _sendPort.send(const <String, dynamic>{'cmd': 'shutdown'});
    } catch (_) {}
    _exitPort.close();
    // Give worker a brief window to finish cleanly; OS reclaims isolate on exit
    Future<void>.delayed(const Duration(milliseconds: 500), () {
      try {
        _isolate.kill(priority: Isolate.beforeNextEvent);
      } catch (_) {}
    });
  }
}

void _workerMain(Map<String, dynamic> initArgs) {
  final readyPort = initArgs['ready'] as SendPort;
  final libPath = initArgs['lib_path'] as String?;

  final VedroNativeBindings bindings;
  try {
    bindings = VedroNativeBindings.load(overridePath: libPath);
  } catch (e) {
    readyPort.send(<String, dynamic>{'error': e.toString()});
    return;
  }

  final inbox = ReceivePort();
  readyPort.send(inbox.sendPort);

  inbox.listen((msg) {
    if (msg is! Map) return;
    final cmd = msg['cmd'];
    if (cmd == 'shutdown') {
      inbox.close();
      return;
    }
    if (cmd == 'invoke') {
      final reply = msg['reply'] as SendPort;
      final handleAddr = msg['handle'] as int;
      final method = msg['method'] as String;
      final params = msg['params'];

      Pointer<Utf8> methodPtr = nullptr;
      Pointer<Utf8> paramsPtr = nullptr;
      Pointer<Utf8> resultPtr = nullptr;
      try {
        final paramsJson = jsonEncode(params);
        final handle = Pointer<VedroRuntime>.fromAddress(handleAddr);
        methodPtr = method.toNativeUtf8();
        paramsPtr = paramsJson.toNativeUtf8();
        resultPtr = bindings.invoke(handle, methodPtr, paramsPtr);
        if (resultPtr == nullptr) {
          reply.send(const <String, dynamic>{'ok': false, 'error': 'Null FFI response'});
          return;
        }
        final raw = resultPtr.toDartString();
        final decoded = jsonDecode(raw);
        reply.send(decoded);
      } catch (e) {
        reply.send(<String, dynamic>{'ok': false, 'error': e.toString()});
      } finally {
        if (methodPtr != nullptr) calloc.free(methodPtr);
        if (paramsPtr != nullptr) calloc.free(paramsPtr);
        if (resultPtr != nullptr) bindings.freeString(resultPtr);
      }
    }
  });
}

/// Production FFI bridge calling our Rust `VedroRuntime` asynchronously via a 2-worker
/// persistent Isolate pool (zero per-call isolate spawns, JSON encode/decode off UI thread,
/// lock-free `proxySpeedBps`, and ref-counted safe shutdown).
class VedroFfiBridge implements VedroCoreClient {
  VedroFfiBridge._(this._bindings, this._handle, this._libraryPath);

  static const int _poolSize = 2;

  final VedroNativeBindings _bindings;
  final String? _libraryPath;
  Pointer<VedroRuntime> _handle;
  bool _disposed = false;
  int _inFlight = 0;
  bool _destroyPending = false;
  int _rr = 0;
  List<_FfiWorker>? _workers;
  Future<List<_FfiWorker>>? _poolInitFuture;

  static VedroFfiBridge open({String? dbPath, String? libraryPath}) {
    final bindings = VedroNativeBindings.load(overridePath: libraryPath);
    Pointer<Utf8> pathPtr = nullptr;
    try {
      if (dbPath != null) {
        pathPtr = dbPath.toNativeUtf8();
      }
      final handle = bindings.init(pathPtr);
      if (handle == nullptr) {
        throw VedroCoreException('vedro_init returned null handle');
      }
      return VedroFfiBridge._(bindings, handle, libraryPath);
    } finally {
      if (pathPtr != nullptr) {
        calloc.free(pathPtr);
      }
    }
  }

  Future<List<_FfiWorker>> _ensurePool() {
    if (_workers != null) return Future.value(_workers!);
    return _poolInitFuture ??= Future.wait(
      List.generate(_poolSize, (_) => _FfiWorker.spawn(_libraryPath)),
    ).then((pool) {
      if (_disposed) {
        for (final w in pool) {
          w.close();
        }
        throw VedroCoreException('VedroFfiBridge already disposed');
      }
      _workers = pool;
      return pool;
    });
  }

  @override
  String get coreVersion {
    final ptr = _bindings.version();
    return ptr == nullptr ? '0.0.0' : ptr.toDartString();
  }

  @override
  int get proxySpeedBps {
    if (_disposed || _handle == nullptr) return 0;
    final fn = _bindings.proxySpeedBps;
    if (fn == null) return 0;
    return fn(_handle);
  }

  @override
  Future<dynamic> invoke(String method, [Map<String, dynamic> params = const {}]) async {
    if (_disposed || _handle == nullptr) {
      throw VedroCoreException('VedroFfiBridge already disposed');
    }
    _inFlight++;
    try {
      final pool = await _ensurePool();
      if (_disposed || _handle == nullptr) {
        throw VedroCoreException('VedroFfiBridge already disposed');
      }
      final worker = pool[_rr++ % pool.length];
      return await worker.call(_handle.address, method, params);
    } finally {
      _inFlight--;
      _maybeFinalizeDestroy();
    }
  }

  @override
  List<Map<String, dynamic>> pollEvents() {
    if (_disposed || _handle == nullptr) return const [];
    final ptr = _bindings.pollEvents(_handle);
    if (ptr == nullptr) return const [];
    try {
      final raw = ptr.toDartString();
      final list = jsonDecode(raw) as List<dynamic>;
      return list.whereType<Map<String, dynamic>>().toList();
    } catch (_) {
      return const [];
    } finally {
      _bindings.freeString(ptr);
    }
  }

  void _maybeFinalizeDestroy() {
    if (_destroyPending && _inFlight == 0 && _handle != nullptr) {
      final h = _handle;
      _handle = nullptr;
      _destroyPending = false;
      _bindings.destroy(h);
      final pool = _workers;
      _workers = null;
      if (pool != null) {
        for (final w in pool) {
          w.close();
        }
      }
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _destroyPending = true;
    _maybeFinalizeDestroy();
  }
}
