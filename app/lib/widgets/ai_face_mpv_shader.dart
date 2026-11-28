import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import '../core/services/ai_face_beauty_manager.dart';
import 'beauty_filter.dart';

/// Pure coordinate projection between decoded video-frame space `[0..1]` and
/// Flutter viewport space `[0..1]` under `BoxFit.contain` / `BoxFit.cover` / `BoxFit.fill`.
///
/// Essential so 2.39:1 cinema movies, 4:3 classics, and vertical videos stay pixel-locked
/// across BOTH pipelines:
/// - Impeller `ImageFilter.shader` (operates in viewport space; needs `videoToViewport`
///   when frames come from `mpv screenshot-raw` fallback).
/// - `libmpv` `//!HOOK MAIN` GLSL shader on Windows (D3D11/ANGLE), Linux (OpenGL), and
///   Skia fallback (operates in video-frame space; needs `viewportToVideo` when frames
///   come from `RepaintBoundary.toImage()`).
class AiFaceCoordinateMapper {
  AiFaceCoordinateMapper._();

  static ({double offX, double offY, double drawW, double drawH}) _fittedRect({
    required double videoW,
    required double videoH,
    required double viewW,
    required double viewH,
    required BoxFit fit,
  }) {
    if (videoW <= 0 || videoH <= 0 || viewW <= 0 || viewH <= 0) {
      return (offX: 0.0, offY: 0.0, drawW: viewW, drawH: viewH);
    }
    if (fit == BoxFit.fill) {
      return (offX: 0.0, offY: 0.0, drawW: viewW, drawH: viewH);
    }
    final sx = viewW / videoW;
    final sy = viewH / videoH;
    final scale = fit == BoxFit.cover ? math.max(sx, sy) : math.min(sx, sy);
    final drawW = videoW * scale;
    final drawH = videoH * scale;
    return (
      offX: (viewW - drawW) * 0.5,
      offY: (viewH - drawH) * 0.5,
      drawW: drawW,
      drawH: drawH,
    );
  }

  /// Map normalized video-frame coordinates `[0..1]` into normalized viewport coordinates `[0..1]`.
  static AiTrackedFace videoToViewport(
    AiTrackedFace f, {
    required int videoW,
    required int videoH,
    required double viewW,
    required double viewH,
    required BoxFit fit,
  }) {
    if (videoW <= 0 || videoH <= 0 || viewW <= 0 || viewH <= 0 || fit == BoxFit.fill) {
      return f;
    }
    final r = _fittedRect(
      videoW: videoW.toDouble(),
      videoH: videoH.toDouble(),
      viewW: viewW,
      viewH: viewH,
      fit: fit,
    );
    double mx(double x) => ((r.offX + x * r.drawW) / viewW).clamp(0.0, 1.0);
    double my(double y) => ((r.offY + y * r.drawH) / viewH).clamp(0.0, 1.0);
    return AiTrackedFace(
      x: mx(f.x),
      y: my(f.y),
      w: (f.w * r.drawW / viewW).clamp(0.0, 1.0),
      h: (f.h * r.drawH / viewH).clamp(0.0, 1.0),
      score: f.score,
      reX: mx(f.reX),
      reY: my(f.reY),
      leX: mx(f.leX),
      leY: my(f.leY),
      noseX: mx(f.noseX),
      noseY: my(f.noseY),
      rmX: mx(f.rmX),
      rmY: my(f.rmY),
      lmX: mx(f.lmX),
      lmY: my(f.lmY),
      alpha: f.alpha,
    );
  }

  /// Map normalized viewport coordinates `[0..1]` into normalized video-frame coordinates `[0..1]`.
  static AiTrackedFace viewportToVideo(
    AiTrackedFace f, {
    required int videoW,
    required int videoH,
    required double viewW,
    required double viewH,
    required BoxFit fit,
  }) {
    if (videoW <= 0 || videoH <= 0 || viewW <= 0 || viewH <= 0 || fit == BoxFit.fill) {
      return f;
    }
    final r = _fittedRect(
      videoW: videoW.toDouble(),
      videoH: videoH.toDouble(),
      viewW: viewW,
      viewH: viewH,
      fit: fit,
    );
    if (r.drawW <= 1e-3 || r.drawH <= 1e-3) return f;
    double mx(double x) => ((x * viewW - r.offX) / r.drawW).clamp(0.0, 1.0);
    double my(double y) => ((y * viewH - r.offY) / r.drawH).clamp(0.0, 1.0);
    return AiTrackedFace(
      x: mx(f.x),
      y: my(f.y),
      w: (f.w * viewW / r.drawW).clamp(0.0, 1.0),
      h: (f.h * viewH / r.drawH).clamp(0.0, 1.0),
      score: f.score,
      reX: mx(f.reX),
      reY: my(f.reY),
      leX: mx(f.leX),
      leY: my(f.leY),
      noseX: mx(f.noseX),
      noseY: my(f.noseY),
      rmX: mx(f.rmX),
      rmY: my(f.rmY),
      lmX: mx(f.lmX),
      lmY: my(f.lmY),
      alpha: f.alpha,
    );
  }
}

