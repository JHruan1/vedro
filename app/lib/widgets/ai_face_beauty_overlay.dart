import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import '../core/ffi/vedro_bridge.dart';
import '../core/platform/platform_perf.dart';
import '../core/services/ai_face_beauty_manager.dart';
import 'ai_face_mpv_shader.dart';

/// Compiled Impeller fragment program loader for `shaders/ai_face_beauty.frag`.
///
/// Updates 34 float uniforms in microseconds with ZERO shader recompilation on
/// iOS Metal, macOS Metal, Android Vulkan, and Android OpenGL ES.
/// On Skia backends (Windows D3D11/ANGLE, Linux OpenGL), dynamic `glsl-shaders`
/// hot-reloading triggers `D3DCompile` stalls on `libmpv`'s video thread (~2 FPS),
/// so Plan A stays safely inactive on Skia while Plan B runs at locked 60 FPS everywhere.
class AiFaceBeautyShader {
  AiFaceBeautyShader._();

  static const String _assetPath = 'shaders/ai_face_beauty.frag';

  static ui.FragmentProgram? _program;
  static Future<void>? _loadingFuture;

  static bool get isSupported => ui.ImageFilter.isShaderFilterSupported;
  static bool get isAvailable => isSupported && _program != null;

  /// Human-readable GPU backend label for the active OS & renderer.
  static String get activeGpuPipelineLabel {
    if (isSupported) {
      if (PlatformPerfProfile.isIOS) return 'iOS Metal · Impeller GPU 实时无重编译着色器';
      if (PlatformPerfProfile.isMacOS) return 'macOS Metal · Impeller GPU 实时无重编译着色器';
      if (PlatformPerfProfile.isAndroid) return 'Android Vulkan / OpenGL ES · Impeller GPU 实时着色器';
      return 'Impeller GPU 实时着色器';
    }
    if (PlatformPerfProfile.isWindows) return 'Windows Skia（暂不支持 60fps 无重编译五官形变，请使用方案 B 质感美颜）';
    if (PlatformPerfProfile.isLinux) return 'Linux Skia（暂不支持 60fps 无重编译五官形变，请使用方案 B 质感美颜）';
    return 'Skia 渲染后端（AI 五官需 Impeller Metal/Vulkan/GLES）';
  }

  static Future<void> preload() {
    if (_program != null) return Future<void>.value();
    return _loadingFuture ??= _loadInternal();
  }

  static Future<void> _loadInternal() async {
    if (!ui.ImageFilter.isShaderFilterSupported) return;
    try {
      _program = await ui.FragmentProgram.fromAsset(_assetPath);
    } catch (_) {
      _program = null;
    }
  }

