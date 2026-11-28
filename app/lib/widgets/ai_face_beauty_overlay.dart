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
/// Updates 34 float uniforms in microseconds at 60/120 Hz with ZERO shader recompilation
/// on iOS Metal, macOS Metal, Android Vulkan, and Android OpenGL ES.
/// On Skia backends (Windows D3D11/ANGLE, Linux OpenGL, or Android with Impeller off),
/// [AiFaceBeautyViewport] seamlessly switches to `libmpv` `//!HOOK MAIN` GPU GLSL via
/// [AiFaceMpvShaderBuilder] so EVERY client platform gets real GPU Slim Face / Big Eyes!
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
      if (PlatformPerfProfile.isIOS) return 'iOS Metal · Impeller GPU 着色器';
      if (PlatformPerfProfile.isMacOS) return 'macOS Metal · Impeller GPU 着色器';
      if (PlatformPerfProfile.isAndroid) return 'Android Vulkan / OpenGL ES · Impeller GPU 着色器';
      return 'Impeller GPU 实时着色器';
    }
    if (PlatformPerfProfile.isWindows) return 'Windows D3D11 / ANGLE · MPV GPU GLSL 钩子';
    if (PlatformPerfProfile.isLinux) return 'Linux OpenGL · MPV GPU GLSL 钩子';
    if (PlatformPerfProfile.isMacOS) return 'macOS Skia · MPV GPU GLSL 钩子';
    if (PlatformPerfProfile.isAndroid) return 'Android Skia · MPV GPU GLSL 钩子';
    return 'MPV GPU GLSL 着色器';
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
  /// on next rebuild / widget dispose to prevent 60fps native uniform buffer leaks.
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
      // 0..1: u_size (populated by Impeller)
      shader.setFloat(0, 0.0);
      shader.setFloat(1, 0.0);
      // 2..5: u_rect (leftPx, topPx, widthPx, heightPx)
      shader.setFloat(2, viewportScreenRectPx.left);
      shader.setFloat(3, viewportScreenRectPx.top);
      shader.setFloat(4, viewportScreenRectPx.width);
      shader.setFloat(5, viewportScreenRectPx.height);
      // 6..9: u_morph (slimFace, bigEyes, vChin, lipTint)
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
        // eyes: (reX, reY, leX, leY)
        shader!.setFloat(baseIdx + 0, f.reX);
        shader.setFloat(baseIdx + 1, f.reY);
        shader.setFloat(baseIdx + 2, f.leX);
        shader.setFloat(baseIdx + 3, f.leY);
        // lower: (noseX, noseY, mouthCenterX, mouthCenterY)
        shader.setFloat(baseIdx + 4, f.noseX);
        shader.setFloat(baseIdx + 5, f.noseY);
        shader.setFloat(baseIdx + 6, f.mouthCenterX);
        shader.setFloat(baseIdx + 7, f.mouthCenterY);
        // meta: (faceW, faceH, mouthW, confidenceAlpha)
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
    this.usingMpvGpuFallback = false,
    this.copyBackHwdecActive = false,
    this.lastError,
  });

  final bool active;
  final int trackedFaces;
  final double lastInferMs;
  final bool gpuWarpSupported;
  final bool usingMpvGpuFallback;
  final bool copyBackHwdecActive;
  final String? lastError;

  String statusBadge() {
    if (!active) return '未启用';
    if (lastError != null && lastError!.isNotEmpty) return '模型待就绪';
    final backend = usingMpvGpuFallback ? 'MPV GPU' : 'GPU';
    if (trackedFaces > 0) {
      return '$backend 追踪 $trackedFaces 张人脸 · ${lastInferMs.round()}ms';
    }
    return '$backend 实时追踪中 · 等待人脸';
  }
}

