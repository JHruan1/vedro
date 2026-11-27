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
/// instead of spawning a new Dart Isolate + `DynamicLibrary.open` on every single RPC.
/// Multiplexes concurrent calls over a single shared reply port and detects unexpected exit.
class _FfiWorker {
  _FfiWorker._(
    this._isolate,
    this._sendPort,
    this._replyPort,
    this._exitPort,
    this._errorPort,
  ) {
    _replyPort.listen(_onReply);
    _exitPort.listen((_) => _handleUnexpectedExit('FFI worker isolate exited unexpectedly'));
    _errorPort.listen((err) => _handleUnexpectedExit('FFI worker isolate error: $err'));
  }

  final Isolate _isolate;
  final SendPort _sendPort;
  final ReceivePort _replyPort;
  final ReceivePort _exitPort;
  final ReceivePort _errorPort;
  final Map<int, Completer<dynamic>> _pending = <int, Completer<dynamic>>{};
  int _nextId = 1;
  bool _closed = false;
  Timer? _killTimer;

  bool get isAlive => !_closed;

  static Future<_FfiWorker> spawn(String? libraryPath) async {
    final readyPort = ReceivePort();
    final replyPort = ReceivePort();
    final exitPort = ReceivePort();
    final errorPort = ReceivePort();
    Isolate? iso;
    try {
      iso = await Isolate.spawn(
        _workerMain,
        <String, dynamic>{
          'ready': readyPort.sendPort,
          'reply': replyPort.sendPort,
          'lib_path': libraryPath,
        },
        onExit: exitPort.sendPort,
        onError: errorPort.sendPort,
        errorsAreFatal: false,
      );
      final msg = await readyPort.first.timeout(const Duration(seconds: 15));
      if (msg is Map && msg['error'] != null) {
        iso.kill(priority: Isolate.immediate);
        replyPort.close();
        exitPort.close();
        errorPort.close();
        throw VedroCoreException(msg['error'].toString());
      }
      if (msg is SendPort) {
        return _FfiWorker._(iso, msg, replyPort, exitPort, errorPort);
      }
      iso.kill(priority: Isolate.immediate);
      replyPort.close();
      exitPort.close();
      errorPort.close();
      throw VedroCoreException('FFI worker failed to start');
    } catch (_) {
      iso?.kill(priority: Isolate.immediate);
      replyPort.close();
      exitPort.close();
      errorPort.close();
      rethrow;
    } finally {
      readyPort.close();
    }
  }

  void _onReply(dynamic msg) {
    if (msg is! Map) return;
    final id = msg['id'];
    if (id is! int) return;
    final completer = _pending.remove(id);
    if (completer == null || completer.isCompleted) return;
    final resp = msg['resp'];
    if (resp is Map) {
      if (resp['ok'] == true) {
        completer.complete(resp['data']);
      } else {
        completer.completeError(
          VedroCoreException(resp['error']?.toString() ?? 'Unknown Rust core error'),
        );
      }
      return;
    }
    completer.completeError(VedroCoreException('Invalid FFI worker response'));
  }

  void _handleUnexpectedExit(String reason) {
    _killTimer?.cancel();
    _killTimer = null;
    if (!_closed) {
      _closed = true;
    }
    _failAllPending(reason);
    _replyPort.close();
    _exitPort.close();
    _errorPort.close();
  }

  void _failAllPending(String reason) {
    if (_pending.isEmpty) return;
    final entries = List<Completer<dynamic>>.from(_pending.values);
    _pending.clear();
    final err = VedroCoreException(reason);
    for (final c in entries) {
      if (!c.isCompleted) {
        c.completeError(err);
      }
    }
  }

