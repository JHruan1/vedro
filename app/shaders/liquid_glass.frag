precision highp float;

#include <flutter/runtime_effect.glsl>

// Impeller ImageFilter.shader mandatory first uniform: bound render-pass texture pixel size.
uniform vec2 u_size;
// Exact widget screen-space bounds in physical pixels: (centerX, centerY, halfW, halfH).
uniform vec4 u_rect;
// Corner radius in physical pixels (logical dp * devicePixelRatio).
uniform float u_radiusPx;
// Device pixel ratio (keeps bevel width & refraction resolution-independent).
uniform float u_dpr;
// Curved glass bezel width in physical pixels.
uniform float u_refractionHeightPx;
// Peak inward lens refraction displacement in physical pixels.
uniform float u_refractionAmountPx;
// Chromatic dispersion ratio (0..1).
uniform float u_dispersion;
// 3D convex dome depth curvature.
uniform float u_depthEffect;
// Specular & caustic optical intensity multiplier (0.72 subtle, 1.0 standard, 1.32 vivid).
uniform float u_specIntensity;
// 1.0 for light theme polarity, 0.0 for dark theme polarity.
uniform float u_isLight;
// Active theme accent color (RGB in 0..1) for subtle ambient bounce.
uniform vec3 u_accent;

// Impeller ImageFilter.shader mandatory first sampler: live full-pass backdrop texture.
uniform sampler2D u_texture;

out vec4 fragColor;

float sdRoundedRect(vec2 coord, vec2 halfSize, float radius) {
  vec2 cornerCoord = abs(coord) - (halfSize - vec2(radius));
  float outside = length(max(cornerCoord, vec2(0.0))) - radius;
  float inside = min(max(cornerCoord.x, cornerCoord.y), 0.0);
  return outside + inside;
}

float safeSign(float v) {
  return v < 0.0 ? -1.0 : 1.0;
}

vec2 safeNormalize(vec2 v, vec2 fallback) {
  float len = length(v);
  return len > 0.001 ? (v / len) : fallback;
}

vec2 gradSdRoundedRect(vec2 coord, vec2 halfSize, float radius) {
  vec2 cornerCoord = abs(coord) - (halfSize - vec2(radius));
  vec2 s = vec2(safeSign(coord.x), safeSign(coord.y));
  if (cornerCoord.x >= 0.0 || cornerCoord.y >= 0.0) {
    vec2 outside = max(cornerCoord, vec2(0.0));
    float outsideLen = length(outside);
    if (outsideLen > 0.001) {
      return s * (outside / outsideLen);
    }
    float useX = step(cornerCoord.y, cornerCoord.x);
    return vec2(useX * s.x, (1.0 - useX) * s.y);
  }
  float gradX = step(cornerCoord.y, cornerCoord.x);
  return s * vec2(gradX, 1.0 - gradX);
}

float circleMap(float x) {
  float cx = clamp(x, 0.0, 0.99);
  return 1.0 - sqrt(max(0.0, 1.0 - cx * cx));
}

// Mirror-clamp UV safely across Vulkan, OpenGL ES, and Metal backends without
// stretched edge stripes or GLES decal black (matching flutter_liquid_glass).
// Note: Impeller's FlutterFragCoord() + sampler already handle backend Y-origin.
vec2 toSampleUV(vec2 posPx, vec2 invSize) {
  vec2 uv = posPx * invSize;
  vec2 mirrored = vec2(1.0) - abs(mod(uv, vec2(2.0)) - vec2(1.0));
  vec2 halfTexel = invSize * 0.5;
  return clamp(mirrored, halfTexel, vec2(1.0) - halfTexel);
}