/// Pure-Dart temporal face tracker that smoothly interpolates 10–13 Hz YuNet detections
/// into jitter-free 60/120 Hz GPU uniforms, with instant snap-reset on hard scene cuts.
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

    // Greedy nearest-center pairing so face #0 and face #1 never swap slots mid-shot.
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

  /// Advance smooth interpolation by [dtSecs]. Returns `true` if uniforms changed visibly.
  bool step(double dtSecs) {
    if (_smoothed.isEmpty && _targets.isEmpty) return false;
    final dt = dtSecs.clamp(0.004, 0.1);
    final posT = 1.0 - math.exp(-dt * 18.0);
    final fadeInT = 1.0 - math.exp(-dt * 12.0);
    final fadeOutT = 1.0 - math.exp(-dt * 11.0);

    final next = <AiTrackedFace>[];
    final count = math.max(_smoothed.length, _targets.length).clamp(0, 2);
    for (var i = 0; i < count; i++) {
      final hasCur = i < _smoothed.length;
      final hasTgt = i < _targets.length;
      if (hasCur && hasTgt) {
        final cur = _smoothed[i];
        final tgt = _targets[i];
        final dx = tgt.centerX - cur.centerX;
        final dy = tgt.centerY - cur.centerY;
        // Large jump without explicit scene_cut -> snap landmarks faster
        final jump = math.sqrt(dx * dx + dy * dy);
        final effT = jump > 0.28 ? 1.0 : posT;
        final nextAlpha = cur.alpha + (1.0 - cur.alpha) * fadeInT;
        next.add(cur.lerpTo(tgt, effT, alphaOverride: nextAlpha));
      } else if (hasTgt) {
        next.add(_targets[i].withAlpha(fadeInT));
      } else if (hasCur) {
        final cur = _smoothed[i];
        final nextAlpha = cur.alpha * (1.0 - fadeOutT);
        if (nextAlpha > 0.01) {
          next.add(cur.withAlpha(nextAlpha));
        }
      }
    }
    _smoothed = next;
    return true;
  }
}

/// Ensures Impeller `ImageFiltered` allocates the full viewport offscreen texture
/// (matching Flutter's own `StretchEffect` `_StretchEffectPainter`) even when the
/// video uses `BoxFit.contain` with letterbox/pillarbox margins.
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

/// Self-contained Cross-Client / Cross-GPU Plan A AI Face Beauty wrapper around `Video(...)`.
///
/// - **Zero-overhead when off**: When disabled, model missing, or morph sliders are 0,
///   renders [child] directly with ZERO `ImageFiltered` overhead, ZERO frame captures,
///   ZERO `hwdec` overrides, and 100% native Dolby Vision / HDR zero-copy playback.
/// - **iOS Metal / macOS Metal / Android Vulkan & OpenGL ES (Impeller)**:
///   Drives `shaders/ai_face_beauty.frag` via `ImageFiltered(ImageFilter.shader)` at 60/120Hz
///   with proper `FragmentShader.dispose()` lifecycle and 4-corner coverage.
/// - **Windows (D3D11/ANGLE) / Linux (OpenGL) / Skia fallback**:
///   Automatically routes video-space tracked faces to [onFallbackMpvFacesChanged] so `libmpv`
///   renders the exact same Slim Face / Big Eyes / V-Chin / Lip Tint in `//!HOOK MAIN` GPU GLSL!
/// - **Android Hardware SurfaceTexture resilience**:
///   Detects black `RepaintBoundary.toImage()` frames on opaque MediaCodec surfaces, falls back
///   to `mpv screenshot-raw` with stride-safe downsampling, and invokes [onCopyBackHwdecRequired]
///   ONLY when zero-copy `mediacodec` blocks raw frame reads (restoring immediately on disable).
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
    this.rawBgraFallbackCapture,
    this.onFallbackMpvFacesChanged,
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
  final Future<Uint8List?> Function()? rawBgraFallbackCapture;
  final ValueChanged<List<AiTrackedFace>>? onFallbackMpvFacesChanged;
  final ValueChanged<bool>? onCopyBackHwdecRequired;
  final Widget child;

  @override
  State<AiFaceBeautyViewport> createState() => _AiFaceBeautyViewportState();
}

