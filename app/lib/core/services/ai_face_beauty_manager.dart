import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// On-demand downloadable local AI Face Detection & 5-Landmark ONNX model metadata (Plan A).
///
/// Uses OpenCV Zoo's official Apache-2.0 YuNet (`face_detection_yunet_2023mar.onnx`, ~228 KB),
/// running 100% locally offline via pure-Rust `tract-onnx` inside `libvedro_ffi`.
/// Zero cloud uploads, sub-20ms single-thread inference, unlocks GPU Slim Face / Big Eyes /
/// V-Chin / Precision Lip Tint when downloaded & enabled in Settings or the Player Beauty panel.
class AiFaceBeautyModelSpec {
  static const String id = 'yunet_2023mar';
  static const String displayName = 'YuNet 实时人脸关键点模型 (ONNX)';
  static const String capabilitiesLabel = '本地离线 5 关键点人脸追踪 · 解锁 AI 瘦脸 / 大眼 / V脸 / 精准唇彩';
  static const String fileName = 'face_detection_yunet_2023mar.onnx';
  static const int expectedBytes = 232589;
  static const int minValidBytes = 180000;
  static const String expectedSha256 =
      '8f2383e4dd3cfbb4553ea8718107fc0423210dc964f9f4280604804ed2552fa4';

  static const String _hfRepoPath = 'opencv/face_detection_yunet/resolve/main/$fileName';
  static const String _githubRawUrl =
      'https://github.com/opencv/opencv_zoo/raw/main/models/face_detection_yunet/$fileName';

  static List<String> modelUrls({required bool preferChinaMirror}) => preferChinaMirror
      ? const [
          'https://hf-mirror.com/$_hfRepoPath',
          'https://huggingface.co/$_hfRepoPath',
          _githubRawUrl,
        ]
      : const [
          'https://huggingface.co/$_hfRepoPath',
          _githubRawUrl,
          'https://hf-mirror.com/$_hfRepoPath',
        ];
}

/// Stackable Plan A AI Face Morph parameters (`0.0 ~ 1.0` each).
class AiFaceMorphParams {
  const AiFaceMorphParams({
    this.slimFace = 0.0,
    this.bigEyes = 0.0,
    this.vChin = 0.0,
    this.lipTint = 0.0,
  });

  static const AiFaceMorphParams off = AiFaceMorphParams();
  static const AiFaceMorphParams subtle = AiFaceMorphParams(
    slimFace: 0.30,
    bigEyes: 0.22,
    vChin: 0.18,
    lipTint: 0.16,
  );
  static const AiFaceMorphParams douyin = AiFaceMorphParams(
    slimFace: 0.56,
    bigEyes: 0.44,
    vChin: 0.38,
    lipTint: 0.36,
  );

  final double slimFace;
  final double bigEyes;
  final double vChin;
  final double lipTint;

  bool get isActive =>
      slimFace > 0.005 || bigEyes > 0.005 || vChin > 0.005 || lipTint > 0.005;

  AiFaceMorphParams clamped() => AiFaceMorphParams(
        slimFace: slimFace.clamp(0.0, 1.0),
        bigEyes: bigEyes.clamp(0.0, 1.0),
        vChin: vChin.clamp(0.0, 1.0),
        lipTint: lipTint.clamp(0.0, 1.0),
      );

  AiFaceMorphParams copyWith({
    double? slimFace,
    double? bigEyes,
    double? vChin,
    double? lipTint,
  }) =>
      AiFaceMorphParams(
        slimFace: (slimFace ?? this.slimFace).clamp(0.0, 1.0),
        bigEyes: (bigEyes ?? this.bigEyes).clamp(0.0, 1.0),
        vChin: (vChin ?? this.vChin).clamp(0.0, 1.0),
        lipTint: (lipTint ?? this.lipTint).clamp(0.0, 1.0),
      );

  String summaryLabel() {
    if (!isActive) return '已归零';
    final parts = <String>[];
    if (slimFace > 0.005) parts.add('瘦脸 ${(slimFace * 100).round()}%');
    if (bigEyes > 0.005) parts.add('大眼 ${(bigEyes * 100).round()}%');
    if (vChin > 0.005) parts.add('V脸 ${(vChin * 100).round()}%');
    if (lipTint > 0.005) parts.add('唇彩 ${(lipTint * 100).round()}%');
    return parts.join(' · ');
  }

  @override
  bool operator ==(Object other) =>
      other is AiFaceMorphParams &&
      (slimFace - other.slimFace).abs() < 0.001 &&
      (bigEyes - other.bigEyes).abs() < 0.001 &&
      (vChin - other.vChin).abs() < 0.001 &&
      (lipTint - other.lipTint).abs() < 0.001;

  @override
  int get hashCode => Object.hash(
        (slimFace * 100).round(),
        (bigEyes * 100).round(),
        (vChin * 100).round(),
        (lipTint * 100).round(),
      );
}

