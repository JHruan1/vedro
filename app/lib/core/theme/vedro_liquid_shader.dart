import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Unified optical density presets for Vedro's Liquid Glass material system.
///
/// Guarantees 100% consistent frosted clarity, 360° curved-lens refraction,
/// RGB chromatic dispersion, and specular rim weight across EVERY Liquid Glass
/// surface in the app (dock, top pills, dropdowns, Peek & Pop, sheets, panels).
enum VedroGlassDensity {
  /// Floating chrome: bottom dock, top header pills, action pills, pull-down triggers.
  chrome,

  /// Text-dense overlays: Version / "更多" menus, Peek & Pop menu, modal sheets.
  menu,

  /// Adaptive panels and large glass containers.
  panel,
}

/// Real-time Impeller GPU Liquid Glass optical backdrop pipeline
/// grounded in `QmDeve/AndroidLiquidGlassView` & `whynotmake-it/flutter_liquid_glass`.
///
/// Passes the widget's exact screen-space `u_rect` into `shaders/liquid_glass.frag`
/// on every paint and retained-layer scroll/transform frame so the 360° rounded-rect
/// SDF, curved-lens refraction, prismatic RGB dispersion, and Fresnel rim stay
/// pixel-locked to EVERY glass pill, dock, menu, and sheet across the entire screen.
class VedroLiquidGlassShader {
  VedroLiquidGlassShader._();

  static const String _assetPath = 'shaders/liquid_glass.frag';

  static ui.FragmentProgram? _program;
  static Future<void>? _loadingFuture;

  /// Whether the current runtime supports Impeller `ImageFilter.shader` and
  /// our compiled liquid glass fragment program is loaded.
  static bool get isAvailable =>
      ui.ImageFilter.isShaderFilterSupported && _program != null;

  /// Preload the compiled fragment program once during app startup.
  /// Safe no-op on Skia backends or headless tests.
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

  /// Unified crystal frost blur sigma for Liquid Glass on Impeller GPU.
  /// Never returns 0 — guarantees unmistakable luminous glass depth rather than
  /// raw invisible transparency while preserving crisp 360° curved-bezel bending.
  static double gpuBlurSigma(VedroGlassDensity density) => switch (density) {
        VedroGlassDensity.chrome => 5.5,
        VedroGlassDensity.menu => 12.0,
        VedroGlassDensity.panel => 7.5,
      };

  /// Unified Liquid Glass translucent body tint color for dark & light themes.
  static Color liquidFillColor({
    required bool isLight,
    required Color canvas,
    required Color surface,
    required Color surface2,
    required VedroGlassDensity density,
    bool highlighted = false,
  }) {
    if (isLight) {
      final alpha = switch (density) {
        VedroGlassDensity.chrome => highlighted ? 0.54 : 0.44,
        VedroGlassDensity.menu => 0.72,
        VedroGlassDensity.panel => highlighted ? 0.62 : 0.54,
      };
      return Colors.white.withValues(alpha: alpha);
    }
    final base = switch (density) {
      VedroGlassDensity.chrome => Color.lerp(surface, canvas, 0.35)!,
      VedroGlassDensity.menu => Color.lerp(surface2, surface, 0.32)!,
      VedroGlassDensity.panel => Color.lerp(surface, canvas, 0.25)!,
    };
    final alpha = switch (density) {
      VedroGlassDensity.chrome => highlighted ? 0.48 : 0.38,
      VedroGlassDensity.menu => 0.65,
      VedroGlassDensity.panel => highlighted ? 0.56 : 0.48,
    };
    return base.withValues(alpha: alpha);
  }

