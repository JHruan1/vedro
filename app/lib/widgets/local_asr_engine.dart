import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

/// On-demand downloadable local offline ASR model metadata (SenseVoice-Small INT8 + Silero VAD).
///
/// Runs completely offline on Android, iOS, macOS, Windows, and Linux via `sherpa_onnx`
/// in a persistent background Isolate (~10x realtime on modern mobile ARM64 CPUs with
/// 2 threads so playback stays 120fps and thermal load remains low).
class LocalAsrModelSpec {
  static const String id = 'sensevoice_int8';
  static const String displayName = 'SenseVoice-Small (INT8 多语种)';
  static const String languagesLabel = '中文 / 日语 / 英语 / 韩语 / 粤语（5 语合一 · 带标点）';
  static const int expectedTotalBytes = 239233841 + 320000 + 643854;

  static const String modelFileName = 'model.int8.onnx';
  static const String tokensFileName = 'tokens.txt';
  static const String vadFileName = 'silero_vad.onnx';

  static const String _repoPath =
      'csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17/resolve/main';

  static List<String> modelUrls({required bool preferChinaMirror}) => preferChinaMirror
      ? const [
          'https://hf-mirror.com/$_repoPath/$modelFileName',
          'https://huggingface.co/$_repoPath/$modelFileName',
        ]
      : const [
          'https://huggingface.co/$_repoPath/$modelFileName',
          'https://hf-mirror.com/$_repoPath/$modelFileName',
        ];

  static List<String> tokensUrls({required bool preferChinaMirror}) => preferChinaMirror
      ? const [
          'https://hf-mirror.com/$_repoPath/$tokensFileName',
          'https://huggingface.co/$_repoPath/$tokensFileName',
        ]
      : const [
          'https://huggingface.co/$_repoPath/$tokensFileName',
          'https://hf-mirror.com/$_repoPath/$tokensFileName',
        ];

  static const List<String> vadUrls = [
    'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/silero_vad.onnx',
  ];
}

/// Manages local offline ASR model downloads, storage stats, and persistent Isolate inference.
class LocalAsrManager extends ChangeNotifier {
  LocalAsrManager();

  static final LocalAsrManager instance = LocalAsrManager();

  bool isModelDownloaded = false;
  bool hasVadModel = false;
  int downloadedBytes = 0;
  String? modelDirPath;

  bool isDownloading = false;
  double downloadProgress = 0.0;
  String downloadStage = '';
  String? downloadError;

  HttpClient? _activeClient;
  bool _cancelRequested = false;

  // Persistent background Isolate so the 228 MB ONNX model is loaded ONCE per playback session
  // instead of reloading from disk on every 20-second audio slice!
  Isolate? _workerIsolate;
  SendPort? _workerSendPort;
  ReceivePort? _workerExitPort;
  String _loadedModelSig = '';
  Future<void>? _startingWorker;
  int _activeTranscriptions = 0;

  bool get isWorkerLoaded => _workerIsolate != null;
  bool get isTranscribing => _activeTranscriptions > 0;

  Future<Directory> _resolveModelDir() async {
    if (modelDirPath != null && modelDirPath!.isNotEmpty) {
      return Directory(modelDirPath!);
    }
    String base;
    try {
      final dir = await getApplicationSupportDirectory();
      base = dir.path;
    } catch (_) {
      base = Directory.systemTemp.path;
    }
    final dir = Directory('$base/asr_models/${LocalAsrModelSpec.id}');
    modelDirPath = dir.path;
    return dir;
  }

  Future<void> refreshStatus() async {
    final dir = await _resolveModelDir();
    final modelFile = File('${dir.path}/${LocalAsrModelSpec.modelFileName}');
    final tokensFile = File('${dir.path}/${LocalAsrModelSpec.tokensFileName}');
    final vadFile = File('${dir.path}/${LocalAsrModelSpec.vadFileName}');

    final modelOk = modelFile.existsSync() && modelFile.lengthSync() > 10 * 1024 * 1024;
    final tokensOk = tokensFile.existsSync() && tokensFile.lengthSync() > 1024;
    final vadOk = vadFile.existsSync() && vadFile.lengthSync() > 100 * 1024;

    var total = 0;
    if (modelFile.existsSync()) total += modelFile.lengthSync();
    if (tokensFile.existsSync()) total += tokensFile.lengthSync();
    if (vadFile.existsSync()) total += vadFile.lengthSync();

    isModelDownloaded = modelOk && tokensOk;
    hasVadModel = vadOk;
    downloadedBytes = total;
    notifyListeners();
  }

