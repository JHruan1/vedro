import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

/// Stackable, camera-grade portrait beauty parameters (`0.0 ~ 1.0` each).
///
/// Every channel runs strictly inside the GPU portrait shader (zero whole-screen tint veil):
/// - [smooth]: 2-pass separable bilateral surface blur + frequency-separation micro-grain recovery (磨皮)
/// - [whiten]: skin-only Beauty-Camera logarithmic whitening & de-yellowing curve (美白)
/// - [rosy]: skin-only healthy peach-pink complexion + natural lip vitality boost (粉嫩)
/// - [clarity]: facial-feature & eye/eyelash/eyebrow micro-contrast sharpening (亮眼清晰)
class BeautyFilterParams {
  const BeautyFilterParams({
    this.smooth = 0.0,
    this.whiten = 0.0,
    this.rosy = 0.0,
    this.clarity = 0.0,
  });

  static const BeautyFilterParams off = BeautyFilterParams();

  final double smooth;
  final double whiten;
  final double rosy;
  final double clarity;

  bool get isActive =>
      smooth > 0.005 || whiten > 0.005 || rosy > 0.005 || clarity > 0.005;

  BeautyFilterParams clamped() => BeautyFilterParams(
        smooth: smooth.clamp(0.0, 1.0),
        whiten: whiten.clamp(0.0, 1.0),
        rosy: rosy.clamp(0.0, 1.0),
        clarity: clarity.clamp(0.0, 1.0),
      );

  BeautyFilterParams scaled(double strength) {
    final s = strength.clamp(0.0, 1.0);
    return BeautyFilterParams(
      smooth: (smooth * s).clamp(0.0, 1.0),
      whiten: (whiten * s).clamp(0.0, 1.0),
      rosy: (rosy * s).clamp(0.0, 1.0),
      clarity: (clarity * s).clamp(0.0, 1.0),
    );
  }

  BeautyFilterParams copyWith({
    double? smooth,
    double? whiten,
    double? rosy,
    double? clarity,
  }) =>
      BeautyFilterParams(
        smooth: (smooth ?? this.smooth).clamp(0.0, 1.0),
        whiten: (whiten ?? this.whiten).clamp(0.0, 1.0),
        rosy: (rosy ?? this.rosy).clamp(0.0, 1.0),
        clarity: (clarity ?? this.clarity).clamp(0.0, 1.0),
      );

  String summaryLabel() {
    if (!isActive) return '已关闭';
    final parts = <String>[];
    if (smooth > 0.005) parts.add('磨皮 ${(smooth * 100).round()}%');
    if (whiten > 0.005) parts.add('美白 ${(whiten * 100).round()}%');
    if (rosy > 0.005) parts.add('粉嫩 ${(rosy * 100).round()}%');
    if (clarity > 0.005) parts.add('亮眼 ${(clarity * 100).round()}%');
    return parts.join(' · ');
  }

  @override
  bool operator ==(Object other) =>
      other is BeautyFilterParams &&
      (smooth - other.smooth).abs() < 0.001 &&
      (whiten - other.whiten).abs() < 0.001 &&
      (rosy - other.rosy).abs() < 0.001 &&
      (clarity - other.clarity).abs() < 0.001;

  @override
  int get hashCode => Object.hash(
        (smooth * 100).round(),
        (whiten * 100).round(),
        (rosy * 100).round(),
        (clarity * 100).round(),
      );
}

/// Curated camera-grade portrait beauty presets combining stackable [smooth], [whiten],
/// [rosy], and [clarity] channels in a 2-pass GPU mpv shader (zero whole-screen overlay).
class BeautyFilterPreset {
  const BeautyFilterPreset({
    required this.id,
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.smooth,
    required this.whiten,
    required this.rosy,
    required this.clarity,
  });

  final String id;
  final String label;
  final String subtitle;
  final IconData icon;

  final double smooth;
  final double whiten;
  final double rosy;
  final double clarity;

  BeautyFilterParams get params => BeautyFilterParams(
        smooth: smooth,
        whiten: whiten,
        rosy: rosy,
        clarity: clarity,
      );

  BeautyFilterParams scaledParams(double strength) => params.scaled(strength);