/// Normalized `[0.0, 1.0]` face bounding box + 5 key landmarks returned by Rust YuNet.
class AiTrackedFace {
  const AiTrackedFace({
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    required this.score,
    required this.reX,
    required this.reY,
    required this.leX,
    required this.leY,
    required this.noseX,
    required this.noseY,
    required this.rmX,
    required this.rmY,
    required this.lmX,
    required this.lmY,
    this.alpha = 1.0,
  });

  final double x;
  final double y;
  final double w;
  final double h;
  final double score;
  final double reX;
  final double reY;
  final double leX;
  final double leY;
  final double noseX;
  final double noseY;
  final double rmX;
  final double rmY;
  final double lmX;
  final double lmY;
  final double alpha;

  double get centerX => x + w * 0.5;
  double get centerY => y + h * 0.5;
  double get mouthCenterX => (rmX + lmX) * 0.5;
  double get mouthCenterY => (rmY + lmY) * 0.5;
  double get mouthWidth => (lmX - rmX).abs().clamp(w * 0.22, w * 0.65);

  factory AiTrackedFace.fromJson(Map<String, dynamic> j) {
    double d(String k, [double fb = 0.0]) => (j[k] is num) ? (j[k] as num).toDouble() : fb;
    return AiTrackedFace(
      x: d('x').clamp(0.0, 1.0),
      y: d('y').clamp(0.0, 1.0),
      w: d('w').clamp(0.0, 1.0),
      h: d('h').clamp(0.0, 1.0),
      score: d('score').clamp(0.0, 1.0),
      reX: d('re_x').clamp(0.0, 1.0),
      reY: d('re_y').clamp(0.0, 1.0),
      leX: d('le_x').clamp(0.0, 1.0),
      leY: d('le_y').clamp(0.0, 1.0),
      noseX: d('nose_x').clamp(0.0, 1.0),
      noseY: d('nose_y').clamp(0.0, 1.0),
      rmX: d('rm_x').clamp(0.0, 1.0),
      rmY: d('rm_y').clamp(0.0, 1.0),
      lmX: d('lm_x').clamp(0.0, 1.0),
      lmY: d('lm_y').clamp(0.0, 1.0),
    );
  }

  AiTrackedFace withAlpha(double nextAlpha) => AiTrackedFace(
        x: x,
        y: y,
        w: w,
        h: h,
        score: score,
        reX: reX,
        reY: reY,
        leX: leX,
        leY: leY,
        noseX: noseX,
        noseY: noseY,
        rmX: rmX,
        rmY: rmY,
        lmX: lmX,
        lmY: lmY,
        alpha: nextAlpha.clamp(0.0, 1.0),
      );

  static double _lerp(double a, double b, double t) => a + (b - a) * t;

  AiTrackedFace lerpTo(AiTrackedFace target, double t, {double? alphaOverride}) {
    final k = t.clamp(0.0, 1.0);
    return AiTrackedFace(
      x: _lerp(x, target.x, k),
      y: _lerp(y, target.y, k),
      w: _lerp(w, target.w, k),
      h: _lerp(h, target.h, k),
      score: _lerp(score, target.score, k),
      reX: _lerp(reX, target.reX, k),
      reY: _lerp(reY, target.reY, k),
      leX: _lerp(leX, target.leX, k),
      leY: _lerp(leY, target.leY, k),
      noseX: _lerp(noseX, target.noseX, k),
      noseY: _lerp(noseY, target.noseY, k),
      rmX: _lerp(rmX, target.rmX, k),
      rmY: _lerp(rmY, target.rmY, k),
      lmX: _lerp(lmX, target.lmX, k),
      lmY: _lerp(lmY, target.lmY, k),
      alpha: (alphaOverride ?? _lerp(alpha, target.alpha, k)).clamp(0.0, 1.0),
    );
  }
}

/// Manages on-demand downloading, verification, storage status, and deletion of the
/// local YuNet AI Face Landmark model (mirrors `LocalAsrManager`).
class AiFaceBeautyManager extends ChangeNotifier {
  AiFaceBeautyManager();

  static final AiFaceBeautyManager instance = AiFaceBeautyManager();

  bool isModelDownloaded = false;
  int downloadedBytes = 0;
  String? modelDirPath;
  String? modelFilePath;

  bool isDownloading = false;
  double downloadProgress = 0.0;
  String downloadStage = '';
  String? downloadError;

  HttpClient? _activeClient;
  Future<void>? _activeDownloadFuture;
  bool _cancelRequested = false;

  Future<Directory> _resolveModelDir() async {
    if (modelDirPath != null && modelDirPath!.isNotEmpty) {
      return Directory(modelDirPath!);
    }
    final dir = await getApplicationSupportDirectory();
    final out = Directory('${dir.path}/ai_face_models/${AiFaceBeautyModelSpec.id}');
    modelDirPath = out.path;
    return out;
  }

