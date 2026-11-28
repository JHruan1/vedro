#include <flutter/runtime_effect.glsl>

// Impeller ImageFilter.shader mandatory first uniform: bound texture pixel size.
uniform vec2 u_size;
// Corner radius in physical pixels (logical dp * devicePixelRatio).
uniform float u_radiusPx;
// Device pixel ratio (keeps bevel width & refraction resolution-independent).
uniform float u_dpr;
// Curved glass bezel width in physical pixels (QmDeve default ~20-24 dp).
uniform float u_refractionHeightPx;
// Peak inward lens refraction displacement in physical pixels (QmDeve default ~56-68 dp).
uniform float u_refractionAmountPx;
// Chromatic dispersion ratio (QmDeve default ~0.50-0.55).
uniform float u_dispersion;
// 3D convex dome depth curvature (QmDeve default ~0.30).
uniform float u_depthEffect;
// Specular & caustic optical intensity multiplier (0.65 subtle, 1.0 standard, 1.35 vivid).
uniform float u_specIntensity;
// 1.0 for light theme polarity, 0.0 for dark theme polarity.
uniform float u_isLight;
// Active theme accent color (RGB in 0..1) for subtle bottom-right caustic bounce.
uniform vec3 u_accent;

// Impeller ImageFilter.shader mandatory first sampler: live (or lightly blurred) backdrop texture.
uniform sampler2D u_texture;

out vec4 fragColor;

// Exact rounded-rectangle SDF & analytical gradient from QmDeve/AndroidLiquidGlassView
// (MIT License, based on Kyant0/AndroidLiquidGlass).
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

// True circular-arc convex lens derivative (QmDeve / Kyant0).
float circleMap(float x) {
  float cx = clamp(x, 0.0, 0.999);
  return 1.0 - sqrt(max(0.0, 1.0 - cx * cx));
}

vec2 toSampleUV(vec2 posPx) {
  vec2 safeSize = max(u_size, vec2(1.0));
  vec2 uv = clamp(posPx / safeSize, vec2(0.001), vec2(0.999));
#ifdef IMPELLER_TARGET_OPENGLES
  uv.y = 1.0 - uv.y;
#endif
  return uv;
}