  static const List<BeautyFilterPreset> all = [
    BeautyFilterPreset(
      id: 'off',
      label: '原画关闭',
      subtitle: '零额外渲染开销，最省电',
      icon: Icons.hide_image_outlined,
      smooth: 0.0,
      whiten: 0.0,
      rosy: 0.0,
      clarity: 0.0,
    ),
    BeautyFilterPreset(
      id: 'natural',
      label: '综合美颜',
      subtitle: '黄金配比：保边磨皮 + 匀净美白 + 柔和粉嫩 + 亮眼清晰',
      icon: Icons.face_retouching_natural_rounded,
      smooth: 0.58,
      whiten: 0.42,
      rosy: 0.30,
      clarity: 0.40,
    ),
    BeautyFilterPreset(
      id: 'douyin_cream',
      label: '奶油水光',
      subtitle: '抖音风匀肤柔焦 + 奶油水光柔光 + 祛油光 + 清澈亮眼',
      icon: Icons.auto_fix_high_rounded,
      smooth: 0.78,
      whiten: 0.68,
      rosy: 0.36,
      clarity: 0.48,
    ),
    BeautyFilterPreset(
      id: 'cool_white',
      label: '冷白网感',
      subtitle: '强效去暗黄冷白皮 + 肤色匀净祛油光 + 眉眼立体清晰',
      icon: Icons.flare_rounded,
      smooth: 0.66,
      whiten: 0.88,
      rosy: 0.22,
      clarity: 0.54,
    ),
    BeautyFilterPreset(
      id: 'bright',
      label: '清透美白',
      subtitle: '仅提亮肤色与去暗黄，背景与衣物保持 100% 原色',
      icon: Icons.wb_sunny_outlined,
      smooth: 0.52,
      whiten: 0.80,
      rosy: 0.16,
      clarity: 0.34,
    ),
    BeautyFilterPreset(
      id: 'rosy',
      label: '粉嫩元气',
      subtitle: '柔肤磨皮 + 蜜桃红润肤色 + 自然润唇气色',
      icon: Icons.favorite_outline_rounded,
      smooth: 0.62,
      whiten: 0.44,
      rosy: 0.76,
      clarity: 0.38,
    ),
    BeautyFilterPreset(
      id: 'soft_glow',
      label: '奶油磨皮',
      subtitle: '高强度双边保边磨皮淡化毛孔瑕疵，同时保留真实肌肤纹理',
      icon: Icons.auto_awesome_outlined,
      smooth: 0.88,
      whiten: 0.50,
      rosy: 0.32,
      clarity: 0.28,
    ),
    BeautyFilterPreset(
      id: 'vivid',
      label: '立体质感',
      subtitle: '轻度美肤 + 增强眼眸眉发立体清晰度，改善平淡暗沉人像',
      icon: Icons.hd_outlined,
      smooth: 0.36,
      whiten: 0.28,
      rosy: 0.18,
      clarity: 0.74,
    ),
  ];

  static BeautyFilterPreset byId(String id) {
    for (final p in all) {
      if (p.id == id) return p;
    }
    return all.first;
  }

  static String displayLabelFor(String id, BeautyFilterParams params) {
    if (!params.isActive) return '原画关闭';
    if (id == 'custom') return '自定义叠加';
    for (final p in all) {
      if (p.id == id) return p.label;
    }
    return '自定义叠加';
  }
}

class BeautyFilterEngine {
  static const String thermalNotice =
      '提示：采用 2-Pass 人像肤色保边 GPU 着色器（仅作用于人物肤色与五官，背景零偏色），开启后仍会略微增加 GPU 功耗与机身发热；手机端长片建议适度调节或关闭。';

  /// Resolve active [BeautyFilterParams] from saved preset + individual sliders
  /// (seamlessly migrates older saved prefs that only stored preset + strength).
  static BeautyFilterParams resolveParams({
    required String presetId,
    required double strength,
    required double smooth,
    required double whiten,
    required double rosy,
    required double clarity,
  }) {
    final explicit = BeautyFilterParams(
      smooth: smooth,
      whiten: whiten,
      rosy: rosy,
      clarity: clarity,
    ).clamped();
    if (explicit.isActive) return explicit;
    if (presetId == 'off' || presetId == 'custom') return BeautyFilterParams.off;
    return BeautyFilterPreset.byId(presetId).scaledParams(strength.clamp(0.15, 1.0));
  }