  void cancelDownload() {
    if (!isDownloading) return;
    _cancelRequested = true;
    try {
      _activeClient?.close(force: true);
    } catch (_) {}
    _activeClient = null;
  }

  Future<void> downloadModel({bool useChinaMirror = true}) async {
    if (isDownloading) return;
    isDownloading = true;
    _cancelRequested = false;
    downloadProgress = 0.0;
    downloadStage = '正在准备下载本地语音模型…';
    downloadError = null;
    notifyListeners();

    try {
      final dir = await _resolveModelDir();
      if (!dir.existsSync()) {
        await dir.create(recursive: true);
      }

      // 1. Download tokens.txt (~300 KB)
      downloadStage = '下载词表 (tokens.txt)…';
      notifyListeners();
      await _downloadWithMirrors(
        urls: LocalAsrModelSpec.tokensUrls(preferChinaMirror: useChinaMirror),
        destPath: '${dir.path}/${LocalAsrModelSpec.tokensFileName}',
        minBytes: 1024,
        onProgress: (_, __) {},
      );
      if (_cancelRequested) throw Exception('已取消下载');

      // 2. Download Silero VAD (~640 KB, best-effort — energy VAD fallback exists if blocked)
      downloadStage = '下载语音活动检测模型 (silero_vad.onnx)…';
      downloadProgress = 0.02;
      notifyListeners();
      try {
        await _downloadWithMirrors(
          urls: LocalAsrModelSpec.vadUrls,
          destPath: '${dir.path}/${LocalAsrModelSpec.vadFileName}',
          minBytes: 100 * 1024,
          onProgress: (_, __) {},
        );
      } catch (_) {
        // Non-fatal: pure-Dart RMS energy speech splitter works if Silero VAD is unreachable
      }
      if (_cancelRequested) throw Exception('已取消下载');

      // 3. Download SenseVoice-Small INT8 ONNX model (~228 MB) with live progress
      downloadStage = '下载 SenseVoice 语音模型…';
      notifyListeners();
      await _downloadWithMirrors(
        urls: LocalAsrModelSpec.modelUrls(preferChinaMirror: useChinaMirror),
        destPath: '${dir.path}/${LocalAsrModelSpec.modelFileName}',
        minBytes: 50 * 1024 * 1024,
        onProgress: (received, total) {
          final effTotal = total > 0 ? total : 239233841;
          final ratio = (received / effTotal).clamp(0.0, 1.0);
          final recvMb = (received / (1024 * 1024)).toStringAsFixed(1);
          final totMb = (effTotal / (1024 * 1024)).toStringAsFixed(1);
          downloadProgress = 0.03 + ratio * 0.97;
          downloadStage = '下载 SenseVoice 语音模型：$recvMb / $totMb MB';
          notifyListeners();
        },
      );

      downloadProgress = 1.0;
      downloadStage = '本地离线语音模型已就绪';
      await refreshStatus();
    } catch (e) {
      downloadError = e.toString().replaceFirst('Exception: ', '');
      downloadStage = '';
    } finally {
      _activeClient = null;
      isDownloading = false;
      notifyListeners();
    }
  }

  Future<void> deleteModel() async {
    await unloadEngine();
    final dir = await _resolveModelDir();
    if (dir.existsSync()) {
      await dir.delete(recursive: true);
    }
    downloadProgress = 0.0;
    downloadStage = '';
    downloadError = null;
    await refreshStatus();
  }