  /// Build an `ImageFilter.shader` + owned `FragmentShader` handle carrying the active
  /// morph sliders and up to 2 tracked faces. Caller MUST dispose the returned `shader`
  /// on next rebuild / widget dispose to prevent native uniform buffer leaks.
  static ({ui.ImageFilter filter, ui.FragmentShader shader})? buildFilterWithHandle({
    required Rect viewportScreenRectPx,
    required AiFaceMorphParams morph,
    required List<AiTrackedFace> faces,
  }) {
    if (!isAvailable || !morph.isActive || faces.isEmpty) return null;
    final hasVisible = faces.any((f) => f.alpha > 0.005);
    if (!hasVisible) return null;
    final program = _program;
    if (program == null) return null;

    ui.FragmentShader? shader;
    try {
      shader = program.fragmentShader();
      shader.setFloat(0, 0.0);
      shader.setFloat(1, 0.0);
      shader.setFloat(2, viewportScreenRectPx.left);
      shader.setFloat(3, viewportScreenRectPx.top);
      shader.setFloat(4, viewportScreenRectPx.width);
      shader.setFloat(5, viewportScreenRectPx.height);
      shader.setFloat(6, morph.slimFace.clamp(0.0, 1.0));
      shader.setFloat(7, morph.bigEyes.clamp(0.0, 1.0));
      shader.setFloat(8, morph.vChin.clamp(0.0, 1.0));
      shader.setFloat(9, morph.lipTint.clamp(0.0, 1.0));

      void writeFace(int baseIdx, AiTrackedFace? f) {
        if (f == null || f.alpha <= 0.005) {
          for (var i = 0; i < 12; i++) {
            shader!.setFloat(baseIdx + i, 0.0);
          }
          return;
        }
        shader!.setFloat(baseIdx + 0, f.reX);
        shader.setFloat(baseIdx + 1, f.reY);
        shader.setFloat(baseIdx + 2, f.leX);
        shader.setFloat(baseIdx + 3, f.leY);
        shader.setFloat(baseIdx + 4, f.noseX);
        shader.setFloat(baseIdx + 5, f.noseY);
        shader.setFloat(baseIdx + 6, f.mouthCenterX);
        shader.setFloat(baseIdx + 7, f.mouthCenterY);
        shader.setFloat(baseIdx + 8, f.w);
        shader.setFloat(baseIdx + 9, f.h);
        shader.setFloat(baseIdx + 10, f.mouthWidth);
        shader.setFloat(baseIdx + 11, f.alpha.clamp(0.0, 1.0));
      }

      writeFace(10, faces.isNotEmpty ? faces[0] : null);
      writeFace(22, faces.length > 1 ? faces[1] : null);

      final filter = ui.ImageFilter.shader(
        shader,
        filterQuality: FilterQuality.low,
      );
      return (filter: filter, shader: shader);
    } catch (_) {
      shader?.dispose();
      return null;
    }
  }
}

/// Live telemetry snapshot exposed by [AiFaceBeautyViewport] for the player Beauty Sheet.
class AiFaceTrackTelemetry {
  const AiFaceTrackTelemetry({
    this.active = false,
    this.trackedFaces = 0,
    this.lastInferMs = 0.0,
    this.gpuWarpSupported = true,
    this.copyBackHwdecActive = false,
    this.lastError,
  });

  final bool active;
  final int trackedFaces;
  final double lastInferMs;
  final bool gpuWarpSupported;
  final bool copyBackHwdecActive;
  final String? lastError;

  String statusBadge() {
    if (!gpuWarpSupported) return '需 Impeller GPU（请用方案 B）';
    if (!active) return '未启用';
    if (lastError != null && lastError!.isNotEmpty) return '模型待就绪';
    if (trackedFaces > 0) {
      return 'GPU 追踪 $trackedFaces 张人脸 · ${lastInferMs.round()}ms';
    }
    return 'GPU 实时追踪中 · 等待人脸';
  }
}

/// Pure-Dart temporal face tracker that smoothly interpolates ~7–10 Hz YuNet detections
/// into jitter-free 30 Hz GPU uniforms, with instant snap-reset on hard scene cuts
/// and strict convergence gating (returns `false` once settled -> zero wasted shader churn!).
class AiFaceTemporalSmoother {
  List<AiTrackedFace> _targets = const [];
  List<AiTrackedFace> _smoothed = const [];
  int _missedTicks = 0;

  List<AiTrackedFace> get smoothed => _smoothed;

  void reset() {
    _targets = const [];
    _smoothed = const [];
    _missedTicks = 0;
  }