  /// Generate a preset-scaled 2-Pass Portrait Beauty Camera GLSL shader.
  /// Returns `null` when `presetId == 'off'`.
  static String? buildGlslSource(
    String presetId,
    double strength, {
    bool mobileLean = false,
  }) {
    final p = BeautyFilterPreset.byId(presetId);
    if (p.id == 'off') return null;
    return buildGlslSourceFromParams(
      p.scaledParams(strength.clamp(0.15, 1.0)),
      label: p.id,
      mobileLean: mobileLean,
    );
  }

  /// Generate a strictly GLSL ES 3.00 & Desktop OpenGL/ANGLE/Metal compatible
  /// 2-Pass Separable Portrait Beauty Camera mpv shader (`//!HOOK MAIN`):
  ///
  /// - **Pass 1 (`//!SAVE VEDRO_SKIN_H`)**: Rotated YCbCr ellipse + RGB dominance
  ///   skin segmentation (`skinMask`) + horizontal resolution-adaptive edge-preserving
  ///   bilateral blur (9-tap desktop / 7-tap mobile = 81-tap / 49-tap 2D equivalent!).
  /// - **Pass 2 (`//!BIND HOOKED`, `//!BIND VEDRO_SKIN_H`)**: Vertical bilateral blur,
  ///   high-pass micro-grain recovery (poreless yet natural, never plastic wax),
  ///   skin-only non-linear Log whitening & de-yellowing, skin & lip rosy vitality,
  ///   and facial-feature / eye micro-clarity USM.
  ///
  /// Zero whole-screen color veil: backgrounds, skies, clothes, subtitles, HDR peaks (>1.0),
  /// and OLED black letterbox bars (`y <= 0.02`) pass through 100% untouched.
  static String? buildGlslSourceFromParams(
    BeautyFilterParams rawParams, {
    String label = 'custom',
    bool mobileLean = false,
  }) {
    final params = rawParams.clamped();
    if (!params.isActive) return null;

    final smoothAmt = params.smooth.toStringAsFixed(4);
    final whitenAmt = params.whiten.toStringAsFixed(4);
    final rosyAmt = params.rosy.toStringAsFixed(4);
    final clarityAmt = params.clarity.toStringAsFixed(4);
    final radius = mobileLean ? 3 : 4;
    final stepBase = mobileLean ? '2.25' : '2.35';
    final invSigmaL = (1.0 / (0.011 + params.smooth * 0.028)).toStringAsFixed(2);
    final invSigmaC = (1.0 / (0.018 + params.smooth * 0.036)).toStringAsFixed(2);

    final hLoop = StringBuffer();
    final vLoop = StringBuffer();
    for (var i = -radius; i <= radius; i++) {
      if (i == 0) continue;
      final fi = i.toDouble().toStringAsFixed(1);
      final spW = _gaussianSpatialWeight(i, radius).toStringAsFixed(4);
      hLoop.writeln('''
    {
        vec3 s = HOOKED_texOff(vec2($fi * stepX, 0.0)).rgb;
        float sy = dot(clamp(s, 0.0, 1.0), vec3(0.299, 0.587, 0.114));
        float dy = sy - cy;
        vec3 dc = clamp(s, 0.0, 1.0) - cc;
        float rw = exp(-(dy * dy * $invSigmaL + dot(dc, dc) * $invSigmaC));
        float w = $spW * rw;
        acc += s * w;
        wSum += w;
    }''');
      vLoop.writeln('''
    {
        vec4 t = VEDRO_SKIN_H_texOff(vec2(0.0, $fi * stepY));
        vec3 s = t.rgb;
        float sy = dot(clamp(s, 0.0, 1.0), vec3(0.299, 0.587, 0.114));
        float dy = sy - cy;
        vec3 dc = clamp(s, 0.0, 1.0) - cc;
        float rw = exp(-(dy * dy * $invSigmaL + dot(dc, dc) * $invSigmaC));
        float w = $spW * rw;
        acc += s * w;
        wSum += w;
        skinAcc += t.a * $spW;
        skinWSum += $spW;
        skinMax = max(skinMax, t.a);
    }''');
    }

    return '''
//!DESC Vedro Portrait Beauty Pass 1 ($label)
//!HOOK MAIN
//!BIND HOOKED
//!SAVE VEDRO_SKIN_H
//!COMPONENTS 4

float vedro_skin_mask(vec3 rgb) {
    vec3 c = clamp(rgb, 0.0, 1.0);
    float y  = dot(c, vec3(0.299, 0.587, 0.114));
    float cb = -0.168736 * c.r - 0.331264 * c.g + 0.500000 * c.b + 0.500000;
    float cr =  0.500000 * c.r - 0.418688 * c.g - 0.081312 * c.b + 0.500000;

    float dx = (cb - 0.418) / 0.086;
    float dy = (cr - 0.588) / 0.088;
    float rx =  0.9063 * dx + 0.4226 * dy;
    float ry = -0.4226 * dx + 0.9063 * dy;
    float ellipse = 1.0 - smoothstep(0.62, 1.28, rx * rx + ry * ry);

    float maxC = max(c.r, max(c.g, c.b));
    float minC = min(c.r, min(c.g, c.b));
    float rgGate = smoothstep(-0.025, 0.032, c.r - c.g);
    float rbGate = smoothstep(0.012, 0.072, c.r - c.b);
    float satGate = smoothstep(0.028, 0.095, maxC - minC);
    float lumaGate = smoothstep(0.10, 0.22, y) * (1.0 - smoothstep(0.92, 0.995, y));

    return clamp(ellipse * rgGate * rbGate * satGate * lumaGate, 0.0, 1.0);
}

vec4 hook() {
    vec4 center = HOOKED_texOff(vec2(0.0, 0.0));
    vec3 c = center.rgb;
    vec3 cc = clamp(c, 0.0, 1.0);
    float cy = dot(cc, vec3(0.299, 0.587, 0.114));
    float skinMask = vedro_skin_mask(cc);

    float scale = clamp(HOOKED_size.y / 1080.0, 0.65, 2.50);
    float stepX = $stepBase * scale;

    vec3 acc = c;
    float wSum = 1.0;
${hLoop.toString()}
    return vec4(acc / wSum, skinMask);
}

//!DESC Vedro Portrait Beauty Pass 2 ($label)
//!HOOK MAIN
//!BIND HOOKED
//!BIND VEDRO_SKIN_H

vec4 hook() {
    vec4 orig = HOOKED_texOff(vec2(0.0, 0.0));
    vec3 c = orig.rgb;
    vec3 cc = clamp(c, 0.0, 1.0);
    vec3 hdrExcess = max(c - vec3(1.0, 1.0, 1.0), vec3(0.0, 0.0, 0.0));
    float cy = dot(cc, vec3(0.299, 0.587, 0.114));

    vec4 hCenter = VEDRO_SKIN_H_texOff(vec2(0.0, 0.0));
    float scale = clamp(HOOKED_size.y / 1080.0, 0.65, 2.50);
    float stepY = $stepBase * scale;

    vec3 acc = hCenter.rgb;
    float wSum = 1.0;
    float skinAcc = hCenter.a;
    float skinWSum = 1.0;
    float skinMax = hCenter.a;
${vLoop.toString()}
    vec3 surfaceBlur = acc / wSum;
    float softSkin = clamp(skinAcc / skinWSum, 0.0, 1.0);
    float skinMask = clamp(max(hCenter.a * 0.65 + softSkin * 0.35, softSkin), 0.0, 1.0);
    float faceRegion = clamp(max(softSkin, skinMax * 0.85), 0.0, 1.0);

    // Fine 4-tap local sample for high-pass skin micro-grain & eye/eyelash clarity
    float fineStep = 1.25 * scale;
    vec3 fineBlur = (
        HOOKED_texOff(vec2( fineStep, 0.0)).rgb +
        HOOKED_texOff(vec2(-fineStep, 0.0)).rgb +
        HOOKED_texOff(vec2(0.0,  fineStep)).rgb +
        HOOKED_texOff(vec2(0.0, -fineStep)).rgb
    ) * 0.25;
    vec3 highPass = cc - clamp(fineBlur, 0.0, 1.0);

    vec3 res = cc;
    float smoothAmt = $smoothAmt;
    float whitenAmt = $whitenAmt;
    float rosyAmt = $rosyAmt;
    float clarityAmt = $clarityAmt;

    // 1. Chroma-first frequency-separation smoothing + oil-shine control (creamy foundation look)
    if (smoothAmt > 0.001) {
        vec3 sBlurC = clamp(surfaceBlur, 0.0, 1.0);
        float edgeDiff = length(cc - sBlurC);
        float edgeProtect = 1.0 - smoothstep(0.055, 0.21, edgeDiff);
        float grainKeep = 0.14 + 0.14 * clarityAmt;
        // Even out blotchy skin chroma stronger than luma so 3D face contours stay natural
        float sBlurY = dot(sBlurC, vec3(0.299, 0.587, 0.114));
        vec3 chromaEven = clamp(vec3(cy) + (sBlurC - vec3(sBlurY)), 0.0, 1.0);
        vec3 smoothSkin = clamp(mix(chromaEven, sBlurC, 0.74) + clamp(highPass, -0.036, 0.036) * grainKeep, 0.0, 1.0);
        float blendW = clamp(smoothAmt * skinMask * (0.30 + 0.70 * edgeProtect), 0.0, 0.95);
        res = mix(res, smoothSkin, blendW);

        // Suppress greasy T-zone specular hot-spots toward soft velvety surfaceBlur
        float oilGate = smoothstep(0.70, 0.90, cy) * skinMask * smoothAmt;
        res = mix(res, min(res, sBlurC + vec3(0.035)), oilGate * 0.42);
        // Gentle under-eye & nasolabial shadow softening strictly on skin
        float shadowGate = smoothstep(0.10, 0.26, cy) * (1.0 - smoothstep(0.42, 0.68, cy));
        res = res + vec3(0.048, 0.044, 0.042) * (smoothAmt * skinMask * shadowGate);
    }

    // 2. Skin-only cool-porcelain Log whitening + sallow yellow removal + dewy soft-light glow
    if (whitenAmt > 0.001) {
        float beta = 1.0 + whitenAmt * 3.15;
        vec3 safeRes = max(res, vec3(0.0, 0.0, 0.0));
        vec3 logWhite = log(vec3(1.0, 1.0, 1.0) + safeRes * (beta - 1.0)) / log(beta);
        float yellowCast = clamp((res.r + res.g) * 0.5 - res.b, 0.0, 0.48);
        vec3 deYellow = logWhite + vec3(-0.012, 0.006, 0.068) * (yellowCast * whitenAmt);
        // Subtle Douyin dewy soft-focus screen bloom strictly inside luminous skin tones
        vec3 sBlurGlow = clamp(surfaceBlur, 0.0, 1.0);
        vec3 dewyGlow = vec3(1.0) - (vec3(1.0) - clamp(deYellow, 0.0, 1.0)) * (vec3(1.0) - sBlurGlow * 0.28);
        float glowMix = clamp(whitenAmt * (0.22 + 0.28 * smoothAmt) * smoothstep(0.28, 0.78, cy), 0.0, 0.46);
        vec3 brightSkin = mix(clamp(deYellow, 0.0, 1.0), dewyGlow, glowMix);
        float whiteWeight = clamp(skinMask * (0.64 + 0.32 * whitenAmt), 0.0, 0.94);
        res = mix(res, clamp(brightSkin, 0.0, 1.0), whiteWeight);
    }

    // 3. Skin-only healthy rosy peach complexion + natural lip vitality
    if (rosyAmt > 0.001) {
        float ry = dot(res, vec3(0.299, 0.587, 0.114));
        float midSkin = smoothstep(0.14, 0.30, ry) * (1.0 - smoothstep(0.84, 0.98, ry));
        vec3 peachShift = vec3(0.072, -0.016, 0.012) * (rosyAmt * skinMask * midSkin);
        res = clamp(res + peachShift, 0.0, 1.0);
        // Subtle warm healthy saturation boost strictly on skin
        vec3 gray = vec3(ry, ry, ry);
        res = mix(res, clamp(mix(gray, res, 1.0 + 0.16 * rosyAmt), 0.0, 1.0), skinMask * midSkin);

        // Natural lip vitality detection inside face neighborhood
        float lcb = -0.168736 * cc.r - 0.331264 * cc.g + 0.500000 * cc.b + 0.500000;
        float lcr =  0.500000 * cc.r - 0.418688 * cc.g - 0.081312 * cc.b + 0.500000;
        float lipMask = faceRegion
            * smoothstep(0.545, 0.60, lcr)
            * (1.0 - smoothstep(0.45, 0.50, lcb))
            * smoothstep(0.06, 0.14, cc.r - cc.g)
            * smoothstep(0.14, 0.24, cy) * (1.0 - smoothstep(0.60, 0.78, cy));
        res = clamp(res + vec3(0.065, -0.022, 0.010) * (rosyAmt * lipMask), 0.0, 1.0);
    }

    // 4. Portrait eye, eyelash, eyebrow & hair micro-clarity right next to smoothed skin
    if (clarityAmt > 0.001) {
        float detailMag = length(highPass);
        float featureMask = faceRegion * (1.0 - skinMask * 0.62) * smoothstep(0.012, 0.075, detailMag);
        res = clamp(res + clamp(highPass, -0.14, 0.14) * (clarityAmt * 0.78 * featureMask), 0.0, 1.0);
        // Subtle eye-catchlight crispness on bright facial accents
        float eyeHighlight = faceRegion * (1.0 - skinMask) * smoothstep(0.55, 0.85, cy) * smoothstep(0.02, 0.08, detailMag);
        res = clamp(res + vec3(0.055, 0.055, 0.058) * (clarityAmt * eyeHighlight), 0.0, 1.0);
    }

    // Keep pure OLED black bars strictly 0.0 and preserve HDR highlight headroom
    float blackProtect = smoothstep(0.012, 0.04, cy);
    vec3 finalRgb = mix(cc, res, blackProtect) + hdrExcess;
    return vec4(max(finalRgb, vec3(0.0, 0.0, 0.0)), orig.a);
}
''';
  }