class _AiFaceBeautyViewportState extends State<AiFaceBeautyViewport>
    with SingleTickerProviderStateMixin {
  final GlobalKey _captureKey = GlobalKey(debugLabel: 'ai-face-video-capture');
  final AiFaceTemporalSmoother _smoother = AiFaceTemporalSmoother();
  final ValueNotifier<int> _paintTickNotifier = ValueNotifier<int>(0);

  ui.FragmentShader? _activeShader;
  Ticker? _ticker;
  Timer? _detectTimer;
  Duration _lastTick = Duration.zero;
  bool _detectInFlight = false;
  bool _disposed = false;
  bool _modelLoadedInRust = false;
  bool _useFallbackBgra = false;
  bool _copyBackRequested = false;
  int _consecutiveDarkCaptures = 0;
  int _consecutiveNullFallback = 0;

  // Throttling state for Windows/Linux/Skia `libmpv` GLSL face-morph backend
  List<AiTrackedFace> _lastMpvEmittedFaces = const [];
  int _lastMpvEmitMs = 0;

  bool get _useMpvGpuBackend =>
      !AiFaceBeautyShader.isAvailable && widget.onFallbackMpvFacesChanged != null;

  bool get _shouldTrack =>
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
      } else if (_useMpvGpuBackend) {
        _emitMpvFacesIfNeeded(force: true);
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

    if (!_useMpvGpuBackend) {
      if (_ticker == null) {
        _lastTick = Duration.zero;
        _ticker = createTicker(_onAnimTick)..start();
      } else if (!_ticker!.isActive) {
        _lastTick = Duration.zero;
        _ticker!.start();
      }
    } else {
      // On libmpv GLSL backend (Windows/Linux), we emit smoothly on detection cadence
      // rather than burning 60Hz Dart ticks.
      _ticker?.stop();
    }

    _detectTimer?.cancel();
    if (!widget.paused) {
      final intervalMs = _useMpvGpuBackend
          ? 165
          : (PlatformPerfProfile.isMobile ? 105 : 75);
      _detectTimer = Timer.periodic(
        Duration(milliseconds: intervalMs),
        (_) => unawaited(_runSingleDetection()),
      );
    }

    if (triggerImmediate) {
      // Also runs 1 detection when paused so user can preview Slim Face / Big Eyes live on still frames!
      unawaited(_runSingleDetection());
    }
    _emitTelemetry();
  }

  void _stopTracking({required bool unloadModel}) {
    _detectTimer?.cancel();
    _detectTimer = null;
    _ticker?.stop();
    _smoother.reset();
    _disposeActiveShader();
    _paintTickNotifier.value++;

    if (_lastMpvEmittedFaces.isNotEmpty) {
      _lastMpvEmittedFaces = const [];
      widget.onFallbackMpvFacesChanged?.call(const []);
    }
    if (_copyBackRequested) {
      _copyBackRequested = false;
      _consecutiveNullFallback = 0;
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
    final dt = _lastTick == Duration.zero
        ? 0.016
        : ((elapsed - _lastTick).inMicroseconds / 1000000.0);
    _lastTick = elapsed;
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
      gpuWarpSupported: AiFaceBeautyShader.isSupported || widget.onFallbackMpvFacesChanged != null,
      usingMpvGpuFallback: _useMpvGpuBackend,
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

  static bool _facesMovedSignificantly(List<AiTrackedFace> a, List<AiTrackedFace> b) {
    if (a.length != b.length) return true;
    for (var i = 0; i < a.length; i++) {
      final dx = (a[i].centerX - b[i].centerX).abs();
      final dy = (a[i].centerY - b[i].centerY).abs();
      final dw = (a[i].w - b[i].w).abs();
      final da = (a[i].alpha - b[i].alpha).abs();
      if (dx > 0.012 || dy > 0.012 || dw > 0.016 || da > 0.15) return true;
    }
    return false;
  }

  void _emitMpvFacesIfNeeded({bool force = false}) {
    if (!_useMpvGpuBackend) return;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final current = _smoother.smoothed.where((f) => f.alpha > 0.05).toList();
    if (!force &&
        nowMs - _lastMpvEmitMs < 155 &&
        current.length == _lastMpvEmittedFaces.length) {
      return;
    }
    if (!force && !_facesMovedSignificantly(_lastMpvEmittedFaces, current)) {
      return;
    }
    _lastMpvEmitMs = nowMs;
    _lastMpvEmittedFaces = current;
    widget.onFallbackMpvFacesChanged?.call(current);
  }

  Future<({Uint8List bytes, int width, int height, String format, bool fromVideoFrame})?>
      _captureFrame() async {
    if (!_useFallbackBgra) {
      try {
        final ro = _captureKey.currentContext?.findRenderObject();
        if (ro is RenderRepaintBoundary && ro.hasSize && !ro.size.isEmpty) {
          final targetW = PlatformPerfProfile.isMobile ? 256.0 : 320.0;
          final ratio = (targetW / ro.size.width).clamp(0.10, 0.55);
          final img = await ro.toImage(pixelRatio: ratio);
          try {
            final bd = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
            if (bd != null) {
              final bytes = bd.buffer.asUint8List(bd.offsetInBytes, bd.lengthInBytes);
              if (_looksAllBlack(bytes)) {
                _consecutiveDarkCaptures += 1;
                if (_consecutiveDarkCaptures >= 3 && widget.rawBgraFallbackCapture != null) {
                  _useFallbackBgra = true;
                }
              } else {
                _consecutiveDarkCaptures = 0;
                return (
                  bytes: bytes,
                  width: img.width,
                  height: img.height,
                  format: 'rgba',
                  fromVideoFrame: false,
                );
              }
            }
          } finally {
            img.dispose();
          }
        }
      } catch (_) {
        if (widget.rawBgraFallbackCapture != null) {
          _useFallbackBgra = true;
        }
      }
    }

    if (_useFallbackBgra && widget.rawBgraFallbackCapture != null) {
      try {
        final raw = await widget.rawBgraFallbackCapture!();
        if (raw == null || raw.isEmpty) {
          // On Android `hwdec=mediacodec` (zero-copy opaque Surface), `screenshot-raw`
          // returns null until mpv switches to `auto-copy-safe` (`mediacodec-copy`).
          _consecutiveNullFallback += 1;
          if (PlatformPerfProfile.isAndroid &&
              !_copyBackRequested &&
              _consecutiveNullFallback >= 2 &&
              widget.onCopyBackHwdecRequired != null) {
            _copyBackRequested = true;
            widget.onCopyBackHwdecRequired!.call(true);
            _emitTelemetry();
          }
          return null;
        }
        _consecutiveNullFallback = 0;
        if (widget.videoWidth > 0 && widget.videoHeight > 0) {
          final srcW = widget.videoWidth;
          final srcH = widget.videoHeight;
          if (raw.length >= srcW * srcH * 4) {
            // Respect mpv BGRA row-alignment stride (e.g. 854x480 padded to 32-byte rows!)
            final rowBytes =
                (raw.length % srcH == 0) ? (raw.length ~/ srcH) : (srcW * 4);
            final stride = math.max(1, (srcW / 256).ceil());
            final dstW = (srcW / stride).floor();
            final dstH = (srcH / stride).floor();
            if (dstW >= 16 && dstH >= 16 && (dstW - 1) * stride * 4 + 3 < rowBytes) {
              final small = Uint8List(dstW * dstH * 4);
              var outIdx = 0;
              for (var y = 0; y < dstH; y++) {
                final rowOff = (y * stride) * rowBytes;
                for (var x = 0; x < dstW; x++) {
                  final srcOff = rowOff + (x * stride) * 4;
                  small[outIdx++] = raw[srcOff];
                  small[outIdx++] = raw[srcOff + 1];
                  small[outIdx++] = raw[srcOff + 2];
                  small[outIdx++] = raw[srcOff + 3];
                }
              }
              return (
                bytes: small,
                width: dstW,
                height: dstH,
                format: 'bgra',
                fromVideoFrame: true,
              );
            }
          }
        }
      } catch (_) {}
    }
    return null;
  }

  Future<void> _runSingleDetection() async {
    if (_disposed || !mounted || !_shouldTrack || _detectInFlight) return;
    final modelPath = AiFaceBeautyManager.instance.modelFilePath;
    if (modelPath == null || modelPath.isEmpty) return;

    _detectInFlight = true;
    try {
      final frame = await _captureFrame();
      if (_disposed || !mounted || !_shouldTrack || frame == null) return;

      final isMobile = PlatformPerfProfile.isMobile;
      final res = await widget.core.invoke('ai_face_detect', {
        'model_path': modelPath,
        'width': frame.width,
        'height': frame.height,
        'data_b64': base64Encode(frame.bytes),
        'pixel_format': frame.format,
        'infer_w': isMobile ? 256 : 320,
        'infer_h': isMobile ? 160 : 192,
        'score_threshold': 0.62,
        'max_faces': 2,
      });
      if (_disposed || !mounted || !_shouldTrack) return;
      _modelLoadedInRust = true;

      if (res is Map<String, dynamic>) {
        var faces = (res['faces'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(AiTrackedFace.fromJson)
            .toList();

        // Align landmark space to the active GPU backend:
        // - Impeller ImageFilter.shader expects viewport space [0..1]
        // - libmpv //!HOOK MAIN expects decoded video-frame space [0..1]
        final viewSize = _resolveViewportLogicalSize();
        if (!_useMpvGpuBackend && frame.fromVideoFrame) {
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
        } else if (_useMpvGpuBackend && !frame.fromVideoFrame) {
          faces = faces
              .map((f) => AiFaceCoordinateMapper.viewportToVideo(
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
        if (_useMpvGpuBackend) {
          // Advance smoother directly on detection step so libmpv receives smooth steady coords.
          _smoother.step(0.10);
          _emitMpvFacesIfNeeded(force: sceneCut || faces.isEmpty);
        } else {
          _paintTickNotifier.value++;
        }
        _emitTelemetry(inferMs: inferMs, error: null);
      }
    } catch (e) {
      if (!_disposed && mounted) {
        _emitTelemetry(error: e.toString());
      }
    } finally {
      _detectInFlight = false;
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
    _detectTimer?.cancel();
    _ticker?.dispose();
    _disposeActiveShader();
    _paintTickNotifier.dispose();
    if (_lastMpvEmittedFaces.isNotEmpty) {
      _lastMpvEmittedFaces = const [];
      widget.onFallbackMpvFacesChanged?.call(const []);
    }
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
    // Keep inner RepaintBoundary stable so switching Plan A on/off never remounts `Video`!
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
        if (built == null) return child!;
        _activeShader = built.shader;
        return ImageFiltered(
          imageFilter: built.filter,
          child: CustomPaint(
            painter: const _ViewportCoveragePainter(),
            child: child,
          ),
        );
      },
      child: rawVideo,
    );
  }
}