// Fast quadratic-gamma crystal grading (120Hz mobile GPU friendly, zero pow()).
vec3 gradeLiquidCrystalFast(vec3 rgb, float chromaMul, float whitePoint, float contrast) {
  vec3 lin = rgb * rgb;
  float y = dot(lin, vec3(0.2126, 0.7152, 0.0722));
  vec3 satLin = max(mix(vec3(y), lin, chromaMul), vec3(0.0));
  vec3 graded = sqrt(satLin);
  vec3 target = whitePoint > 0.0 ? vec3(1.0) : vec3(0.0);
  graded = mix(graded, target, abs(whitePoint));
  graded = (graded - 0.5) * (1.0 + contrast) + 0.5;
  return clamp(graded, 0.0, 1.0);
}

vec3 unpremul(vec4 c) {
  return c.a > 1e-4 ? clamp(c.rgb / c.a, 0.0, 1.0) : vec3(0.0);
}

void main() {
  vec2 safeSize = max(u_size, vec2(1.0));
  vec2 invSize = 1.0 / safeSize;
  vec2 posPx = FlutterFragCoord().xy;

  // In the normal root render pass, u_size is the full screen and u_rect is the
  // exact widget rect in screen physical pixels. If an ancestor saveLayer/Opacity
  // ever cropped the pass to the widget itself, fall back smoothly to pass center.
  bool inRootPass = (u_rect.z > 0.5 && u_rect.w > 0.5) &&
      (u_rect.x + u_rect.z <= safeSize.x + 12.0) &&
      (u_rect.y + u_rect.w <= safeSize.y + 12.0) &&
      (u_rect.x - u_rect.z >= -12.0) &&
      (u_rect.y - u_rect.w >= -12.0);
  vec2 rectCenter = inRootPass ? u_rect.xy : (safeSize * 0.5);
  vec2 halfSize = inRootPass ? u_rect.zw : (safeSize * 0.5);
  vec2 p = posPx - rectCenter;

  float dpr = max(u_dpr, 1.0);
  float minHalf = max(min(halfSize.x, halfSize.y), 1.0);
  float r = clamp(u_radiusPx, 0.0, max(0.0, minHalf - 0.5));
  float sd = sdRoundedRect(p, halfSize, r);
  float distFromEdge = max(0.0, -sd);

  // Full-surface C2-continuous 3D liquid-glass lens (ZERO interior/bezel branch or seam!):
  // On capsules/pills (height <= ~64dp), refrSpan spans 98% of minHalf so the ENTIRE bar
  // acts as one continuous curved liquid-glass dome from center spine to 360° outer rim.
  // On larger panels/menus, quintic C2 falloff blends invisibly into the convex crystal body.
  float refrSpan = clamp(u_refractionHeightPx, 10.0 * dpr, minHalf * 0.98);
  float safeRefrAmount = clamp(u_refractionAmountPx, 0.0, minHalf * 1.42);
  float t = clamp(1.0 - (distFromEdge / max(refrSpan, 1.0)), 0.0, 1.0);
  // C2 quintic smoothstep: value, 1st derivative, AND 2nd derivative all vanish smoothly at t=0.
  float q = t * t * t * (t * (t * 6.0 - 15.0) + 10.0);
  float lensProfile = mix(q, circleMap(t) * q, 0.52);

  // Continuous outward surface normal across the entire glass (zero spine crease at p.y = 0).
  float smoothRadius = max(r * 1.15, 14.0 * dpr);
  float gradRadius = min(smoothRadius, minHalf);
  vec2 shapeGrad = gradSdRoundedRect(p, halfSize, gradRadius);
  vec2 normP = p / max(halfSize, vec2(1.0));
  vec2 radialGrad = safeNormalize(normP, shapeGrad);
  // Blend smoothly from radial dome near center to exact rounded-rect SDF normal near rim.
  float rimAlign = smoothstep(0.0, 0.55, t);
  vec2 grad = safeNormalize(
    mix(radialGrad, shapeGrad, rimAlign) + (u_depthEffect * 0.42) * radialGrad,
    shapeGrad
  );

  // Continuous whole-body convex magnification + seamless curved bevel refraction.
  vec2 domeDisp = -normP * (minHalf * 0.11 * (0.55 + 0.45 * u_depthEffect));
  vec2 bevelDisp = -grad * (lensProfile * safeRefrAmount);
  vec2 totalDisp = domeDisp + bevelDisp;
  vec2 refractedPos = posPx + totalDisp;

  // Unified single-pass 4-tap diagonal crystal frost everywhere (ZERO sharp-vs-blurry cliff!).
  // Softly frosted through the body, slightly glossier toward the outer curved lip.
  float frostOff = mix(2.35, 1.45, lensProfile) * dpr;
  vec4 s0 = texture(u_texture, toSampleUV(refractedPos + vec2(-frostOff, -frostOff), invSize));
  vec4 s1 = texture(u_texture, toSampleUV(refractedPos + vec2( frostOff, -frostOff), invSize));
  vec4 s2 = texture(u_texture, toSampleUV(refractedPos + vec2(-frostOff,  frostOff), invSize));
  vec4 s3 = texture(u_texture, toSampleUV(refractedPos + vec2( frostOff,  frostOff), invSize));
  vec4 base = (s0 + s1 + s2 + s3) * 0.25;
  float alpha = base.a;
  vec3 rgb = unpremul(base);

  // Continuous prismatic RGB chromatic dispersion blended smoothly into the crystal frost.
  vec2 dispVec = totalDisp * (u_dispersion * 0.26);
  float dispLen = length(dispVec);
  if (dispLen > 0.35) {
    vec3 rSample = unpremul(texture(u_texture, toSampleUV(refractedPos + dispVec, invSize)));
    vec3 bSample = unpremul(texture(u_texture, toSampleUV(refractedPos - dispVec, invSize)));
    float dispMix = clamp(dispLen / (4.2 * dpr), 0.0, 0.68) * (0.28 + 0.72 * q);
    rgb.r = mix(rgb.r, rSample.r, dispMix);
    rgb.b = mix(rgb.b, bSample.b, dispMix);
  }

  float chromaMul = mix(1.22, 1.14, u_isLight) + 0.10 * q;
  float whitePoint = mix(0.03, 0.07, u_isLight);
  float contrast = mix(0.06, 0.04, u_isLight);
  rgb = gradeLiquidCrystalFast(rgb, chromaMul, whitePoint, contrast);

  // Continuous 360° Apple iOS 26 Fresnel glass rim + smooth full-dome specular sheen.
  float rim360 = smoothstep(3.0 * dpr, 0.0, distFromEdge);
  float softBevel360 = smoothstep(refrSpan, 0.0, distFromEdge);
  float fresnel = q * q;

  float verticalSlope = mix(-normP.y, -shapeGrad.y, rimAlign);
  float horizSlope = mix(abs(normP.x), abs(shapeGrad.x), rimAlign);
  float topWeight = 0.5 + 0.5 * clamp(verticalSlope, -1.0, 1.0);
  float sideWeight = 0.35 + 0.65 * clamp(horizSlope, 0.0, 1.0);
  float specScale = clamp(u_specIntensity, 0.45, 1.6);

  float bodyGlow = mix(0.015, 0.045, topWeight) * (1.0 - softBevel360 * 0.5);
  float rimLight = mix(0.20, 0.35, topWeight) * rim360 +
      mix(0.04, 0.10, topWeight) * softBevel360 +
      0.065 * sideWeight * rim360 +
      mix(0.04, 0.08, u_isLight) * fresnel +
      bodyGlow;
  vec3 rimGlow = vec3(1.0) * (rimLight * mix(0.88, 1.08, u_isLight) * specScale);

  float botWeight = 1.0 - topWeight;
  vec3 causticGlow = mix(vec3(1.0), u_accent, 0.38) *
      ((botWeight * 0.10 * rim360 + botWeight * 0.025 * softBevel360) * specScale);

  rgb = clamp(rgb + rimGlow + causticGlow, 0.0, 1.0);
  fragColor = vec4(rgb * alpha, alpha);
}