// Linear-sRGB saturation lift + whitePoint + contrast (QmDeve/AndroidLiquidGlassView).
vec3 gradeLiquidCrystal(vec3 rgb, float chromaMul, float whitePoint, float contrast) {
  vec3 lin = pow(max(rgb, vec3(0.0)), vec3(2.2));
  float y = dot(lin, vec3(0.2126, 0.7152, 0.0722));
  vec3 satLin = mix(vec3(y), lin, chromaMul);
  vec3 graded = pow(clamp(satLin, vec3(0.0), vec3(1.0)), vec3(1.0 / 2.2));
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

  // Adaptive bezel height bounded by shape half-thickness so pills & full cards both bend naturally.
  float refrHeight = clamp(u_refractionHeightPx, 6.0 * dpr, minHalf * 0.92);
  float chromaMul = mix(1.22, 1.16, u_isLight);
  float whitePoint = mix(0.02, 0.08, u_isLight);
  float contrast = mix(0.08, 0.04, u_isLight);

  vec3 rgb;
  float alpha;
  vec2 shapeGrad = vec2(0.0, -1.0);

  if (distFromEdge >= refrHeight) {
    // Calm crystal interior: subtle gentle lens magnification without warping readable labels.
    vec2 centerSamplePos = posPx - (p / max(halfSize, vec2(1.0))) * (u_refractionAmountPx * 0.03);
    vec4 base = texture(u_texture, toSampleUV(centerSamplePos));
    alpha = base.a;
    rgb = alpha > 1e-4 ? clamp(base.rgb / alpha, 0.0, 1.0) : vec3(0.0);
    rgb = gradeLiquidCrystal(rgb, chromaMul, whitePoint, contrast);
  } else {
    // Curved optical prism wall (exact QmDeve/AndroidLiquidGlassView math!).
    float edgeT = clamp(1.0 - (distFromEdge / max(refrHeight, 1.0)), 0.0, 1.0);
    // Negative refraction offset pulls exterior light inward along -grad like thick convex crystal.
    float d = -circleMap(edgeT) * u_refractionAmountPx;

    float smoothRadius = max(r * 1.5, 26.0 * dpr);
    float gradRadius = min(smoothRadius, minHalf);
    shapeGrad = gradSdRoundedRect(p, halfSize, gradRadius);
    vec2 depthGrad = safeNormalize(p, shapeGrad);
    vec2 grad = safeNormalize(shapeGrad + u_depthEffect * depthGrad, shapeGrad);

    vec2 refractedPos = posPx + d * grad;

    // 7-band diagonal-quadrant spectral chromatic dispersion (exact QmDeve weights!).
    float quadFactor = (p.x * p.y) / max(halfSize.x * halfSize.y, 1.0);
    float dispIntensity = u_dispersion * quadFactor;
    vec2 dispersedVec = d * grad * dispIntensity;

    vec4 sRed    = texture(u_texture, toSampleUV(refractedPos + dispersedVec));
    vec4 sOrange = texture(u_texture, toSampleUV(refractedPos + dispersedVec * (2.0 / 3.0)));
    vec4 sYellow = texture(u_texture, toSampleUV(refractedPos + dispersedVec * (1.0 / 3.0)));
    vec4 sGreen  = texture(u_texture, toSampleUV(refractedPos));
    vec4 sCyan   = texture(u_texture, toSampleUV(refractedPos - dispersedVec * (1.0 / 3.0)));
    vec4 sBlue   = texture(u_texture, toSampleUV(refractedPos - dispersedVec * (2.0 / 3.0)));
    vec4 sPurple = texture(u_texture, toSampleUV(refractedPos - dispersedVec));

    vec4 acc = vec4(0.0);
    acc.r += (sRed.r + sOrange.r + sYellow.r) / 3.5 + sPurple.r / 7.0;
    acc.g += sOrange.g / 7.0 + (sYellow.g + sGreen.g + sCyan.g) / 3.5;
    acc.b += (sCyan.b + sBlue.b + sPurple.b) / 3.0;
    acc.a = (sRed.a + sOrange.a + sYellow.a + sGreen.a + sCyan.a + sBlue.a + sPurple.a) / 7.0;

    alpha = acc.a;
    rgb = alpha > 1e-4 ? clamp(acc.rgb / alpha, 0.0, 1.0) : vec3(0.0);
    rgb = gradeLiquidCrystal(rgb, chromaMul + 0.08 * edgeT, whitePoint, contrast);

    // Sub-surface Fresnel specular catchlight & opposite accent caustic along curved wall.
    vec2 lightDir = normalize(vec2(-0.72, -0.69));
    float dotL = dot(shapeGrad, lightDir);
    float topCatch = pow(max(0.0, dotL), 1.5);
    float botCaustic = pow(max(0.0, -dotL), 1.8);
    float dualRim = pow(abs(dotL), 2.0);

    float rimBand = smoothstep(3.2 * dpr, 0.0, distFromEdge);
    float bevelBand = smoothstep(refrHeight * 0.55, 0.0, distFromEdge);
    float fresnel = pow(edgeT, 2.6);

    float specScale = clamp(u_specIntensity, 0.4, 1.6);
    float topBoost = mix(0.32, 0.40, u_isLight) * specScale;
    float causticBoost = mix(0.24, 0.16, u_isLight) * specScale;

    vec3 rimGlow = vec3(1.0) * (
      topCatch * topBoost * rimBand +
      topCatch * (topBoost * 0.30) * bevelBand +
      dualRim * (0.12 * specScale) * rimBand +
      mix(0.08, 0.12, u_isLight) * specScale * fresnel
    );
    vec3 causticColor = mix(vec3(1.0), u_accent, 0.48);
    vec3 causticGlow = causticColor * (botCaustic * causticBoost * (rimBand * 0.78 + bevelBand * 0.22));

    // Crisp sub-rim optical refraction trough for glass thickness depth.
    float trough = smoothstep(0.0, 2.2 * dpr, distFromEdge) * smoothstep(7.0 * dpr, 2.2 * dpr, distFromEdge);
    rgb *= 1.0 - trough * mix(0.11, 0.04, u_isLight);

    rgb = clamp(rgb + rimGlow + causticGlow, 0.0, 1.0);
  }

  fragColor = vec4(rgb * alpha, alpha);
}