  Future<void> _downloadWithMirrors({
    required List<String> urls,
    required String destPath,
    required int minBytes,
    required void Function(int received, int total) onProgress,
  }) async {
    final destFile = File(destPath);
    if (destFile.existsSync() && destFile.lengthSync() >= minBytes) {
      return;
    }
    final partFile = File('$destPath.part');
    Object? lastErr;

    for (final rawUrl in urls) {
      if (_cancelRequested) throw Exception('已取消下载');
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 20);
      _activeClient = client;
      IOSink? sink;
      try {
        var uri = Uri.parse(rawUrl);
        HttpClientResponse? resp;
        for (var hop = 0; hop < 8; hop++) {
          if (uri.scheme.toLowerCase() != 'https') {
            throw Exception('拒绝非 HTTPS 模型下载地址: ${uri.scheme}');
          }
          final req = await client.getUrl(uri);
          req.followRedirects = false;
          req.headers.set(HttpHeaders.userAgentHeader, 'Vedro-ASR/0.4');
          final r = await req.close().timeout(const Duration(seconds: 25));
          if (r.isRedirect && r.headers.value(HttpHeaders.locationHeader) != null) {
            final loc = r.headers.value(HttpHeaders.locationHeader)!;
            await r.drain<void>();
            uri = uri.resolve(loc);
            continue;
          }
          resp = r;
          break;
        }
        if (resp == null || resp.statusCode < 200 || resp.statusCode >= 300) {
          throw Exception('HTTP ${resp?.statusCode ?? 0}');
        }

        final total = resp.contentLength;
        sink = partFile.openWrite(mode: FileMode.writeOnly);
        var received = 0;
        var lastEmitMs = 0;

        await for (final chunk in resp.timeout(const Duration(seconds: 30))) {
          if (_cancelRequested) {
            throw Exception('已取消下载');
          }
          sink.add(chunk);
          received += chunk.length;
          final nowMs = DateTime.now().millisecondsSinceEpoch;
          if (nowMs - lastEmitMs >= 180) {
            lastEmitMs = nowMs;
            onProgress(received, total);
          }
        }
        await sink.flush();
        await sink.close();
        sink = null;

        if (received < minBytes) {
          throw Exception('文件下载不完整 ($received B)');
        }
        onProgress(received, total);
        if (destFile.existsSync()) destFile.deleteSync();
        partFile.renameSync(destPath);
        return;
      } catch (e) {
        lastErr = e;
        try {
          await sink?.close();
        } catch (_) {}
        try {
          if (partFile.existsSync()) partFile.deleteSync();
        } catch (_) {}
        if (_cancelRequested) rethrow;
      } finally {
        client.close(force: true);
      }
    }
    throw Exception('模型下载失败（所有镜像源均不可达）：$lastErr');
  }

  /// Transcribe a 16 kHz Mono 16-bit PCM WAV slice locally on-device using `sherpa_onnx`
  /// (`SenseVoice-Small INT8` + `Silero VAD` or RMS energy splitter) inside a persistent
  /// background Isolate so the UI never drops a frame.
  Future<List<Map<String, dynamic>>> transcribeWavSlice({
    required String wavPath,
    required double sliceStartSecs,
    String language = 'auto',
  }) async {
    _activeTranscriptions += 1;
    final reply = ReceivePort();
    try {
      await refreshStatus();
      if (!isModelDownloaded) {
        throw Exception('尚未下载本地离线语音模型，请先前往「设置 → AI 翻译」下载 SenseVoice 模型');
      }
      final dir = await _resolveModelDir();
      final modelPath = '${dir.path}/${LocalAsrModelSpec.modelFileName}';
      final tokensPath = '${dir.path}/${LocalAsrModelSpec.tokensFileName}';
      final vadPath = hasVadModel ? '${dir.path}/${LocalAsrModelSpec.vadFileName}' : '';
      final normLang = (language.trim().isEmpty || language.trim().toLowerCase() == 'auto')
          ? 'auto'
          : language.trim().toLowerCase();
      final numThreads = (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) ? 2 : 4;
      final sig = '$modelPath::$tokensPath::$vadPath::$normLang::$numThreads';

      await _ensureWorker(
        modelPath: modelPath,
        tokensPath: tokensPath,
        vadPath: vadPath,
        language: normLang,
        numThreads: numThreads,
        sig: sig,
      );

      final sendPort = _workerSendPort;
      if (sendPort == null) {
        throw Exception('本地语音识别引擎初始化失败');
      }

      sendPort.send(<String, dynamic>{
        'cmd': 'transcribe',
        'wav_path': wavPath,
        'slice_start_ms': (sliceStartSecs * 1000).round(),
        'reply': reply.sendPort,
      });
      final resp = await reply.first.timeout(const Duration(seconds: 60));

      if (resp is Map && resp['error'] != null) {
        throw Exception(resp['error'].toString());
      }
      if (resp is Map && resp['cues'] is List) {
        return (resp['cues'] as List).whereType<Map<String, dynamic>>().toList();
      }
      return const [];
    } finally {
      _activeTranscriptions = (_activeTranscriptions - 1).clamp(0, 1 << 20);
      reply.close();
      try {
        final f = File(wavPath);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
    }
  }

  Future<void> _ensureWorker({
    required String modelPath,
    required String tokensPath,
    required String vadPath,
    required String language,
    required int numThreads,
    required String sig,
  }) async {
    if (_workerSendPort != null && _loadedModelSig == sig) return;
    if (_startingWorker != null) {
      await _startingWorker;
      if (_workerSendPort != null && _loadedModelSig == sig) return;
    }

    final completer = Completer<void>();
    _startingWorker = completer.future;
    final readyPort = ReceivePort();
    try {
      await unloadEngine();
      final exitPort = ReceivePort();
      _workerExitPort = exitPort;
      final isolate = await Isolate.spawn(
        _localAsrIsolateEntry,
        <String, dynamic>{
          'ready': readyPort.sendPort,
          'model_path': modelPath,
          'tokens_path': tokensPath,
          'vad_path': vadPath,
          'language': language,
          'num_threads': numThreads,
        },
        onExit: exitPort.sendPort,
      );
      _workerIsolate = isolate;
      exitPort.listen((_) {
        if (_workerIsolate == isolate) {
          _workerIsolate = null;
          _workerSendPort = null;
          _loadedModelSig = '';
          _workerExitPort?.close();
          _workerExitPort = null;
        }
      });

      final initMsg = await readyPort.first.timeout(const Duration(seconds: 30));
      if (initMsg is Map && initMsg['error'] != null) {
        await unloadEngine();
        throw Exception(initMsg['error'].toString());
      }
      if (initMsg is Map && initMsg['send_port'] is SendPort) {
        _workerSendPort = initMsg['send_port'] as SendPort;
        _loadedModelSig = sig;
      } else {
        await unloadEngine();
        throw Exception('本地语音识别引擎启动异常');
      }
      completer.complete();
    } catch (e) {
      await unloadEngine();
      if (!completer.isCompleted) completer.completeError(e);
      rethrow;
    } finally {
      readyPort.close();
      _startingWorker = null;
    }
  }

  /// Gracefully free ONNX recognizer + VAD native C++ memory BEFORE terminating the worker isolate.
  /// Avoids leaking 230–400 MB of native ONNX heap on `Isolate.immediate` termination.
  Future<void> unloadEngine() async {
    final sp = _workerSendPort;
    final iso = _workerIsolate;
    final exitPort = _workerExitPort;
    _workerSendPort = null;
    _workerIsolate = null;
    _workerExitPort = null;
    _loadedModelSig = '';

    if (sp != null) {
      final ackPort = ReceivePort();
      try {
        sp.send(<String, dynamic>{
          'cmd': 'shutdown',
          'ack': ackPort.sendPort,
        });
        await ackPort.first.timeout(const Duration(seconds: 3));
      } catch (_) {
        // Fallback to hard kill if the worker is wedged
      } finally {
        ackPort.close();
      }
    }
    try {
      iso?.kill(priority: Isolate.immediate);
    } catch (_) {}
    exitPort?.close();
  }
}

