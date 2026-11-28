#include <flutter/runtime_effect.glsl>

// Impeller ImageFilter.shader mandatory first uniform: bound texture pixel size.
uniform vec2 u_size;
// Corner radius in physical pixels (logical dp * devicePixelRatio).
uniform float u_radiusPx;
// Device pixel ratio (keeps bevel width & refraction resolution-independent).
uniform float u_dpr;
// Curved glass bezel width in physical pixels.
uniform float u_refractionHeightPx;
// Peak inward lens refraction displacement in physical pixels (auto-clamped to shape thickness).
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

// Impeller ImageFilter.shader mandatory first sampler: live backdrop texture.
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
  float cx = clamp(x, 0.0, 0.985);
  return 1.0 - sqrt(max(0.0, 1.0 - cx * cx));
}

vec2 toSampleUV(vec2 posPx) {
  vec2 safeSize = max(u_size, vec2(1.0));
  vec2 uv = clamp(posPx / safeSize, vec2(0.002), vec2(0.998));
#ifdef IMPELLER_TARGET_OPENGLES
  uv.y = 1.0 - uv.y;
#endif
  return uv;
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

void main() {
  vec2 safeSize = max(u_size, vec2(1.0));
  vec2 posPx = FlutterFragCoord().xy;
  vec2 halfSize = safeSize * 0.5;
  vec2 p = posPx - halfSize;

  float dpr = max(u_dpr, 1.0);
  float minHalf = max(min(halfSize.x, halfSize.y), 1.0);
  float r = clamp(u_radiusPx, 0.0, max(0.0, minHalf - 0.5));
  float sd = sdRoundedRect(p, halfSize, r);
  float distFromEdge = max(0.0, -sd);

  // Clamp bezel width & peak refraction safely to shape half-thickness so thin
  // floating docks (56dp) NEVER shoot past the clipped texture boundary into a
  // single clamped stripe — refracting organically all 360° around the entire pill!
  float refrHeight = clamp(u_refractionHeightPx, 6.0 * dpr, minHalf * 0.58);
  float safeRefrAmount = min(u_refractionAmountPx, refrHeight * 0.88);
  float edgeT = clamp(1.0 - (distFromEdge / max(refrHeight, 1.0)), 0.0, 1.0);
  // C1 smooth cubic blend eliminates any visible seam between bezel and flat center.
  float smoothEdge = edgeT * edgeT * (3.0 - 2.0 * edgeT);
  float lensProfile = mix(smoothEdge, circleMap(edgeT), 0.55) * smoothEdge;

  float chromaMul = mix(1.18, 1.12, u_isLight);
  float whitePoint = mix(0.02, 0.06, u_isLight);
  float contrast = mix(0.05, 0.03, u_isLight);

  vec3 rgb;
  float alpha;

  if (edgeT <= 0.001) {
    // Fast 1-tap interior path: calm crystal glass with gentle lens magnification.
    vec2 centerPos = posPx - (p / max(halfSize, vec2(1.0))) * (safeRefrAmount * 0.04);
    vec4 base = texture(u_texture, toSampleUV(centerPos));
    alpha = base.a;
    rgb = alpha > 1e-4 ? clamp(base.rgb / alpha, 0.0, 1.0) : vec3(0.0);
    rgb = gradeLiquidCrystalFast(rgb, chromaMul, whitePoint, contrast);
  } else {
    float smoothRadius = max(r * 1.35, 16.0 * dpr);
    float gradRadius = min(smoothRadius, minHalf);
    vec2 shapeGrad = gradSdRoundedRect(p, halfSize, gradRadius);
    vec2 depthGrad = safeNormalize(p, shapeGrad);
    vec2 grad = safeNormalize(shapeGrad + (u_depthEffect * 0.65) * depthGrad, shapeGrad);

    // Pull exterior light softly inward along -grad all 360° around the perimeter.
    float d = -lensProfile * safeRefrAmount;
    vec2 refractedPos = posPx + d * grad;

    // Subtle 3-tap RGB prismatic dispersion around the full curved perimeter.
    vec2 dispVec = d * grad * (u_dispersion * 0.28);
    vec4 sG = texture(u_texture, toSampleUV(refractedPos));
    alpha = sG.a;
    if (dot(dispVec, dispVec) > 0.20) {
      vec4 sR = texture(u_texture, toSampleUV(refractedPos + dispVec));
      vec4 sB = texture(u_texture, toSampleUV(refractedPos - dispVec));
      rgb = vec3(sR.r, sG.g, sB.b);
    } else {
      rgb = sG.rgb;
    }
    rgb = alpha > 1e-4 ? clamp(rgb / alpha, 0.0, 1.0) : vec3(0.0);
    rgb = gradeLiquidCrystalFast(rgb, chromaMul + 0.06 * smoothEdge, whitePoint, contrast);

    // Natural 360° continuous Apple iOS 26 Fresnel glass rim (top, bottom, left, right).
    float rim360 = smoothstep(2.6 * dpr, 0.0, distFromEdge);
    float softBevel360 = smoothstep(refrHeight * 0.62, 0.0, distFromEdge);
    float fresnel = smoothEdge * smoothEdge;

    // Gentle directional modulation (top edge slightly brighter, bottom softly bounced,
    // NEVER dropping to zero along any edge!).
    float topWeight = 0.5 + 0.5 * clamp(-shapeGrad.y, -1.0, 1.0);
    float sideWeight = 0.35 + 0.65 * abs(shapeGrad.x);
    float specScale = clamp(u_specIntensity, 0.45, 1.5);

    float rimLight = mix(0.16, 0.28, topWeight) * rim360 +
        mix(0.04, 0.08, topWeight) * softBevel360 +
        0.05 * sideWeight * rim360 +
        mix(0.04, 0.07, u_isLight) * fresnel;
    vec3 rimGlow = vec3(1.0) * (rimLight * mix(0.85, 1.05, u_isLight) * specScale);

    // Subtle ambient accent tint on the lower curve so the glass feels dimensional, not neon.
    float botWeight = 1.0 - topWeight;
    vec3 causticGlow = mix(vec3(1.0), u_accent, 0.35) * (botWeight * 0.08 * rim360 * specScale);

    rgb = clamp(rgb + rimGlow + causticGlow, 0.0, 1.0);
  }

  fragColor = vec4(rgb * alpha, alpha);
}
