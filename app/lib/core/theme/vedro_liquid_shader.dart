import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Real-time Impeller GPU Liquid Glass optical backdrop pipeline.
///
/// Combines a Gaussian inner backdrop blur (ensuring underlying text is always
/// smoothly diffused and never sharply legible through menus/sheets) with a
/// custom GLSL fragment shader (`shaders/liquid_glass.frag`) that computes:
/// - Rounded-rectangle SDF & analytical surface normals
/// - Convex curved-bezel lens refraction (inspired by Kyant0/AndroidLiquidGlass)
/// - Physical Cauchy RGB chromatic dispersion along the curved rim
/// - Apple-style vibrancy saturation lift & sub-surface Fresnel/caustic rim glow
///
/// Runs natively via Impeller on Android (Vulkan/GLES), iOS (Metal), and macOS
/// (Metal), and automatically falls back to standard `ui.ImageFilter.blur` on
/// Skia backends (Windows/Linux) or headless widget tests.
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
      // Silently fall back to standard Gaussian blur if shader asset is unavailable.
      _program = null;
    }
  }

  /// Build the optimal backdrop [ui.ImageFilter] for a glass surface.
  ///
  /// When [enableRefraction] is true (for `ios_liquid_glass`) and Impeller
  /// shader filters are active, returns `ImageFilter.compose(outer: shader,
  /// inner: blur)` so the shader refracts & disperses an already-blurred live
  /// backdrop. Otherwise returns a crisp Gaussian `ImageFilter.blur`.
  static ui.ImageFilter buildBackdropFilter({
    required BuildContext context,
    required bool isLight,
    required Color accent,
    required double blurSigma,
    required double borderRadius,
    required bool enableRefraction,
    String liquidSpecular = 'balanced',
    double refractionDp = 12.5,
    double dispersionDp = 2.2,
    double? intensityOverride,
  }) {
    final blurFilter = ui.ImageFilter.blur(
      sigmaX: blurSigma,
      sigmaY: blurSigma,
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
            'subtle' => 0.65,
            'vivid' => 1.35,
            _ => 1.0,
          };
      final refractScale = switch (liquidSpecular) {
        'subtle' => 0.78,
        'vivid' => 1.24,
        _ => 1.0,
      };

      final shader = program.fragmentShader();
      // Uniforms 0, 1: u_size (overwritten by Impeller engine with bound texture pixel size).
      shader.setFloat(0, 0.0);
      shader.setFloat(1, 0.0);
      // Uniform 2: u_radiusPx
      shader.setFloat(2, (borderRadius * dpr).clamp(0.0, 240.0));
      // Uniform 3: u_dpr
      shader.setFloat(3, dpr.clamp(1.0, 4.0));
      // Uniform 4: u_refractionPx
      shader.setFloat(4, (refractionDp * refractScale * dpr).clamp(0.0, 84.0));
      // Uniform 5: u_dispersionPx
      shader.setFloat(5, (dispersionDp * refractScale * dpr).clamp(0.0, 18.0));
      // Uniform 6: u_specIntensity
      shader.setFloat(6, specMul.clamp(0.4, 1.6));
      // Uniform 7: u_isLight
      shader.setFloat(7, isLight ? 1.0 : 0.0);
      // Uniforms 8, 9, 10: u_accent (r, g, b in 0..1)
      shader.setFloat(8, accent.r);
      shader.setFloat(9, accent.g);
      shader.setFloat(10, accent.b);

      final shaderFilter = ui.ImageFilter.shader(
        shader,
        filterQuality: FilterQuality.medium,
      );
      return ui.ImageFilter.compose(
        outer: shaderFilter,
        inner: blurFilter,
      );
    } catch (_) {
      return blurFilter;
    }
  }
}