/// Decode a standard 16-bit PCM Mono WAV byte buffer into normalized `[-1.0, 1.0]` `Float32List`.
Float32List decodePcm16WavToFloat32(Uint8List bytes) {
  if (bytes.length <= 44) return Float32List(0);
  // Locate the `data` chunk cleanly (handles standard 44-byte or extended WAV headers)
  var offset = 12;
  var dataStart = 44;
  var dataLen = bytes.length - 44;
  final bd = ByteData.sublistView(bytes);
  while (offset + 8 <= bytes.length) {
    final c0 = bytes[offset];
    final c1 = bytes[offset + 1];
    final c2 = bytes[offset + 2];
    final c3 = bytes[offset + 3];
    final chunkSize = bd.getUint32(offset + 4, Endian.little);
    if (c0 == 0x64 && c1 == 0x61 && c2 == 0x74 && c3 == 0x61) {
      // 'data'
      dataStart = offset + 8;
      dataLen = chunkSize.clamp(0, bytes.length - dataStart);
      break;
    }
    offset += 8 + chunkSize + (chunkSize.isOdd ? 1 : 0);
  }

  final sampleCount = dataLen ~/ 2;
  final out = Float32List(sampleCount);
  for (var i = 0; i < sampleCount; i++) {
    final s = bd.getInt16(dataStart + i * 2, Endian.little);
    out[i] = s / 32768.0;
  }
  return out;
}