  /// Feed a fresh YuNet detection result.
  void ingestDetection(List<AiTrackedFace> detected, {required bool sceneCut}) {
    if (sceneCut) {
      _missedTicks = 0;
      _targets = detected.take(2).map((f) => f.withAlpha(1.0)).toList();
      _smoothed = detected.take(2).map((f) => f.withAlpha(0.35)).toList();
      return;
    }
    if (detected.isEmpty) {
      _missedTicks += 1;
      if (_missedTicks >= 2) {
        _targets = const [];
      }
      return;
    }
    _missedTicks = 0;

    final nextTargets = <AiTrackedFace>[];
    final used = <int>{};
    for (final prev in _smoothed.take(2)) {
      var bestIdx = -1;
      var bestDist = 0.24;
      for (var i = 0; i < detected.length; i++) {
        if (used.contains(i)) continue;
        final dx = detected[i].centerX - prev.centerX;
        final dy = detected[i].centerY - prev.centerY;
        final dist = math.sqrt(dx * dx + dy * dy);
        if (dist < bestDist) {
          bestDist = dist;
          bestIdx = i;
        }
      }
      if (bestIdx >= 0) {
        used.add(bestIdx);
        nextTargets.add(detected[bestIdx].withAlpha(1.0));
      }
    }
    for (var i = 0; i < detected.length && nextTargets.length < 2; i++) {
      if (!used.contains(i)) {
        nextTargets.add(detected[i].withAlpha(1.0));
      }
    }
    _targets = nextTargets;
    if (_smoothed.isEmpty) {
      _smoothed = nextTargets.map((f) => f.withAlpha(0.25)).toList();
    }
  }

  static double _faceDelta(AiTrackedFace a, AiTrackedFace b) {
    var d = (a.reX - b.reX).abs();
    d = math.max(d, (a.reY - b.reY).abs());
    d = math.max(d, (a.leX - b.leX).abs());
    d = math.max(d, (a.leY - b.leY).abs());
    d = math.max(d, (a.noseX - b.noseX).abs());
    d = math.max(d, (a.noseY - b.noseY).abs());
    d = math.max(d, (a.mouthCenterX - b.mouthCenterX).abs());
    d = math.max(d, (a.mouthCenterY - b.mouthCenterY).abs());
    d = math.max(d, (a.w - b.w).abs());
    d = math.max(d, (a.h - b.h).abs());
    d = math.max(d, (a.alpha - b.alpha).abs());
    return d;
  }

  /// Advance smooth interpolation by [dtSecs]. Returns `true` ONLY if uniforms changed
  /// visibly (`> 0.0008` normalized delta or face count changed) — zero idle shader churn!
  bool step(double dtSecs) {
    if (_smoothed.isEmpty && _targets.isEmpty) return false;
    final dt = dtSecs.clamp(0.008, 0.1);
    final posT = 1.0 - math.exp(-dt * 18.0);
    final fadeInT = 1.0 - math.exp(-dt * 12.0);
    final fadeOutT = 1.0 - math.exp(-dt * 11.0);

    final next = <AiTrackedFace>[];
    var changed = false;
    final count = math.max(_smoothed.length, _targets.length).clamp(0, 2);
    for (var i = 0; i < count; i++) {
      final hasCur = i < _smoothed.length;
      final hasTgt = i < _targets.length;
      if (hasCur && hasTgt) {
        final cur = _smoothed[i];
        final tgt = _targets[i];
        final dx = tgt.centerX - cur.centerX;
        final dy = tgt.centerY - cur.centerY;
        final jump = math.sqrt(dx * dx + dy * dy);
        final effT = jump > 0.28 ? 1.0 : posT;
        final nextAlpha = cur.alpha + (1.0 - cur.alpha) * fadeInT;
        final stepped = cur.lerpTo(tgt, effT, alphaOverride: nextAlpha);
        if (_faceDelta(cur, stepped) > 0.0008) {
          changed = true;
          next.add(stepped);
        } else {
          // Snap tiny epsilon residual once converged so ticker stops repainting!
          next.add(tgt.withAlpha(1.0));
        }
      } else if (hasTgt) {
        changed = true;
        next.add(_targets[i].withAlpha(fadeInT));
      } else if (hasCur) {
        final cur = _smoothed[i];
        final nextAlpha = cur.alpha * (1.0 - fadeOutT);
        changed = true;
        if (nextAlpha > 0.01) {
          next.add(cur.withAlpha(nextAlpha));
        }
      }
    }
    if (next.length != _smoothed.length) changed = true;
    _smoothed = next;
    return changed;
  }
}