  static double _gaussianSpatialWeight(int offset, int radius) {
    final norm = offset / (radius + 0.5);
    return (1.0 - 0.55 * norm * norm).clamp(0.25, 1.0);
  }

  /// Write the verified 2-pass beauty shader for a preset+strength pair.
  static Future<String?> prepareShaderFile(
    String presetId,
    double strength, {
    bool mobileLean = false,
  }) async {
    final p = BeautyFilterPreset.byId(presetId);
    if (p.id == 'off') return null;
    return prepareShaderFileForParams(
      p.scaledParams(strength.clamp(0.15, 1.0)),
      label: p.id,
      mobileLean: mobileLean,
    );
  }

  /// Write the verified 2-pass beauty shader for arbitrary stackable [BeautyFilterParams]
  /// to the app's private support directory and return its path.
  static Future<String?> prepareShaderFileForParams(
    BeautyFilterParams rawParams, {
    String label = 'custom',
    bool mobileLean = false,
  }) async {
    final params = rawParams.clamped();
    final src = buildGlslSourceFromParams(
      params,
      label: label,
      mobileLean: mobileLean,
    );
    if (src == null) return null;
    final bSmooth = (params.smooth * 20).round();
    final bWhiten = (params.whiten * 20).round();
    final bRosy = (params.rosy * 20).round();
    final bClarity = (params.clarity * 20).round();
    final tier = mobileLean ? 'm' : 'd';

    final Directory support;
    try {
      support = await getApplicationSupportDirectory();
    } catch (_) {
      return null;
    }
    final dir = Directory('${support.path}/vedro_shaders_v4');
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    } else {
      // Bound cached shader files so frequent slider tweaking never bloats storage
      try {
        final files = dir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.glsl'))
            .toList();
        if (files.length > 36) {
          files.sort((a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()));
          for (final stale in files.take(files.length - 24)) {
            try {
              stale.deleteSync();
            } catch (_) {}
          }
        }
      } catch (_) {}
    }
    final file = File(
      '${dir.path}/beauty_v4_${tier}_${bSmooth}_${bWhiten}_${bRosy}_$bClarity.glsl',
    );
    await file.writeAsString(src);
    return file.path;
  }
}
