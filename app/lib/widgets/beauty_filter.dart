import 'dart:io';

import 'package:flutter/material.dart';

/// Ultra-lightweight, single-pass GPU Beauty Filter presets for libmpv.
///
/// Design for minimal mobile heat & battery impact:
/// - When `off`, ZERO GLSL shaders are mounted (`glsl-shaders=""`).
/// - Active presets use a single 5-tap YCbCr skin-tone-masked edge-preserving fragment hook
///   (~4 neighbor taps/pixel, ~0.2ms on modern mobile GPUs) so eyes, hair, and details remain
///   sharp while skin is gently smoothed and brightened without heavy multi-pass blur heat.
class BeautyFilterPreset {
  const BeautyFilterPreset({
    required this.id,
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.smooth,
    required this.brighten,
    required this.warmth,
    required this.rosy,
    required this.glow,
    required this.contrast,
    required this.eqBrightness,
    required this.eqContrast,
    required this.eqSaturation,
    required this.eqGamma,
  });

  final String id;
  final String label;
  final String subtitle;
  final IconData icon;

  // Single-pass GPU shader weights (scaled by user strength 0.15..1.0)
  final double smooth;
  final double brighten;
  final double warmth;
  final double rosy;
  final double glow;
  final double contrast;

  // Zero-cost mpv YUV->RGB matrix EQ fallback deltas
  final int eqBrightness;
  final int eqContrast;
  final int eqSaturation;
  final int eqGamma;

  static const List<BeautyFilterPreset> all = [
    BeautyFilterPreset(
      id: 'off',
      label: '原画关闭',
      subtitle: '零额外 GPU 开销，最省电',
      icon: Icons.hide_image_outlined,
      smooth: 0.0,
      brighten: 0.0,
      warmth: 0.0,
      rosy: 0.0,
      glow: 0.0,
      contrast: 0.0,
      eqBrightness: 0,
      eqContrast: 0,
      eqSaturation: 0,
      eqGamma: 0,
    ),
    BeautyFilterPreset(
      id: 'natural',
      label: '自然清透',
      subtitle: '轻度肤色磨皮 + 微提亮，低功耗首选',
      icon: Icons.face_retouching_natural_rounded,
      smooth: 0.42,
      brighten: 0.045,
      warmth: 0.015,
      rosy: 0.02,
      glow: 0.04,
      contrast: 0.02,
      eqBrightness: 2,
      eqContrast: 1,
      eqSaturation: 2,
      eqGamma: 3,
    ),
    BeautyFilterPreset(
      id: 'rosy',
      label: '粉嫩气色',
      subtitle: '柔肤磨皮 + 红润暖粉肤色',
      icon: Icons.favorite_outline_rounded,
      smooth: 0.56,
      brighten: 0.055,
      warmth: 0.035,
      rosy: 0.065,
      glow: 0.07,
      contrast: 0.02,
      eqBrightness: 3,
      eqContrast: 2,
      eqSaturation: 5,
      eqGamma: 4,
    ),
    BeautyFilterPreset(
      id: 'bright',
      label: '白皙通透',
      subtitle: '肤色提亮去黄 + 清爽柔肤',
      icon: Icons.wb_sunny_outlined,
      smooth: 0.52,
      brighten: 0.085,
      warmth: -0.025,
      rosy: 0.025,
      glow: 0.06,
      contrast: 0.03,
      eqBrightness: 5,
      eqContrast: 2,
      eqSaturation: -2,
      eqGamma: 6,
    ),
    BeautyFilterPreset(
      id: 'soft_glow',
      label: '电影柔光',
      subtitle: '日系柔焦高光 + 细腻肤质',
      icon: Icons.auto_awesome_outlined,
      smooth: 0.64,
      brighten: 0.06,
      warmth: 0.025,
      rosy: 0.03,
      glow: 0.14,
      contrast: -0.02,
      eqBrightness: 3,
      eqContrast: -2,
      eqSaturation: 3,
      eqGamma: 5,
    ),
    BeautyFilterPreset(
      id: 'vivid',
      label: '高清通透',
      subtitle: '改善暗沉片源 + 轻度美肤增艳',
      icon: Icons.hd_outlined,
      smooth: 0.34,
      brighten: 0.04,
      warmth: 0.01,
      rosy: 0.02,
      glow: 0.02,
      contrast: 0.09,
      eqBrightness: 2,
      eqContrast: 6,
      eqSaturation: 8,
      eqGamma: 3,
    ),
  ];

