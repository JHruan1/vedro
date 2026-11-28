#include <flutter/runtime_effect.glsl>

// Impeller ImageFilter.shader mandatory first uniform: bound texture pixel size.
uniform vec2 u_size;
// Corner radius in physical pixels (logical dp * devicePixelRatio).
uniform float u_radiusPx;
// Device pixel ratio (keeps bezel width & rim thickness resolution-independent).
uniform float u_dpr;
// Peak inward refraction displacement at the curved bevel edge (physical pixels).
uniform float u_refractionPx;
// Spectral chromatic dispersion intensity (0.0..1.0 scaled by physical pixel width).
uniform float u_dispersionPx;
// Specular & caustic optical intensity multiplier (0.65 subtle, 1.0 balanced, 1.35 vivid).
uniform float u_specIntensity;
// 1.0 for light theme polarity, 0.0 for dark theme polarity.
uniform float u_isLight;
// Active theme accent color (RGB in 0..1) for subtle bottom-right caustic bounce.
uniform vec3 u_accent;

// Impeller ImageFilter.shader mandatory first sampler: blurred backdrop texture.
uniform sampler2D u_texture;

out vec4 fragColor;

// Exact rounded-rectangle SDF & analytical gradient (grounded in Kyant0/AndroidLiquidGlass).
float sdRoundedRect(vec2 coord, vec2 halfSize, float radius) {
  vec2 cornerCoord = abs(coord) - (halfSize - vec2(radius));
  float outside = length(max(cornerCoord, vec2(0.0))) - radius;
  float inside = min(max(cornerCoord.x, cornerCoord.y), 0.0);
  return outside + inside;
}

vec2 gradSdRoundedRect(vec2 coord, vec2 halfSize, float radius) {
  vec2 cornerCoord = abs(coord) - (halfSize - vec2(radius));
  vec2 s = vec2(coord.x >= 0.0 ? 1.0 : -1.0, coord.y >= 0.0 ? 1.0 : -1.0);
  if (cornerCoord.x >= 0.0 || cornerCoord.y >= 0.0) {
    vec2 clamped = max(cornerCoord, vec2(0.0));
    float len = length(clamped);
    return len > 1e-4 ? (s * (clamped / len)) : vec2(0.0, -1.0);
  }
  float gradX = step(cornerCoord.y, cornerCoord.x);
  return s * vec2(gradX, 1.0 - gradX);
}

// True circular-arc convex lens thickness derivative (Kyant0/AndroidLiquidGlass).
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