  /// Unified interior glass specular sheen gradient (top catchlight + subtle ambient bounce).
  static LinearGradient liquidSheenGradient({
    required bool isLight,
    required Color accent,
    double intensity = 1.0,
    double opacityFactor = 1.0,
  }) {
    final op = opacityFactor.clamp(0.0, 1.0);
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      stops: const [0.0, 0.40, 1.0],
      colors: [
        Colors.white.withValues(
          alpha: ((isLight ? 0.46 : 0.18) * intensity * op).clamp(0.0, 0.64),
        ),
        Colors.white.withValues(
          alpha: ((isLight ? 0.12 : 0.03) * intensity * op).clamp(0.0, 0.24),
        ),
        accent.withValues(alpha: (isLight ? 0.05 : 0.08) * op),
      ],
    );
  }

  /// Build the optimal backdrop [ui.ImageFilter] for a glass surface.
  static ui.ImageFilter buildBackdropFilter({
    BuildContext? context,
    double? devicePixelRatio,
    Rect? screenRect,
    required bool isLight,
    required Color accent,
    required double blurSigma,
    required double borderRadius,
    required bool enableRefraction,
    String liquidSpecular = 'standard',
    double refractionHeightDp = 19.0,
    double refractionAmountDp = 48.0,
    double dispersion = 0.54,
    double depthEffect = 0.30,
    double? intensityOverride,
  }) {
    final hasBlur = blurSigma > 0.15;
    final blurFilter = ui.ImageFilter.blur(
      sigmaX: hasBlur ? blurSigma : 0.0,
      sigmaY: hasBlur ? blurSigma : 0.0,
      tileMode: ui.TileMode.clamp,
    );
    if (!enableRefraction || !isAvailable) {
      return blurFilter;
    }

    final program = _program;
    if (program == null) return blurFilter;

    try {
      final dpr = (devicePixelRatio ??
              (context != null ? MediaQuery.maybeDevicePixelRatioOf(context) : null) ??
              2.0)
          .clamp(1.0, 4.0);
      final specMul = intensityOverride ??
          switch (liquidSpecular) {
            'subtle' => 0.76,
            'vivid' => 1.32,
            _ => 1.0,
          };
      final refractScale = switch (liquidSpecular) {
        'subtle' => 0.80,
        'vivid' => 1.18,
        _ => 1.0,
      };

      final shader = program.fragmentShader();
      // Uniforms 0, 1: u_size (overwritten by Impeller engine with bound pass texture size).
      shader.setFloat(0, 0.0);
      shader.setFloat(1, 0.0);
      // Uniforms 2..5: u_rect (centerX, centerY, halfW, halfH in screen physical pixels).
      if (screenRect != null && !screenRect.isEmpty) {
        shader.setFloat(2, screenRect.center.dx * dpr);
        shader.setFloat(3, screenRect.center.dy * dpr);
        shader.setFloat(4, (screenRect.width * 0.5) * dpr);
        shader.setFloat(5, (screenRect.height * 0.5) * dpr);
      } else {
        shader.setFloat(2, 0.0);
        shader.setFloat(3, 0.0);
        shader.setFloat(4, 0.0);
        shader.setFloat(5, 0.0);
      }
      // Uniform 6: u_radiusPx
      shader.setFloat(6, (borderRadius * dpr).clamp(0.0, 260.0));
      // Uniform 7: u_dpr
      shader.setFloat(7, dpr);
      // Uniform 8: u_refractionHeightPx
      shader.setFloat(8, (refractionHeightDp * dpr).clamp(8.0, 120.0));
      // Uniform 9: u_refractionAmountPx
      shader.setFloat(9, (refractionAmountDp * refractScale * dpr).clamp(0.0, 260.0));
      // Uniform 10: u_dispersion
      shader.setFloat(10, (dispersion * refractScale).clamp(0.0, 0.95));
      // Uniform 11: u_depthEffect
      shader.setFloat(11, depthEffect.clamp(0.0, 0.6));
      // Uniform 12: u_specIntensity
      shader.setFloat(12, specMul.clamp(0.4, 1.6));
      // Uniform 13: u_isLight
      shader.setFloat(13, isLight ? 1.0 : 0.0);
      // Uniforms 14..16: u_accent (r, g, b in 0..1)
      shader.setFloat(14, accent.r);
      shader.setFloat(15, accent.g);
      shader.setFloat(16, accent.b);

      // FilterQuality.low uses pure hardware bilinear sampling with ZERO per-frame
      // mipmap pyramid generation on Impeller — critical for locked 120Hz scrolling.
      final shaderFilter = ui.ImageFilter.shader(
        shader,
        filterQuality: FilterQuality.low,
      );
      if (!hasBlur) return shaderFilter;
      return ui.ImageFilter.compose(
        outer: shaderFilter,
        inner: blurFilter,
      );
    } catch (_) {
      return blurFilter;
    }
  }
}