/// Ensures Impeller `ImageFiltered` allocates the full viewport offscreen texture
/// (matching Flutter's own `StretchEffect`) even when the video has letterbox bars.
class _ViewportCoveragePainter extends CustomPainter {
  const _ViewportCoveragePainter();

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width < 2 || size.height < 2) return;
    final paint = Paint()
      ..color = const Color.fromARGB(1, 0, 0, 0)
      ..style = PaintingStyle.fill;
    canvas.drawPoints(ui.PointMode.points, <Offset>[
      Offset.zero,
      Offset(size.width - 1, 0),
      Offset(0, size.height - 1),
      Offset(size.width - 1, size.height - 1),
    ], paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Zero-stutter Plan A AI Face Beauty wrapper around `Video(...)`.
///
/// - **Zero overhead when off (or on Skia Windows/Linux)**: renders [child] directly with
///   ZERO `ImageFiltered`, ZERO captures, ZERO `hwdec` overrides, and 100% native 60fps HDR/DV.
/// - **Zero-copy binary Rust FFI + persistent worker**:
///   - Primary: captures tiny `160×90` (57 KB) frame after `endOfFrame` and sends via
///     `TransferableTypedData` directly to `vedro_face_detect_raw` (`160×96` / `192×112`, ~6ms!).
///   - Fallback (Android `SurfaceTexture` black frames OR slow GPU readback > 75ms):
///     runs `mpv_command_ret("screenshot-raw", "video")` INSIDE the persistent background FFI
///     worker isolate and passes mpv's raw C pixel pointer STRAIGHT into Rust (`0` bytes copied
///     to Dart, `0` Isolate spawns, `0` UI-thread CPU!).
/// - **Self-pacing duty cycle (`>= max(baseMs, captureMs * 4)`)**: guarantees readback never
///   exceeds 20% GPU/CPU budget so video playback stays locked at native 60 FPS!
/// - **30 Hz converged Impeller shader**: skips idle shader rebuilds and keeps `ImageFiltered`
///   mounted stably (`enabled: hasFilter`) with zero structural widget rebuilds.
class AiFaceBeautyViewport extends StatefulWidget {
  const AiFaceBeautyViewport({
    super.key,
    required this.core,
    required this.enabled,
    required this.morph,
    required this.paused,
    required this.loading,
    required this.inPipMode,
    required this.videoWidth,
    required this.videoHeight,
    required this.videoFit,
    required this.telemetryNotifier,
    this.mpvHandleResolver,
    this.onMpvDetectFutureChanged,
    this.onCopyBackHwdecRequired,
    required this.child,
  });

  final VedroCoreClient core;
  final bool enabled;
  final AiFaceMorphParams morph;
  final bool paused;
  final bool loading;
  final bool inPipMode;
  final int videoWidth;
  final int videoHeight;
  final BoxFit videoFit;
  final ValueNotifier<AiFaceTrackTelemetry> telemetryNotifier;
  final Future<int?> Function()? mpvHandleResolver;
  final ValueChanged<Future<void>?>? onMpvDetectFutureChanged;
  final ValueChanged<bool>? onCopyBackHwdecRequired;
  final Widget child;

  @override
  State<AiFaceBeautyViewport> createState() => _AiFaceBeautyViewportState();
}

class _AiFaceBeautyViewportState extends State<AiFaceBeautyViewport>
    with SingleTickerProviderStateMixin {
  static final ui.ImageFilter _identityFilter =
      ui.ImageFilter.matrix(Matrix4.identity().storage);

  final GlobalKey _captureKey = GlobalKey(debugLabel: 'ai-face-video-capture');
  final AiFaceTemporalSmoother _smoother = AiFaceTemporalSmoother();
  final ValueNotifier<int> _paintTickNotifier = ValueNotifier<int>(0);

  ui.FragmentShader? _activeShader;
  Ticker? _ticker;
  Timer? _nextDetectTimer;
  Duration _lastTick = Duration.zero;
  Duration _lastUniformPush = Duration.zero;
  bool _detectInFlight = false;
  bool _disposed = false;
  bool _modelLoadedInRust = false;
  bool _useDirectMpvCapture = false;
  bool _copyBackRequested = false;
  int _consecutiveDarkCaptures = 0;
  int _consecutiveSlowToImage = 0;
  int _consecutiveEmptyMpvFrames = 0;
  int? _cachedMpvHandle;

  bool get _shouldTrack =>
      AiFaceBeautyShader.isSupported &&
      widget.enabled &&
      widget.morph.isActive &&
      AiFaceBeautyManager.instance.isModelDownloaded &&
      (AiFaceBeautyManager.instance.modelFilePath?.isNotEmpty ?? false) &&
      !widget.loading &&
      !widget.inPipMode;

  @override
  void initState() {
    super.initState();
    unawaited(
      AiFaceBeautyShader.preload().then((_) {
        if (mounted && !_disposed && _shouldTrack) {
          setState(() {});
          _emitTelemetry();
        }
      }),
    );
    AiFaceBeautyManager.instance.addListener(_onModelStateChanged);
    _syncTrackingLifecycle(triggerImmediate: true);
  }

  @override
  void didUpdateWidget(covariant AiFaceBeautyViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    final activeChanged = oldWidget.enabled != widget.enabled ||
        oldWidget.morph.isActive != widget.morph.isActive ||
        oldWidget.loading != widget.loading ||
        oldWidget.inPipMode != widget.inPipMode;
    final pausedChanged = oldWidget.paused != widget.paused;
    final morphChanged = oldWidget.morph != widget.morph;

    if (activeChanged || pausedChanged) {
      _syncTrackingLifecycle(triggerImmediate: true);
    } else if (morphChanged && _shouldTrack) {
      _paintTickNotifier.value++;
      if (_smoother.smoothed.isEmpty) {
        unawaited(_runSingleDetection());
      }
    }
  }

  void _onModelStateChanged() {
    if (!mounted || _disposed) return;
    _syncTrackingLifecycle(triggerImmediate: true);
    setState(() {});
  }

  void _syncTrackingLifecycle({bool triggerImmediate = false}) {
    if (!_shouldTrack) {
      _stopTracking(unloadModel: !widget.enabled || !widget.morph.isActive);
      return;
    }

    if (_ticker == null) {
      _lastTick = Duration.zero;
      _lastUniformPush = Duration.zero;
      _ticker = createTicker(_onAnimTick)..start();
    } else if (!_ticker!.isActive) {
      _lastTick = Duration.zero;
      _lastUniformPush = Duration.zero;
      _ticker!.start();
    }

    _nextDetectTimer?.cancel();
    _nextDetectTimer = null;

    if (triggerImmediate) {
      unawaited(_runSingleDetection());
    } else if (!widget.paused) {
      _scheduleNextDetection(PlatformPerfProfile.isMobile ? 140 : 110);
    }
    _emitTelemetry();
  }

  void _scheduleNextDetection(int delayMs) {
    if (_disposed || !mounted || !_shouldTrack || widget.paused) return;
    _nextDetectTimer?.cancel();
    _nextDetectTimer = Timer(
      Duration(milliseconds: delayMs.clamp(100, 480)),
      () => unawaited(_runSingleDetection()),
    );
  }

  void _stopTracking({required bool unloadModel}) {
    _nextDetectTimer?.cancel();
    _nextDetectTimer = null;
    _ticker?.stop();
    _smoother.reset();
    _disposeActiveShader();
    _paintTickNotifier.value++;

    if (_copyBackRequested) {
      _copyBackRequested = false;
      _consecutiveEmptyMpvFrames = 0;
      widget.onCopyBackHwdecRequired?.call(false);
    }
    if (unloadModel && _modelLoadedInRust) {
      _modelLoadedInRust = false;
      unawaited(widget.core.invoke('ai_face_unload_model').catchError((_) => null));
    }
    _emitTelemetry();
  }

  void _disposeActiveShader() {
    _activeShader?.dispose();
    _activeShader = null;
  }

  void _onAnimTick(Duration elapsed) {
    if (_disposed || !mounted) return;
    // Cap uniform repaints to ~30 Hz (32ms) so Impeller never churns shaders at 120 Hz!
    if (_lastUniformPush != Duration.zero &&
        (elapsed - _lastUniformPush).inMilliseconds < 32) {
      return;
    }
    final dt = _lastTick == Duration.zero
        ? 0.033
        : ((elapsed - _lastTick).inMicroseconds / 1000000.0);
    _lastTick = elapsed;
    _lastUniformPush = elapsed;
    if (_smoother.step(dt)) {
      _paintTickNotifier.value++;
    }
  }

  void _emitTelemetry({double? inferMs, String? error}) {
    if (_disposed) return;
    final prev = widget.telemetryNotifier.value;
    widget.telemetryNotifier.value = AiFaceTrackTelemetry(
      active: _shouldTrack,
      trackedFaces: _smoother.smoothed.where((f) => f.alpha > 0.1).length,
      lastInferMs: inferMs ?? prev.lastInferMs,
      gpuWarpSupported: AiFaceBeautyShader.isSupported,
      copyBackHwdecActive: _copyBackRequested,
      lastError: error,
    );
  }

  Size _resolveViewportLogicalSize() {
    final ro = _captureKey.currentContext?.findRenderObject();
    if (ro is RenderBox && ro.attached && ro.hasSize && !ro.size.isEmpty) {
      return ro.size;
    }
    return Size(
      widget.videoWidth > 0 ? widget.videoWidth.toDouble() : 16.0,
      widget.videoHeight > 0 ? widget.videoHeight.toDouble() : 9.0,
    );
  }

  static bool _looksAllBlack(Uint8List bytes) {
    if (bytes.length < 64) return true;
    final step = math.max(4, (bytes.length ~/ 24) & ~3);
    var sum = 0;
    var samples = 0;
    for (var i = 0; i + 2 < bytes.length; i += step) {
      sum += bytes[i] + bytes[i + 1] + bytes[i + 2];
      samples++;
    }
    return samples == 0 || (sum / (samples * 3)) < 2.2;
  }

  Future<({Uint8List bytes, int width, int height, double captureMs})?> _captureTinyViewport() async {
    try {
      // Wait for end-of-frame so capture never collides with an active build/layout pass
      await SchedulerBinding.instance.endOfFrame;
      if (_disposed || !mounted || !_shouldTrack) return null;
      final ro = _captureKey.currentContext?.findRenderObject();
      if (ro is RenderRepaintBoundary && ro.hasSize && !ro.size.isEmpty) {
        final sw = Stopwatch()..start();
        // Tiny 160px-wide GPU downscale (160x90 = 57 KB -> 4x faster readback!)
        final targetW = PlatformPerfProfile.isMobile ? 160.0 : 192.0;
        final ratio = (targetW / ro.size.width).clamp(0.08, 0.35);
        final img = await ro.toImage(pixelRatio: ratio);
        try {
          final bd = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
          final capMs = sw.elapsedMicroseconds / 1000.0;
          if (bd != null) {
            final bytes = bd.buffer.asUint8List(bd.offsetInBytes, bd.lengthInBytes);
            if (_looksAllBlack(bytes)) {
              _consecutiveDarkCaptures += 1;
              if (_consecutiveDarkCaptures >= 2 && widget.mpvHandleResolver != null) {
                _useDirectMpvCapture = true;
              }
              return null;
            }
            _consecutiveDarkCaptures = 0;
            // If GPU readback is stalling Flutter's Raster thread (>75ms twice), switch to
            // background zero-copy mpv capture so Flutter presentation stays locked at 60 FPS!
            if (capMs > 75.0 && widget.mpvHandleResolver != null) {
              _consecutiveSlowToImage += 1;
              if (_consecutiveSlowToImage >= 2) {
                _useDirectMpvCapture = true;
              }
            } else {
              _consecutiveSlowToImage = 0;
            }
            return (bytes: bytes, width: img.width, height: img.height, captureMs: capMs);
          }
        } finally {
          img.dispose();
        }
      }
    } catch (_) {
      if (widget.mpvHandleResolver != null) {
        _useDirectMpvCapture = true;
      }
    }
    return null;
  }

  Future<void> _runSingleDetection() async {
    if (_disposed || !mounted || !_shouldTrack || _detectInFlight) return;
    final modelPath = AiFaceBeautyManager.instance.modelFilePath;
    if (modelPath == null || modelPath.isEmpty) return;

    _detectInFlight = true;
    final baseIntervalMs = PlatformPerfProfile.isMobile ? 140 : 110;
    var observedCaptureMs = 0.0;
    try {
      final isMobile = PlatformPerfProfile.isMobile;
      final inferW = isMobile ? 160 : 192;
      final inferH = isMobile ? 96 : 112;
      Map<String, dynamic>? res;
      var fromVideoFrame = false;

      if (!_useDirectMpvCapture) {
        final frame = await _captureTinyViewport();
        if (_disposed || !mounted || !_shouldTrack) return;
        if (frame != null) {
          observedCaptureMs = frame.captureMs;
          // Fast path: zero-copy TransferableTypedData -> direct Rust C-ABI vedro_face_detect_raw
          res = await widget.core.detectFaceRaw(
            modelPath: modelPath,
            bytes: frame.bytes,
            width: frame.width,
            height: frame.height,
            isBgra: false,
            inferW: inferW,
            inferH: inferH,
            scoreThreshold: 0.60,
            maxFaces: 2,
          );
          // Fallback for mock clients in widget tests that only implement `invoke()`
          if (res == null && !_disposed && mounted) {
            final rawRes = await widget.core.invoke('ai_face_detect', {
              'model_path': modelPath,
              'width': frame.width,
              'height': frame.height,
              'data_b64': base64Encode(frame.bytes),
              'pixel_format': 'rgba',
              'infer_w': inferW,
              'infer_h': inferH,
              'score_threshold': 0.60,
              'max_faces': 2,
            });
            if (rawRes is Map<String, dynamic>) res = rawRes;
          }
        }
      }

      if (_useDirectMpvCapture && widget.mpvHandleResolver != null && !_disposed && mounted) {
        _cachedMpvHandle ??= await widget.mpvHandleResolver!();
        final mpvAddr = _cachedMpvHandle ?? 0;
        if (mpvAddr != 0 && !_disposed && mounted) {
          fromVideoFrame = true;
          final fut = widget.core.detectFaceFromMpv(
            mpvCtxAddr: mpvAddr,
            modelPath: modelPath,
            inferW: inferW,
            inferH: inferH,
            scoreThreshold: 0.60,
            maxFaces: 2,
          );
          widget.onMpvDetectFutureChanged?.call(fut.then((_) {}));
          try {
            res = await fut;
          } finally {
            widget.onMpvDetectFutureChanged?.call(null);
          }
          if (res != null) {
            observedCaptureMs = (res['capture_ms'] as num?)?.toDouble() ?? 15.0;
            if (res['empty_frame'] == true) {
              _consecutiveEmptyMpvFrames += 1;
              if (PlatformPerfProfile.isAndroid &&
                  !_copyBackRequested &&
                  _consecutiveEmptyMpvFrames >= 2 &&
                  widget.onCopyBackHwdecRequired != null) {
                _copyBackRequested = true;
                widget.onCopyBackHwdecRequired!.call(true);
                _emitTelemetry();
              }
              return;
            }
            _consecutiveEmptyMpvFrames = 0;
          }
        }
      }

      if (_disposed || !mounted || !_shouldTrack || res == null) return;
      _modelLoadedInRust = true;

      var faces = (res['faces'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(AiTrackedFace.fromJson)
          .toList();

      if (fromVideoFrame) {
        final viewSize = _resolveViewportLogicalSize();
        faces = faces
            .map((f) => AiFaceCoordinateMapper.videoToViewport(
                  f,
                  videoW: widget.videoWidth,
                  videoH: widget.videoHeight,
                  viewW: viewSize.width,
                  viewH: viewSize.height,
                  fit: widget.videoFit,
                ))
            .toList();
      }

      final sceneCut = res['scene_cut'] == true;
      final inferMs = (res['infer_ms'] as num?)?.toDouble() ?? 0.0;
      _smoother.ingestDetection(faces, sceneCut: sceneCut);
      _paintTickNotifier.value++;
      _emitTelemetry(inferMs: inferMs, error: null);
    } catch (e) {
      if (!_disposed && mounted) {
        _emitTelemetry(error: e.toString());
      }
    } finally {
      _detectInFlight = false;
      // Self-pacing duty cycle: keep capture <= 20% of frame budget so video NEVER drops frames!
      if (!_disposed && mounted && _shouldTrack && !widget.paused) {
        final pacedMs = math.max(baseIntervalMs, (observedCaptureMs * 4.0).round());
        _scheduleNextDetection(pacedMs);
      }
    }
  }

  Rect _resolveViewportScreenRectPx(BuildContext ctx) {
    final dpr = MediaQuery.maybeDevicePixelRatioOf(ctx) ?? 2.0;
    final ro = _captureKey.currentContext?.findRenderObject();
    if (ro is RenderBox && ro.attached && ro.hasSize) {
      final topLeft = ro.localToGlobal(Offset.zero);
      return Rect.fromLTWH(
        topLeft.dx * dpr,
        topLeft.dy * dpr,
        ro.size.width * dpr,
        ro.size.height * dpr,
      );
    }
    final sz = MediaQuery.sizeOf(ctx);
    return Rect.fromLTWH(0, 0, sz.width * dpr, sz.height * dpr);
  }

  @override
  void dispose() {
    _disposed = true;
    AiFaceBeautyManager.instance.removeListener(_onModelStateChanged);
    _nextDetectTimer?.cancel();
    _ticker?.dispose();
    _disposeActiveShader();
    _paintTickNotifier.dispose();
    if (_copyBackRequested) {
      _copyBackRequested = false;
      widget.onCopyBackHwdecRequired?.call(false);
    }
    if (_modelLoadedInRust) {
      unawaited(widget.core.invoke('ai_face_unload_model').catchError((_) => null));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Keep inner RepaintBoundary stable so toggling Plan A never remounts `Video`!
    final rawVideo = RepaintBoundary(
      key: _captureKey,
      child: widget.child,
    );

    if (!_shouldTrack || !AiFaceBeautyShader.isAvailable) {
      _disposeActiveShader();
      return rawVideo;
    }

    return ValueListenableBuilder<int>(
      valueListenable: _paintTickNotifier,
      builder: (ctx, _, child) {
        final built = AiFaceBeautyShader.buildFilterWithHandle(
          viewportScreenRectPx: _resolveViewportScreenRectPx(ctx),
          morph: widget.morph,
          faces: _smoother.smoothed,
        );
        _disposeActiveShader();
        if (built != null) {
          _activeShader = built.shader;
        }
        // Keep ImageFiltered stably mounted (enabled: built != null, matching StretchEffect)
        // so entering/leaving face frames never structurally remounts the video subtree!
        return ImageFiltered(
          imageFilter: built?.filter ?? _identityFilter,
          enabled: built != null,
          child: CustomPaint(
            painter: built != null ? const _ViewportCoveragePainter() : null,
            child: child,
          ),
        );
      },
      child: rawVideo,
    );
  }
}