/// Cross-GPU `libmpv` `//!HOOK MAIN` GLSL generator for Plan A AI Face Morph.
///
/// Gives Windows (ANGLE/D3D11), Linux (OpenGL), and Skia-fallback Android/macOS
/// clients the EXACT same real-time GPU Slim Face / Big Eyes / V-Chin / teeth-protected
/// Lip Tint as Impeller Metal/Vulkan/GLES — and seamlessly chains AFTER Plan B's
/// 2-Pass Portrait Beauty shader inside a single `.glsl` file so both pipelines
/// work simultaneously with zero `glsl-shaders` path-separator conflicts!
class AiFaceMpvShaderBuilder {
  AiFaceMpvShaderBuilder._();

  static String _f(double v) => v.toStringAsFixed(5);

  /// Build a standalone `//!HOOK MAIN` mpv GPU shader pass for up to 2 tracked faces.
  /// Returns `null` when morph sliders are inactive or no visible faces exist.
  static String? buildFaceMorphPassGlsl({
    required AiFaceMorphParams morph,
    required List<AiTrackedFace> faces,
  }) {
    final m = morph.clamped();
    if (!m.isActive) return null;
    final activeFaces = faces.where((f) => f.alpha > 0.01 && f.w > 0.015 && f.h > 0.02).take(2).toList();
    if (activeFaces.isEmpty) return null;

    String faceVec(AiTrackedFace? f) {
      if (f == null) {
        return 'vec4(0.0), vec4(0.0), vec4(0.0)';
      }
      return 'vec4(${_f(f.reX)}, ${_f(f.reY)}, ${_f(f.leX)}, ${_f(f.leY)}), '
          'vec4(${_f(f.noseX)}, ${_f(f.noseY)}, ${_f(f.mouthCenterX)}, ${_f(f.mouthCenterY)}), '
          'vec4(${_f(f.w)}, ${_f(f.h)}, ${_f(f.mouthWidth)}, ${_f(f.alpha.clamp(0.0, 1.0))})';
    }

    final f0Args = faceVec(activeFaces[0]);
    final f1Args = faceVec(activeFaces.length > 1 ? activeFaces[1] : null);
    final morphVec =
        'vec4(${_f(m.slimFace)}, ${_f(m.bigEyes)}, ${_f(m.vChin)}, ${_f(m.lipTint)})';

    return '''
//!DESC Vedro AI Face Morph Pass (Plan A GPU)
//!HOOK MAIN
//!BIND HOOKED

vec2 vedro_safe_norm(vec2 v, vec2 fallback) {
    float l = length(v);
    return l > 1e-4 ? (v / l) : fallback;
}

vec2 vedro_face_warp_iso(vec2 pIso, vec2 aspect, vec4 eyes, vec4 lower, vec4 meta, vec4 morph) {
    float alpha = clamp(meta.w, 0.0, 1.0);
    if (alpha < 0.005 || meta.x < 0.015 || meta.y < 0.02) {
        return vec2(0.0, 0.0);
    }
    vec2 re = eyes.xy * aspect;
    vec2 le = eyes.zw * aspect;
    vec2 nose = lower.xy * aspect;
    vec2 mouth = lower.zw * aspect;
    vec2 eyeVec = le - re;
    float iod = length(eyeVec);
    if (iod < 0.012) {
        return vec2(0.0, 0.0);
    }
    vec2 uAxis = eyeVec / iod;
    vec2 vAxis = vec2(-uAxis.y, uAxis.x);
    if (dot(mouth - (re + le) * 0.5, vAxis) < 0.0) {
        vAxis = -vAxis;
    }
    vec2 eyeMid = (re + le) * 0.5;
    float faceW = max(meta.x * aspect.x, iod * 2.15);
    float faceH = max(meta.y * aspect.y, length(mouth - eyeMid) * 2.45);
    float yaw = clamp(dot(nose - eyeMid, uAxis) / max(iod * 0.52, 0.01), -0.75, 0.75);
    float rightSideVis = clamp(1.0 - max(yaw, 0.0) * 0.65, 0.25, 1.0);
    float leftSideVis = clamp(1.0 - max(-yaw, 0.0) * 0.65, 0.25, 1.0);
    vec2 disp = vec2(0.0, 0.0);

    float eyeAmt = clamp(morph.y, 0.0, 1.0) * alpha;
    if (eyeAmt > 0.002) {
        float eyeR = clamp(iod * 0.44, 0.018, 0.16);
        float eyeR2 = eyeR * eyeR;
        float gain = eyeAmt * 0.25;
        vec2 dR = pIso - re;
        float distR2 = dot(dR, dR);
        if (distR2 < eyeR2) {
            float fall = 1.0 - distR2 / eyeR2;
            disp -= dR * (gain * fall * fall);
        }
        vec2 dL = pIso - le;
        float distL2 = dot(dL, dL);
        if (distL2 < eyeR2) {
            float fall = 1.0 - distL2 / eyeR2;
            disp -= dL * (gain * fall * fall);
        }
    }

    float slimAmt = clamp(morph.x, 0.0, 1.0) * alpha;
    if (slimAmt > 0.002) {
        vec2 target = mouth + vAxis * (faceH * 0.12);
        float cheekRad = clamp(faceW * 0.56, 0.035, 0.34);
        float cheekRad2 = cheekRad * cheekRad;
        vec2 cheekR = eyeMid + vAxis * (faceH * 0.44) - uAxis * (faceW * 0.46);
        vec2 diffR = pIso - cheekR;
        float dR2 = dot(diffR, diffR);
        if (dR2 < cheekRad2) {
            float fall = 1.0 - dR2 / cheekRad2;
            vec2 pullOut = vedro_safe_norm(cheekR - target, -uAxis);
            disp += pullOut * (faceW * 0.135 * slimAmt * rightSideVis * fall * fall);
        }
        vec2 cheekL = eyeMid + vAxis * (faceH * 0.44) + uAxis * (faceW * 0.46);
        vec2 diffL = pIso - cheekL;
        float dL2 = dot(diffL, diffL);
        if (dL2 < cheekRad2) {
            float fall = 1.0 - dL2 / cheekRad2;
            vec2 pullOut = vedro_safe_norm(cheekL - target, uAxis);
            disp += pullOut * (faceW * 0.135 * slimAmt * leftSideVis * fall * fall);
        }
    }

    float chinAmt = clamp(morph.z, 0.0, 1.0) * alpha;
    if (chinAmt > 0.002) {
        vec2 chinCenter = mouth + vAxis * (faceH * 0.30);
        float chinR = clamp(faceW * 0.46, 0.03, 0.28);
        float chinR2 = chinR * chinR;
        vec2 jawR = mouth + vAxis * (faceH * 0.20) - uAxis * (faceW * 0.34);
        vec2 djR = pIso - jawR;
        float djR2 = dot(djR, djR);
        if (djR2 < chinR2) {
            float fall = 1.0 - djR2 / chinR2;
            vec2 dirR = vedro_safe_norm(jawR - (mouth - vAxis * (faceH * 0.04)), -uAxis + vAxis * 0.4);
            disp += dirR * (faceW * 0.11 * chinAmt * rightSideVis * fall * fall);
        }
        vec2 jawL = mouth + vAxis * (faceH * 0.20) + uAxis * (faceW * 0.34);
        vec2 djL = pIso - jawL;
        float djL2 = dot(djL, djL);
        if (djL2 < chinR2) {
            float fall = 1.0 - djL2 / chinR2;
            vec2 dirL = vedro_safe_norm(jawL - (mouth - vAxis * (faceH * 0.04)), uAxis + vAxis * 0.4);
            disp += dirL * (faceW * 0.11 * chinAmt * leftSideVis * fall * fall);
        }
        vec2 dc = pIso - chinCenter;
        float dc2 = dot(dc, dc);
        float liftR = clamp(faceW * 0.34, 0.025, 0.22);
        float liftR2 = liftR * liftR;
        if (dc2 < liftR2) {
            float fall = 1.0 - dc2 / liftR2;
            disp += vAxis * (faceH * 0.055 * chinAmt * fall * fall);
        }
    }
    return disp;
}

vec3 vedro_face_lip_tint(vec3 rgb, vec2 sampleIso, vec2 aspect, vec4 eyes, vec4 lower, vec4 meta, float lipStrength) {
    float alpha = clamp(meta.w, 0.0, 1.0);
    if (lipStrength < 0.005 || alpha < 0.005 || meta.z < 0.01) {
        return rgb;
    }
    vec2 re = eyes.xy * aspect;
    vec2 le = eyes.zw * aspect;
    vec2 mouth = lower.zw * aspect;
    vec2 eyeVec = le - re;
    float iod = length(eyeVec);
    if (iod < 0.012) return rgb;
    vec2 uAxis = eyeVec / iod;
    vec2 vAxis = vec2(-uAxis.y, uAxis.x);
    if (dot(mouth - (re + le) * 0.5, vAxis) < 0.0) {
        vAxis = -vAxis;
    }
    vec2 rel = sampleIso - mouth;
    float rx = max(meta.z * aspect.x * 0.54, iod * 0.36);
    float ry = max(rx * 0.42, 0.008);
    float ex = dot(rel, uAxis) / rx;
    float ey = dot(rel, vAxis) / ry;
    float r2 = ex * ex + ey * ey;
    if (r2 >= 1.35) return rgb;

    float ovalMask = 1.0 - smoothstep(0.45, 1.25, r2);
    float luma = dot(rgb, vec3(0.299, 0.587, 0.114));
    float maxC = max(rgb.r, max(rgb.g, rgb.b));
    float minC = min(rgb.r, min(rgb.g, rgb.b));
    float sat = maxC - minC;
    float warmGate = smoothstep(0.015, 0.095, rgb.r - rgb.g);
    float teethProtect = 1.0 - smoothstep(0.56, 0.74, luma) * (1.0 - smoothstep(0.05, 0.16, sat));
    float darkProtect = smoothstep(0.06, 0.16, luma);
    float mask = clamp(ovalMask * warmGate * teethProtect * darkProtect * alpha, 0.0, 1.0);
    vec3 roseTone = vec3(0.92, 0.36, 0.44);
    vec3 glazed = mix(rgb, rgb * mix(vec3(1.0), roseTone * 1.18, 0.72) + vec3(0.055, -0.012, 0.004), 0.75);
    return mix(rgb, clamp(glazed, 0.0, 1.0), mask * lipStrength * 0.72);
}

vec4 hook() {
    vec2 uv = HOOKED_pos;
    vec2 aspect = vec2(HOOKED_size.x / max(HOOKED_size.y, 1.0), 1.0);
    vec2 pIso = uv * aspect;
    vec4 morph = $morphVec;
    vec2 totalDisp = vedro_face_warp_iso(pIso, aspect, $f0Args, morph)
                   + vedro_face_warp_iso(pIso, aspect, $f1Args, morph);
    vec2 warpedUv = clamp(uv + totalDisp / aspect, HOOKED_pt * 0.5, vec2(1.0) - HOOKED_pt * 0.5);
    vec4 texel = HOOKED_tex(warpedUv);
    vec3 cc = clamp(texel.rgb, 0.0, 1.0);
    vec3 hdrExcess = max(texel.rgb - vec3(1.0), vec3(0.0));
    if (morph.w > 0.005) {
        vec2 sampleIso = warpedUv * aspect;
        cc = vedro_face_lip_tint(cc, sampleIso, aspect, $f0Args, morph.w);
        cc = vedro_face_lip_tint(cc, sampleIso, aspect, $f1Args, morph.w);
    }
    return vec4(max(cc + hdrExcess, vec3(0.0)), texel.a);
}
''';
  }