  Future<dynamic> call(int handleAddr, String method, Map<String, dynamic> params) {
    if (_closed) {
      return Future<dynamic>.error(VedroCoreException('FFI worker closed'));
    }
    final id = _nextId++;
    final completer = Completer<dynamic>();
    _pending[id] = completer;
    try {
      _sendPort.send(<String, dynamic>{
        'cmd': 'invoke',
        'id': id,
        'handle': handleAddr,
        'method': method,
        'params': params,
      });
    } catch (e) {
      _pending.remove(id);
      return Future<dynamic>.error(VedroCoreException('FFI worker send failed: $e'));
    }
    return completer.future;
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _failAllPending('FFI worker closed');
    try {
      _sendPort.send(const <String, dynamic>{'cmd': 'shutdown'});
    } catch (_) {}
    _replyPort.close();
    _errorPort.close();
    // Wait briefly for graceful shutdown; cancel fallback kill timer as soon as exitPort fires.
    _killTimer = Timer(const Duration(milliseconds: 500), () {
      _killTimer = null;
      try {
        _isolate.kill(priority: Isolate.beforeNextEvent);
      } catch (_) {}
      _exitPort.close();
    });
  }
}

void _workerMain(Map<String, dynamic> initArgs) {
  final readyPort = initArgs['ready'] as SendPort;
  final replyPort = initArgs['reply'] as SendPort;
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
      final id = msg['id'] as int;
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
          replyPort.send(<String, dynamic>{
            'id': id,
            'resp': const <String, dynamic>{'ok': false, 'error': 'Null FFI response'},
          });
          return;
        }
        final raw = resultPtr.toDartString();
        final decoded = jsonDecode(raw);
        replyPort.send(<String, dynamic>{'id': id, 'resp': decoded});
      } catch (e) {
        replyPort.send(<String, dynamic>{
          'id': id,
          'resp': <String, dynamic>{'ok': false, 'error': e.toString()},
        });
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
/// lock-free `proxySpeedBps`, automatic dead-worker respawn, and ref-counted safe shutdown).
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
        String detail = 'vedro_init returned null handle';
        final errFn = bindings.lastInitError;
        if (errFn != null) {
          final errPtr = errFn();
          if (errPtr != nullptr) {
            try {
              final msg = errPtr.toDartString().trim();
              if (msg.isNotEmpty) {
                detail = msg;
              }
            } finally {
              bindings.freeString(errPtr);
            }
          }
        }
        throw VedroCoreException(detail);
      }
      return VedroFfiBridge._(bindings, handle, libraryPath);
    } finally {
      if (pathPtr != nullptr) {
        calloc.free(pathPtr);
      }
    }
  }

  Future<List<_FfiWorker>> _ensurePool() {
    final existing = _workers;
    if (existing != null) return Future.value(existing);
    final inflight = _poolInitFuture;
    if (inflight != null) return inflight;

    final spawned = <_FfiWorker>[];
    final future = () async {
      try {
        final pool = await Future.wait(
          List.generate(_poolSize, (_) async {
            final w = await _FfiWorker.spawn(_libraryPath);
            spawned.add(w);
            return w;
          }),
        );
        if (_disposed) {
          for (final w in pool) {
            w.close();
          }
          throw VedroCoreException('VedroFfiBridge already disposed');
        }
        _workers = pool;
        return pool;
      } catch (_) {
        for (final w in spawned) {
          w.close();
        }
        _poolInitFuture = null;
        rethrow;
      }
    }();
    _poolInitFuture = future;
    return future;
  }

  Future<_FfiWorker> _acquireWorker() async {
    final pool = _workers ?? await _ensurePool();
    if (_disposed || _handle == nullptr) {
      throw VedroCoreException('VedroFfiBridge already disposed');
    }
    final slot = _rr++ % pool.length;
    var worker = pool[slot];
    if (!worker.isAlive) {
      final replacement = await _FfiWorker.spawn(_libraryPath);
      if (_disposed || _handle == nullptr) {
        replacement.close();
        throw VedroCoreException('VedroFfiBridge already disposed');
      }
      if (identical(_workers, pool)) {
        pool[slot] = replacement;
      }
      worker = replacement;
    }
    return worker;
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
      final existing = _workers;
      final _FfiWorker worker;
      if (existing != null) {
        final slot = _rr++ % existing.length;
        worker = existing[slot].isAlive ? existing[slot] : await _acquireWorker();
      } else {
        worker = await _acquireWorker();
      }
      if (_disposed || _handle == nullptr) {
        throw VedroCoreException('VedroFfiBridge already disposed');
      }
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
