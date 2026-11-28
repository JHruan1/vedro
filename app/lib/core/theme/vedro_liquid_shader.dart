import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Real-time Impeller GPU Liquid Glass optical backdrop pipeline
/// grounded in `QmDeve/AndroidLiquidGlassView` & `Kyant0/AndroidLiquidGlass`.
///
/// Renders authentic thick-crystal lens refraction (`refractionHeight` ~20–24dp,
/// `refractionAmount` ~54–68dp), 3D convex dome depth (`depthEffect` ~0.30),
/// 7-band diagonal-quadrant spectral chromatic dispersion (`dispersion` ~0.52),
/// linear-sRGB crystal grading, and Fresnel specular/caustic rim highlights.
///
/// Runs natively via Impeller on Android (Vulkan/GLES), iOS (Metal), and macOS
/// (Metal), and gracefully falls back to `ui.ImageFilter.blur` on Skia backends
/// (Windows/Linux) or headless widget tests.
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

  /// Build the optimal backdrop [ui.ImageFilter] for a glass surface.
  ///
  /// - For floating chrome (`GlassSurface`, `VedroPullDownButton`) pass a light
  ///   [blurSigma] (`2.5–4.5`) so underlying edges stay crisp enough to visibly
  ///   bend & split into chromatic rainbows like `QmDeve/AndroidLiquidGlassView`.
  /// - For text-dense menus & sheets pass a moderate [blurSigma] (`10–14`) so
  ///   underlying text is fully diffused while the curved outer `22dp` bezel
  ///   refracts and disperses surrounding ambient light.
  static ui.ImageFilter buildBackdropFilter({
    required BuildContext context,
    required bool isLight,
    required Color accent,
    required double blurSigma,
    required double borderRadius,
    required bool enableRefraction,
    String liquidSpecular = 'standard',
    double refractionHeightDp = 22.0,
    double refractionAmountDp = 62.0,
    double dispersion = 0.52,
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
      final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2.0;
      final specMul = intensityOverride ??
          switch (liquidSpecular) {
            'subtle' => 0.72,
            'vivid' => 1.32,
            _ => 1.0,
          };
      final refractScale = switch (liquidSpecular) {
        'subtle' => 0.78,
        'vivid' => 1.18,
        _ => 1.0,
      };

      final shader = program.fragmentShader();
      // Uniforms 0, 1: u_size (overwritten by Impeller engine with bound texture pixel size).
      shader.setFloat(0, 0.0);
      shader.setFloat(1, 0.0);
      // Uniform 2: u_radiusPx
      shader.setFloat(2, (borderRadius * dpr).clamp(0.0, 260.0));
      // Uniform 3: u_dpr
      shader.setFloat(3, dpr.clamp(1.0, 4.0));
      // Uniform 4: u_refractionHeightPx
      shader.setFloat(4, (refractionHeightDp * dpr).clamp(8.0, 120.0));
      // Uniform 5: u_refractionAmountPx
      shader.setFloat(5, (refractionAmountDp * refractScale * dpr).clamp(0.0, 260.0));
      // Uniform 6: u_dispersion (0..1 ratio of refraction amount)
      shader.setFloat(6, (dispersion * refractScale).clamp(0.0, 0.95));
      // Uniform 7: u_depthEffect
      shader.setFloat(7, depthEffect.clamp(0.0, 0.6));
      // Uniform 8: u_specIntensity
      shader.setFloat(8, specMul.clamp(0.4, 1.6));
      // Uniform 9: u_isLight
      shader.setFloat(9, isLight ? 1.0 : 0.0);
      // Uniforms 10, 11, 12: u_accent (r, g, b in 0..1)
      shader.setFloat(10, accent.r);
      shader.setFloat(11, accent.g);
      shader.setFloat(12, accent.b);

      // FilterQuality.low uses pure hardware bilinear sampling with ZERO per-frame
      // mipmap pyramid generation on Impeller — critical for locked 120Hz mobile scrolling!
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