  /// Build & write a combined `.glsl` file stacking Plan B (if active) + Plan A mpv pass (if active).
  /// Uses a 2-slot ping-pong filename for Plan A updates so mpv reloads cleanly with zero disk bloat.
  static Future<String?> prepareCombinedShaderFile({
    required BeautyFilterParams beautyParams,
    required String beautyLabel,
    required bool mobileLean,
    required bool useMpvForAiFace,
    required AiFaceMorphParams aiMorph,
    required List<AiTrackedFace> aiFaces,
    required int pingPongSlot,
  }) async {
    final aiPass = useMpvForAiFace
        ? buildFaceMorphPassGlsl(morph: aiMorph, faces: aiFaces)
        : null;

    if (aiPass == null) {
      if (!beautyParams.isActive) return null;
      return BeautyFilterEngine.prepareShaderFileForParams(
        beautyParams,
        label: beautyLabel,
        mobileLean: mobileLean,
      );
    }

    final beautySrc = beautyParams.isActive
        ? BeautyFilterEngine.buildGlslSourceFromParams(
            beautyParams,
            label: beautyLabel,
            mobileLean: mobileLean,
          )
        : null;

    final combined = beautySrc != null ? '$beautySrc\n$aiPass' : aiPass;
    final Directory support;
    try {
      support = await getApplicationSupportDirectory();
    } catch (_) {
      return null;
    }
    final dir = Directory('${support.path}/vedro_shaders_v4');
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    final slot = (pingPongSlot & 1) == 0 ? 'a' : 'b';
    final file = File('${dir.path}/ai_face_combined_$slot.glsl');
    await file.writeAsString(combined);
    return file.path;
  }
}