/// Unified pixel-locked Liquid Glass & Frosted Glass backdrop widget.
///
/// Computes the widget's EXACT screen-space bounding rect inside its RenderObject
/// on every paint AND tracks ancestor scroll/transform motion in retained layers
/// via [_LiquidGlassTransformLayer], so Impeller's full-screen `ImageFilter.shader`
/// locks its 360° rounded-rect SDF, curved-lens refraction, RGB chromatic dispersion,
/// and Fresnel rim pixel-accurately onto this widget anywhere on screen.
class VedroLiquidGlassBackdrop extends SingleChildRenderObjectWidget {
  const VedroLiquidGlassBackdrop({
    super.key,
    required this.borderRadius,
    required this.blurSigma,
    required this.enableRefraction,
    required this.isLight,
    required this.accent,
    this.liquidSpecular = 'standard',
    this.density = VedroGlassDensity.chrome,
    this.refractionHeightDp,
    this.refractionAmountDp,
    this.dispersion,
    this.depthEffect,
    this.intensityOverride,
    this.devicePixelRatio,
    required super.child,
  });

  final double borderRadius;
  final double blurSigma;
  final bool enableRefraction;
  final bool isLight;
  final Color accent;
  final String liquidSpecular;
  final VedroGlassDensity density;
  final double? refractionHeightDp;
  final double? refractionAmountDp;
  final double? dispersion;
  final double? depthEffect;
  final double? intensityOverride;
  final double? devicePixelRatio;

  double get _effRefractionHeight =>
      refractionHeightDp ??
      switch (density) {
        VedroGlassDensity.chrome => 19.0,
        VedroGlassDensity.menu => 22.0,
        VedroGlassDensity.panel => 20.0,
      };

  double get _effRefractionAmount =>
      refractionAmountDp ??
      switch (density) {
        VedroGlassDensity.chrome => 48.0,
        VedroGlassDensity.menu => 54.0,
        VedroGlassDensity.panel => 50.0,
      };

  double get _effDispersion =>
      dispersion ??
      switch (density) {
        VedroGlassDensity.chrome => 0.54,
        VedroGlassDensity.menu => 0.56,
        VedroGlassDensity.panel => 0.52,
      };

  double get _effDepthEffect =>
      depthEffect ??
      switch (density) {
        VedroGlassDensity.chrome => 0.30,
        VedroGlassDensity.menu => 0.28,
        VedroGlassDensity.panel => 0.28,
      };