/// Lightweight RMS energy-based speech segment splitter used as fallback when Silero VAD
/// isn't downloaded yet. Splits a 16 kHz PCM clip into `(startSample, Float32List)` segments.
List<({int startSample, Float32List samples})> splitSpeechByEnergy(
  Float32List samples, {
  int sampleRate = 16000,
  double rmsThreshold = 0.012,
  double maxSegmentSecs = 7.5,
  double minSilenceSecs = 0.45,
}) {
  if (samples.isEmpty) return const [];
  const frameMs = 30;
  final frameLen = (sampleRate * frameMs) ~/ 1000;
  final maxSegFrames = ((maxSegmentSecs * 1000) / frameMs).round();
  final minSilFrames = ((minSilenceSecs * 1000) / frameMs).round();
  final totalFrames = samples.length ~/ frameLen;
  if (totalFrames == 0) return const [];

  final out = <({int startSample, Float32List samples})>[];
  int? segStartFrame;
  var silentRun = 0;

  void flushSegment(int startF, int endF) {
    final s = (startF * frameLen).clamp(0, samples.length);
    final e = (endF * frameLen).clamp(s, samples.length);
    if (e - s >= (sampleRate * 0.25).round()) {
      out.add((startSample: s, samples: Float32List.sublistView(samples, s, e)));
    }
  }

  for (var f = 0; f < totalFrames; f++) {
    final off = f * frameLen;
    var sumSq = 0.0;
    for (var i = 0; i < frameLen; i++) {
      final v = samples[off + i];
      sumSq += v * v;
    }
    final rms = math.sqrt(sumSq / frameLen);
    final voiced = rms >= rmsThreshold;

    if (voiced) {
      segStartFrame ??= f;
      silentRun = 0;
      if (f - segStartFrame >= maxSegFrames) {
        flushSegment(segStartFrame, f + 1);
        segStartFrame = null;
      }
    } else if (segStartFrame != null) {
      silentRun += 1;
      if (silentRun >= minSilFrames) {
        flushSegment(segStartFrame, (f - silentRun + 2).clamp(segStartFrame + 1, totalFrames));
        segStartFrame = null;
        silentRun = 0;
      }
    }
  }
  if (segStartFrame != null) {
    flushSegment(segStartFrame, totalFrames);
  }
  return out;
}

/// Strip SenseVoice emotion/language control tags (`<|ja|>`, `<|NEUTRAL|>`, `<|Speech|>`, etc.).
String cleanSenseVoiceText(String raw) {
  return raw.replaceAll(RegExp(r'<\|[^|]*\|>'), '').trim();
}