  Future<void> refreshStatus() async {
    try {
      final dir = await _resolveModelDir();
      final modelFile = File('${dir.path}/${AiFaceBeautyModelSpec.fileName}');
      final exists = modelFile.existsSync();
      final bytes = exists ? modelFile.lengthSync() : 0;
      isModelDownloaded = exists && bytes >= AiFaceBeautyModelSpec.minValidBytes;
      downloadedBytes = bytes;
      modelFilePath = isModelDownloaded ? modelFile.path : null;
    } catch (_) {
      isModelDownloaded = false;
      downloadedBytes = 0;
      modelFilePath = null;
    }
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

  Future<void> downloadModel({bool useChinaMirror = true}) {
    if (isDownloading && _activeDownloadFuture != null) {
      return _activeDownloadFuture!;
    }
    final fut = _downloadModelImpl(useChinaMirror: useChinaMirror);
    _activeDownloadFuture = fut;
    return fut;
  }

  Future<void> _downloadModelImpl({required bool useChinaMirror}) async {
    isDownloading = true;
    _cancelRequested = false;
    downloadProgress = 0.0;
    downloadStage = '正在连接模型镜像源…';
    downloadError = null;
    notifyListeners();

    try {
      final dir = await _resolveModelDir();
      if (!dir.existsSync()) {
        await dir.create(recursive: true);
      }
      final destPath = '${dir.path}/${AiFaceBeautyModelSpec.fileName}';
      await _downloadWithMirrors(
        urls: AiFaceBeautyModelSpec.modelUrls(preferChinaMirror: useChinaMirror),
        destPath: destPath,
        minBytes: AiFaceBeautyModelSpec.minValidBytes,
        onProgress: (received, total) {
          final effTotal = total > 0 ? total : AiFaceBeautyModelSpec.expectedBytes;
          final ratio = (received / effTotal).clamp(0.0, 1.0);
          final recvKb = (received / 1024).toStringAsFixed(0);
          final totKb = (effTotal / 1024).toStringAsFixed(0);
          downloadProgress = ratio;
          downloadStage = '下载 YuNet 人脸模型：$recvKb / $totKb KB';
          notifyListeners();
        },
      );
      downloadProgress = 1.0;
      downloadStage = '本地 AI 人脸模型已就绪';
      await refreshStatus();
    } catch (e) {
      downloadError = e.toString().replaceFirst('Exception: ', '');
      downloadStage = '';
    } finally {
      _activeClient = null;
      _activeDownloadFuture = null;
      isDownloading = false;
      notifyListeners();
    }
  }

  Future<void> deleteModel() async {
    if (isDownloading) {
      cancelDownload();
      try {
        await _activeDownloadFuture;
      } catch (_) {}
    }
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
      client.connectionTimeout = const Duration(seconds: 15);
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
          req.headers.set(HttpHeaders.userAgentHeader, 'Vedro-FaceAI/1.0');
          final r = await req.close().timeout(const Duration(seconds: 20));
          if (r.isRedirect && r.headers.value(HttpHeaders.locationHeader) != null) {
            final loc = r.headers.value(HttpHeaders.locationHeader)!;
            await r.drain<void>();
            uri = uri.resolve(loc);
            continue;
          }
          resp = r;
          break;
        }
        if (resp == null) throw Exception('HTTP 0');
        if (resp.statusCode < 200 || resp.statusCode >= 300) {
          await resp.drain<void>();
          throw Exception('HTTP ${resp.statusCode}');
        }
        final expectedTotal = resp.contentLength;
        sink = partFile.openWrite(mode: FileMode.writeOnly);
        var received = 0;
        var lastEmitMs = 0;

        await for (final chunk in resp.timeout(const Duration(seconds: 25))) {
          if (_cancelRequested) throw Exception('已取消下载');
          sink.add(chunk);
          received += chunk.length;
          final nowMs = DateTime.now().millisecondsSinceEpoch;
          if (nowMs - lastEmitMs >= 100) {
            lastEmitMs = nowMs;
            onProgress(received, expectedTotal);
          }
        }
        await sink.flush();
        await sink.close();
        sink = null;

        if (expectedTotal > 0 && received != expectedTotal) {
          throw Exception('模型文件不完整 ($received / $expectedTotal B)');
        }
        if (received < minBytes) {
          throw Exception('模型文件大小异常 ($received B)');
        }
        onProgress(received, expectedTotal);
        if (destFile.existsSync()) destFile.deleteSync();
        partFile.renameSync(destPath);
        return;
      } catch (e) {
        lastErr = e;
        try {
          await sink?.close();
        } catch (_) {}
        if (_cancelRequested) rethrow;
      } finally {
        client.close(force: true);
      }
    }
    throw Exception('模型下载失败（所有镜像源均不可达）：$lastErr');
  }
}