  @override
  RenderObject createRenderObject(BuildContext context) {
    final dpr = devicePixelRatio ?? MediaQuery.maybeDevicePixelRatioOf(context) ?? 2.0;
    return _RenderVedroLiquidGlassBackdrop(
      borderRadius: borderRadius,
      blurSigma: blurSigma,
      enableRefraction: enableRefraction,
      isLight: isLight,
      accent: accent,
      liquidSpecular: liquidSpecular,
      refractionHeightDp: _effRefractionHeight,
      refractionAmountDp: _effRefractionAmount,
      dispersion: _effDispersion,
      depthEffect: _effDepthEffect,
      intensityOverride: intensityOverride,
      devicePixelRatio: dpr,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderObject renderObject,
  ) {
    final dpr = devicePixelRatio ?? MediaQuery.maybeDevicePixelRatioOf(context) ?? 2.0;
    (renderObject as _RenderVedroLiquidGlassBackdrop).updateParams(
      borderRadius: borderRadius,
      blurSigma: blurSigma,
      enableRefraction: enableRefraction,
      isLight: isLight,
      accent: accent,
      liquidSpecular: liquidSpecular,
      refractionHeightDp: _effRefractionHeight,
      refractionAmountDp: _effRefractionAmount,
      dispersion: _effDispersion,
      depthEffect: _effDepthEffect,
      intensityOverride: intensityOverride,
      devicePixelRatio: dpr,
    );
  }
}

class _RenderVedroLiquidGlassBackdrop extends RenderProxyBox {
  _RenderVedroLiquidGlassBackdrop({
    required double borderRadius,
    required double blurSigma,
    required bool enableRefraction,
    required bool isLight,
    required Color accent,
    required String liquidSpecular,
    required double refractionHeightDp,
    required double refractionAmountDp,
    required double dispersion,
    required double depthEffect,
    required double? intensityOverride,
    required double devicePixelRatio,
  })  : _borderRadius = borderRadius,
        _blurSigma = blurSigma,
        _enableRefraction = enableRefraction,
        _isLight = isLight,
        _accent = accent,
        _liquidSpecular = liquidSpecular,
        _refractionHeightDp = refractionHeightDp,
        _refractionAmountDp = refractionAmountDp,
        _dispersion = dispersion,
        _depthEffect = depthEffect,
        _intensityOverride = intensityOverride,
        _devicePixelRatio = devicePixelRatio;

  double _borderRadius;
  double _blurSigma;
  bool _enableRefraction;
  bool _isLight;
  Color _accent;
  String _liquidSpecular;
  double _refractionHeightDp;
  double _refractionAmountDp;
  double _dispersion;
  double _depthEffect;
  double? _intensityOverride;
  double _devicePixelRatio;

  final LayerHandle<ClipRRectLayer> _clipLayer = LayerHandle<ClipRRectLayer>();
  final LayerHandle<BackdropFilterLayer> _backdropLayer =
      LayerHandle<BackdropFilterLayer>();
  final LayerHandle<_LiquidGlassTransformLayer> _trackingLayer =
      LayerHandle<_LiquidGlassTransformLayer>();

  bool get _hasShader => _enableRefraction && VedroLiquidGlassShader.isAvailable;
  bool get _needsBackdrop => _blurSigma > 0.15 || _hasShader;

  @override
  bool get alwaysNeedsCompositing => _needsBackdrop;

  void updateParams({
    required double borderRadius,
    required double blurSigma,
    required bool enableRefraction,
    required bool isLight,
    required Color accent,
    required String liquidSpecular,
    required double refractionHeightDp,
    required double refractionAmountDp,
    required double dispersion,
    required double depthEffect,
    required double? intensityOverride,
    required double devicePixelRatio,
  }) {
    final wasCompositing = alwaysNeedsCompositing;
    final changed = _borderRadius != borderRadius ||
        _blurSigma != blurSigma ||
        _enableRefraction != enableRefraction ||
        _isLight != isLight ||
        _accent != accent ||
        _liquidSpecular != liquidSpecular ||
        _refractionHeightDp != refractionHeightDp ||
        _refractionAmountDp != refractionAmountDp ||
        _dispersion != dispersion ||
        _depthEffect != depthEffect ||
        _intensityOverride != intensityOverride ||
        _devicePixelRatio != devicePixelRatio;
    if (!changed) return;
    _borderRadius = borderRadius;
    _blurSigma = blurSigma;
    _enableRefraction = enableRefraction;
    _isLight = isLight;
    _accent = accent;
    _liquidSpecular = liquidSpecular;
    _refractionHeightDp = refractionHeightDp;
    _refractionAmountDp = refractionAmountDp;
    _dispersion = dispersion;
    _depthEffect = depthEffect;
    _intensityOverride = intensityOverride;
    _devicePixelRatio = devicePixelRatio;
    if (wasCompositing != alwaysNeedsCompositing) {
      markNeedsCompositingBitsUpdate();
    }
    markNeedsPaint();
  }