  static BeautyFilterPreset byId(String id) {
    for (final p in all) {
      if (p.id == id) return p;
    }
    return all.first;
  }
}

class BeautyFilterEngine {
  static const String thermalNotice =
      '提示：美颜滤镜采用低开销单通道 GPU 着色器，但开启后仍会略微增加功耗与机身发热；手机端长时间观看建议优先使用「自然清透」或关闭。';

  /// Generate a tiny, single-pass 5-tap YCbCr skin-tone edge-preserving mpv GLSL shader.
  /// Returns `null` when `presetId == 'off'`.
  static String? buildGlslSource(String presetId, double strength) {
    final p = BeautyFilterPreset.byId(presetId);
    if (p.id == 'off') return null;

    final s = strength.clamp(0.15, 1.0);
    final smooth = (p.smooth * s).toStringAsFixed(4);
    final brighten = (p.brighten * s).toStringAsFixed(4);
    final warmth = (p.warmth * s).toStringAsFixed(4);
    final rosy = (p.rosy * s).toStringAsFixed(4);
    final glow = (p.glow * s).toStringAsFixed(4);
    final contrast = (p.contrast * s).toStringAsFixed(4);

    return '''
//!DESC Vedro Low-Power Beauty Filter (${p.id})
//!HOOK MAIN
//!BIND HOOKED

vec4 hook() {
    vec4 center = HOOKED_texOff(0);
    vec3 c = center.rgb;

    // Lightweight YCbCr skin-tone mask (keeps eyes, hair, background & subtitles crisp)
    float y  = dot(c, vec3(0.299, 0.587, 0.114));
    float cb = -0.168736 * c.r - 0.331264 * c.g + 0.5 * c.b + 0.5;
    float cr =  0.5 * c.r - 0.418688 * c.g - 0.081312 * c.b + 0.5;
    float skinMask = smoothstep(0.31, 0.37, cb) * (1.0 - smoothstep(0.47, 0.53, cb))
                   * smoothstep(0.51, 0.56, cr) * (1.0 - smoothstep(0.66, 0.72, cr))
                   * smoothstep(0.12, 0.24, y);

    // 4-tap diagonal edge-preserving bilateral sample (ultra low GPU cost)
    vec3 s1 = HOOKED_texOff(vec2( 1.5,  1.5)).rgb;
    vec3 s2 = HOOKED_texOff(vec2(-1.5,  1.5)).rgb;
    vec3 s3 = HOOKED_texOff(vec2( 1.5, -1.5)).rgb;
    vec3 s4 = HOOKED_texOff(vec2(-1.5, -1.5)).rgb;

    float w1 = exp(-dot(s1 - c, s1 - c) * 42.0);
    float w2 = exp(-dot(s2 - c, s2 - c) * 42.0);
    float w3 = exp(-dot(s3 - c, s3 - c) * 42.0);
    float w4 = exp(-dot(s4 - c, s4 - c) * 42.0);
    vec3 blurred = (c + s1 * w1 + s2 * w2 + s3 * w3 + s4 * w4) / (1.0 + w1 + w2 + w3 + w4);

    // Apply skin-selective smoothing
    vec3 res = mix(c, blurred, $smooth * skinMask);

    // Gentle highlight bloom / soft glow
    float hi = smoothstep(0.55, 0.98, y);
    res += (blurred - res) * ($glow * hi * 0.65) + vec3($glow * hi * 0.06);

    // Skin-weighted brighten, warmth & rosy blush
    float lift = $brighten * (0.45 + 0.55 * skinMask);
    res += vec3(lift);
    res.r += ($warmth + $rosy) * skinMask;
    res.g += ($warmth * 0.35 - $rosy * 0.18) * skinMask;
    res.b += (-$warmth * 0.85 + $rosy * 0.22) * skinMask;

    // Micro contrast polish
    res = (res - 0.5) * (1.0 + $contrast) + 0.5;
    return vec4(clamp(res, 0.0, 1.0), center.a);
}
''';
  }

  /// Write the single-pass shader to a cached file in system temp dir and return its path.
  /// Returns `null` when `presetId == 'off'`.
  static Future<String?> prepareShaderFile(String presetId, double strength) async {
    final src = buildGlslSource(presetId, strength);
    if (src == null) return null;
    final bucket = (strength.clamp(0.15, 1.0) * 20).round();
    final dir = Directory('${Directory.systemTemp.path}/vedro_shaders');
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    final file = File('${dir.path}/beauty_${presetId}_$bucket.glsl');
    await file.writeAsString(src);
    return file.path;
  }
}