// Chroma-adaptive Apple vibrancy (grounded in whynotmake-it/flutter_liquid_glass render.glsl):
// keeps neutral whites/grays pure while letting vivid poster artwork glow richly through glass.
vec3 applyAdaptiveVibrancy(vec3 rgb, float baseSat) {
  float luma = dot(rgb, vec3(0.2126, 0.7152, 0.0722));
  float maxC = max(rgb.r, max(rgb.g, rgb.b));
  float minC = min(rgb.r, min(rgb.g, rgb.b));
  float chroma = maxC - minC;
  float chromaWeight = clamp((chroma - 0.15) / 0.65, 0.0, 1.0);
  float effectiveSat = baseSat + 0.36 * chromaWeight;
  return clamp(mix(vec3(luma), rgb, effectiveSat), 0.0, 1.0);
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

  // Softened gradient radius (1.5x corner radius) eliminates hard straight-to-arc seams.
  float gradRadius = min(max(r * 1.5, 4.0 * dpr), minHalf);
  vec2 rawGrad = gradSdRoundedRect(p, halfSize, gradRadius);
  float pLen = length(p);
  vec2 radialDir = pLen > 1e-4 ? (p / pLen) : vec2(0.0);
  // Subtle 3D domed depth curvature combined with outward perimeter normal.
  vec2 lensGrad = normalize(rawGrad + 0.14 * radialDir + vec2(1e-5));

  // Curved glass bezel thickness (refractionHeight).
  float bezelPx = clamp(max(r * 1.15, 16.0 * dpr), 12.0 * dpr, min(30.0 * dpr, minHalf * 0.78));
  float edgeT = clamp(1.0 - (distFromEdge / max(bezelPx, 1.0)), 0.0, 1.0);
  float lensDisp = circleMap(edgeT) * u_refractionPx;

  // Pull exterior light inward along -lensGrad like a real convex prism wall.
  vec2 refractPos = posPx - lensGrad * lensDisp;

  // Kyant0 diagonal-quadrant 7-band spectral dispersion:
  // strongest around curved corners, naturally fading to zero on flat text edges.
  float quadFactor = (p.x * p.y) / max(halfSize.x * halfSize.y, 1.0);
  float dispStrength = (u_dispersionPx / max(u_refractionPx, 1.0)) * 2.2 * quadFactor;
  vec2 dispVec = -lensGrad * (lensDisp * dispStrength);

  vec3 rgb;
  float alpha;
  if (length(dispVec) > 0.35 && u_dispersionPx > 0.05) {
    vec4 sRed    = texture(u_texture, toSampleUV(refractPos + dispVec));
    vec4 sOrange = texture(u_texture, toSampleUV(refractPos + dispVec * (2.0 / 3.0)));
    vec4 sYellow = texture(u_texture, toSampleUV(refractPos + dispVec * (1.0 / 3.0)));
    vec4 sGreen  = texture(u_texture, toSampleUV(refractPos));
    vec4 sCyan   = texture(u_texture, toSampleUV(refractPos - dispVec * (1.0 / 3.0)));
    vec4 sBlue   = texture(u_texture, toSampleUV(refractPos - dispVec * (2.0 / 3.0)));
    vec4 sPurple = texture(u_texture, toSampleUV(refractPos - dispVec));

    vec4 acc = vec4(0.0);
    acc.r += (sRed.r + sOrange.r + sYellow.r) / 3.5 + sPurple.r / 7.0;
    acc.g += sOrange.g / 7.0 + (sYellow.g + sGreen.g + sCyan.g) / 3.5;
    acc.b += (sCyan.b + sBlue.b + sPurple.b) / 3.0;
    acc.a = (sRed.a + sOrange.a + sYellow.a + sGreen.a + sCyan.a + sBlue.a + sPurple.a) / 7.0;

    alpha = acc.a;
    rgb = alpha > 1e-4 ? clamp(acc.rgb / alpha, 0.0, 1.0) : vec3(0.0);
  } else {
    vec4 centerSample = texture(u_texture, toSampleUV(refractPos));
    alpha = centerSample.a;
    rgb = alpha > 1e-4 ? clamp(centerSample.rgb / alpha, 0.0, 1.0) : vec3(0.0);
  }

  // Adaptive Apple vibrancy saturation lift.
  float baseSat = mix(1.18, 1.12, u_isLight);
  rgb = applyAdaptiveVibrancy(rgb, baseSat);

  // Kyant0 + iOS 26 dual-axis specular catchlight & opposite caustic reflection.
  vec2 lightDir = normalize(vec2(-0.72, -0.69));
  float dotL = dot(rawGrad, lightDir);
  float topCatch = pow(max(0.0, dotL), 1.55);
  float botCaustic = pow(max(0.0, -dotL), 1.85);
  float dualRim = pow(abs(dotL), 2.1);

  float rimBand = smoothstep(3.2 * dpr, 0.0, distFromEdge);
  float innerBevelBand = smoothstep(bezelPx * 0.55, 0.0, distFromEdge);
  float fresnel = pow(edgeT, 3.0);

  float specScale = clamp(u_specIntensity, 0.4, 1.6);
  float topBoost = mix(0.28, 0.36, u_isLight) * specScale;
  float ambientFresnel = mix(0.075, 0.11, u_isLight) * specScale;
  float causticBoost = mix(0.20, 0.14, u_isLight) * specScale;

  vec3 rimGlow = vec3(1.0) * (
    topCatch * topBoost * rimBand +
    topCatch * (topBoost * 0.30) * innerBevelBand +
    dualRim * (0.10 * specScale) * rimBand +
    ambientFresnel * fresnel
  );
  vec3 causticColor = mix(vec3(1.0), u_accent, 0.50);
  vec3 causticGlow = causticColor * (botCaustic * causticBoost * (rimBand * 0.78 + innerBevelBand * 0.22));

  // Subtle sub-rim optical refraction trough for authentic glass thickness depth.
  float trough = smoothstep(0.0, 2.4 * dpr, distFromEdge) * smoothstep(7.2 * dpr, 2.4 * dpr, distFromEdge);
  rgb *= 1.0 - trough * mix(0.09, 0.03, u_isLight);

  rgb = clamp(rgb + rimGlow + causticGlow, 0.0, 1.0);
  fragColor = vec4(rgb * alpha, alpha);
}