  ui.ImageFilter _buildFilter(Matrix4 screenTransform) {
    final screenRect = MatrixUtils.transformRect(screenTransform, Offset.zero & size);
    return VedroLiquidGlassShader.buildBackdropFilter(
      devicePixelRatio: _devicePixelRatio,
      screenRect: screenRect,
      isLight: _isLight,
      accent: _accent,
      blurSigma: _blurSigma,
      borderRadius: _borderRadius,
      enableRefraction: _enableRefraction,
      liquidSpecular: _liquidSpecular,
      refractionHeightDp: _refractionHeightDp,
      refractionAmountDp: _refractionAmountDp,
      dispersion: _dispersion,
      depthEffect: _depthEffect,
      intensityOverride: _intensityOverride,
    );
  }

  /// Called before engine scene submission whenever an ancestor scroll or
  /// transform moves this retained layer without triggering a full repaint.
  void syncRetainedFilter(Matrix4 screenTransform) {
    final backdrop = _backdropLayer.layer;
    if (backdrop == null || !_hasShader || !hasSize || size.isEmpty) return;
    backdrop.filter = _buildFilter(screenTransform);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null || size.isEmpty) return;
    final safeR = _borderRadius.clamp(0.0, math.min(size.width, size.height) * 0.5);
    final rrect = RRect.fromRectAndRadius(offset & size, Radius.circular(safeR));

    if (!_needsBackdrop) {
      _backdropLayer.layer = null;
      _trackingLayer.layer?.targetRenderObject = null;
      _trackingLayer.layer = null;
      if (safeR > 0.0) {
        _clipLayer.layer = context.pushClipRRect(
          needsCompositing,
          offset,
          Offset.zero & size,
          rrect,
          super.paint,
          clipBehavior: Clip.antiAlias,
          oldLayer: _clipLayer.layer,
        );
      } else {
        _clipLayer.layer = null;
        super.paint(context, offset);
      }
      return;
    }

    final screenTransform = getTransformTo(null);
    final filter = _buildFilter(screenTransform);
    final backdrop = BackdropFilterLayer(
      filter: filter,
      blendMode: BlendMode.srcOver,
    );
    _backdropLayer.layer = backdrop;

    void paintBackdrop(PaintingContext ctx, Offset off) {
      ctx.pushLayer(backdrop, super.paint, off);
    }

    void paintInsideClip(PaintingContext ctx, Offset off) {
      if (_hasShader) {
        _trackingLayer.layer?.targetRenderObject = null;
        final tracker = _LiquidGlassTransformLayer()
          ..targetRenderObject = this
          ..lastTransform = screenTransform;
        _trackingLayer.layer = tracker;
        ctx.pushLayer(tracker, paintBackdrop, off);
      } else {
        _trackingLayer.layer?.targetRenderObject = null;
        _trackingLayer.layer = null;
        paintBackdrop(ctx, off);
      }
    }

    _clipLayer.layer = context.pushClipRRect(
      needsCompositing,
      offset,
      Offset.zero & size,
      rrect,
      paintInsideClip,
      clipBehavior: Clip.antiAlias,
      oldLayer: _clipLayer.layer,
    );
  }

  @override
  void dispose() {
    _trackingLayer.layer?.targetRenderObject = null;
    _trackingLayer.layer = null;
    _backdropLayer.layer = null;
    _clipLayer.layer = null;
    super.dispose();
  }
}

class _LiquidGlassTransformLayer extends OffsetLayer {
  _RenderVedroLiquidGlassBackdrop? targetRenderObject;
  Matrix4? lastTransform;

  @override
  void detach() {
    super.detach();
    lastTransform = null;
  }

  @override
  void updateSubtreeNeedsAddToScene() {
    final ro = targetRenderObject;
    if (ro != null && ro.attached && ro.hasSize) {
      final current = ro.getTransformTo(null);
      if (lastTransform == null || !MatrixUtils.matrixEquals(current, lastTransform)) {
        lastTransform = current;
        ro.syncRetainedFilter(current);
      }
    }
    super.updateSubtreeNeedsAddToScene();
  }
}