void _localAsrIsolateEntry(Map<String, dynamic> initArgs) {
  final readyPort = initArgs['ready'] as SendPort;
  final modelPath = initArgs['model_path'] as String;
  final tokensPath = initArgs['tokens_path'] as String;
  final vadPath = initArgs['vad_path'] as String;
  final language = initArgs['language'] as String;
  final numThreads = initArgs['num_threads'] as int;

  sherpa_onnx.OfflineRecognizer? recognizer;
  sherpa_onnx.VoiceActivityDetector? vad;

  try {
    sherpa_onnx.initBindings();
    final recConfig = sherpa_onnx.OfflineRecognizerConfig(
      model: sherpa_onnx.OfflineModelConfig(
        senseVoice: sherpa_onnx.OfflineSenseVoiceModelConfig(
          model: modelPath,
          language: language,
          useInverseTextNormalization: true,
        ),
        tokens: tokensPath,
        numThreads: numThreads,
        debug: false,
        provider: 'cpu',
      ),
    );
    recognizer = sherpa_onnx.OfflineRecognizer(recConfig);

    if (vadPath.isNotEmpty && File(vadPath).existsSync()) {
      final vadConfig = sherpa_onnx.VadModelConfig(
        sileroVad: sherpa_onnx.SileroVadModelConfig(
          model: vadPath,
          threshold: 0.42,
          minSilenceDuration: 0.45,
          minSpeechDuration: 0.25,
          maxSpeechDuration: 8.0,
          windowSize: 512,
        ),
        sampleRate: 16000,
        numThreads: 1,
        debug: false,
      );
      vad = sherpa_onnx.VoiceActivityDetector(
        config: vadConfig,
        bufferSizeInSeconds: 60.0,
      );
    }
  } catch (e) {
    recognizer?.free();
    vad?.free();
    readyPort.send(<String, dynamic>{'error': '加载本地离线模型失败: $e'});
    return;
  }

  final inbox = ReceivePort();
  readyPort.send(<String, dynamic>{'send_port': inbox.sendPort});

  inbox.listen((msg) {
    if (msg is! Map) return;
    final cmd = msg['cmd']?.toString();
    if (cmd == 'shutdown') {
      try {
        recognizer?.free();
        recognizer = null;
      } catch (_) {}
      try {
        vad?.free();
        vad = null;
      } catch (_) {}
      final ack = msg['ack'];
      if (ack is SendPort) {
        try {
          ack.send(true);
        } catch (_) {}
      }
      inbox.close();
      return;
    }
    if (cmd == 'transcribe') {
      final reply = msg['reply'] as SendPort;
      final wavPath = msg['wav_path'] as String;
      final sliceStartMs = (msg['slice_start_ms'] as num?)?.toInt() ?? 0;
      try {
        final wavFile = File(wavPath);
        final bytes = wavFile.readAsBytesSync();
        try {
          wavFile.deleteSync();
        } catch (_) {}

        final samples = decodePcm16WavToFloat32(bytes);
        if (samples.isEmpty) {
          reply.send(const <String, dynamic>{'cues': <Map<String, dynamic>>[]});
          return;
        }

        final segments = <({int startSample, Float32List samples})>[];
        final activeVad = vad;
        if (activeVad != null) {
          activeVad.reset();
          const win = 512;
          for (var offset = 0; offset + win <= samples.length; offset += win) {
            activeVad.acceptWaveform(Float32List.sublistView(samples, offset, offset + win));
            while (!activeVad.isEmpty()) {
              final seg = activeVad.front();
              activeVad.pop();
              if (seg.samples.length >= 3200) {
                segments.add((startSample: seg.start, samples: seg.samples));
              }
            }
          }
          activeVad.flush();
          while (!activeVad.isEmpty()) {
            final seg = activeVad.front();
            activeVad.pop();
            if (seg.samples.length >= 3200) {
              segments.add((startSample: seg.start, samples: seg.samples));
            }
          }
        } else {
          segments.addAll(splitSpeechByEnergy(samples));
        }

        final activeRecognizer = recognizer;
        if (activeRecognizer == null) {
          reply.send(const <String, dynamic>{'error': '本地识别引擎未初始化'});
          return;
        }
        final cues = <Map<String, dynamic>>[];
        for (final seg in segments) {
          final stream = activeRecognizer.createStream();
          String rawText;
          try {
            stream.acceptWaveform(samples: seg.samples, sampleRate: 16000);
            activeRecognizer.decode(stream);
            rawText = activeRecognizer.getResult(stream).text;
          } finally {
            stream.free();
          }
          final text = cleanSenseVoiceText(rawText);
          if (text.isEmpty) continue;
          final startMs = sliceStartMs + ((seg.startSample / 16.0).round());
          final durMs = (seg.samples.length / 16.0).round();
          cues.add(<String, dynamic>{
            'start_ms': startMs,
            'end_ms': startMs + durMs.clamp(700, 12000),
            'text': text,
          });
        }
        reply.send(<String, dynamic>{'cues': cues});
      } catch (e) {
        reply.send(<String, dynamic>{'error': '本地语音识别出错: $e'});
      }
    }
  });
}
