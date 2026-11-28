#include <flutter/runtime_effect.glsl>

// Impeller ImageFilter.shader mandatory first uniform: bound texture pixel size.
uniform vec2 u_size;
// Corner radius in physical pixels (logical dp * devicePixelRatio).
uniform float u_radiusPx;
// Device pixel ratio (used to keep bezel width & rim thickness resolution-independent).
uniform float u_dpr;
// Peak inward refraction displacement at the curved bevel edge (physical pixels).
uniform float u_refractionPx;
// RGB chromatic dispersion spread along the refraction vector (physical pixels).
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

float sdRoundRect(vec2 p, vec2 halfSize, float radius) {
  vec2 q = abs(p) - (halfSize - vec2(radius));
  return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
}

vec2 toSampleUV(vec2 posPx) {
  vec2 safeSize = max(u_size, vec2(1.0));
  vec2 uv = clamp(posPx / safeSize, vec2(0.001), vec2(0.999));
#ifdef IMPELLER_TARGET_OPENGLES
  uv.y = 1.0 - uv.y;
#endif
  return uv;
}

void main() {
  vec2 safeSize = max(u_size, vec2(1.0));
  vec2 posPx = FlutterFragCoord().xy;
  vec2 halfSize = safeSize * 0.5;
  vec2 p = posPx - halfSize;

  float dpr = max(u_dpr, 1.0);
  float minHalf = max(min(halfSize.x, halfSize.y), 1.0);
  float r = clamp(u_radiusPx, 0.0, max(0.0, minHalf - 0.5));

  // Signed distance to rounded-rect perimeter (<= 0 inside the glass lens).
  float d = sdRoundRect(p, halfSize, r);
  float distFromEdge = max(0.0, -d);

  // Smooth outward-pointing normal via symmetric central differences.
  float eps = max(1.0, dpr * 0.5);
  vec2 grad = vec2(
    sdRoundRect(p + vec2(eps, 0.0), halfSize, r) - sdRoundRect(p - vec2(eps, 0.0), halfSize, r),
    sdRoundRect(p + vec2(0.0, eps), halfSize, r) - sdRoundRect(p - vec2(0.0, eps), halfSize, r)
  );
  float gradLen = length(grad);
  vec2 normal = gradLen > 1e-4 ? (grad / gradLen) : vec2(0.0, -1.0);

  // Convex curved-lens bezel profile (inspired by Kyant0/AndroidLiquidGlass & iOS 26).
  // Steep optical curvature near the rim, flattening smoothly across the readable interior.
  float bezelPx = clamp(max(r * 1.12, 16.0 * dpr), 12.0 * dpr, min(28.0 * dpr, minHalf * 0.76));
  float edgeT = clamp(1.0 - (distFromEdge / max(bezelPx, 1.0)), 0.0, 1.0);
  // Dome slope curve: strong refraction right inside the curved wall, silky falloff inward.
  float lensSlope = pow(edgeT, 2.15) * (1.0 - 0.14 * edgeT);

  // Subtle thick-lens interior curvature so the entire glass slab feels gently convex.
  vec2 normCoord = p / max(halfSize, vec2(1.0));
  vec2 interiorMag = -normCoord * (u_refractionPx * 0.12) * (1.0 - edgeT);

  // Pull exterior light inward along -normal like a real convex glass prism.
  vec2 refractOffset = -normal * (lensSlope * u_refractionPx) + interiorMag;

  // Physical Cauchy RGB chromatic dispersion along the curved bezel.
  vec2 dispOffset = -normal * (lensSlope * u_dispersionPx);

  vec4 cR = texture(u_texture, toSampleUV(posPx + refractOffset - dispOffset));
  vec4 cG = texture(u_texture, toSampleUV(posPx + refractOffset));
  vec4 cB = texture(u_texture, toSampleUV(posPx + refractOffset + dispOffset));

  float alpha = cG.a;
  vec3 rgb = vec3(cR.r, cG.g, cB.b);
  if (alpha > 1e-4) {
    rgb = clamp(rgb / alpha, 0.0, 1.0);
  }

  // Apple-style vibrancy saturation lift so underlying poster/artwork colors stay rich.
  float luma = dot(rgb, vec3(0.2126, 0.7152, 0.0722));
  float satBoost = mix(1.26, 1.16, u_isLight);
  rgb = clamp(mix(vec3(luma), rgb, satBoost), 0.0, 1.0);

  // Analytical sub-surface Fresnel sheen & directional specular/caustic rim glow.
  // Directional light from top-left (-0.72, -0.69), subtle caustic bounce at bottom-right.
  vec2 lightDir = normalize(vec2(-0.72, -0.69));
  float topCatch = pow(max(0.0, dot(normal, lightDir)), 1.55);
  float botCaustic = pow(max(0.0, dot(normal, -lightDir)), 1.80);

  float rimBand = smoothstep(3.2 * dpr, 0.0, distFromEdge);
  float innerBevelBand = smoothstep(bezelPx * 0.55, 0.0, distFromEdge);
  float fresnel = pow(edgeT, 3.0);

  float specScale = clamp(u_specIntensity, 0.4, 1.6);
  float topBoost = mix(0.26, 0.34, u_isLight) * specScale;
  float ambientFresnel = mix(0.07, 0.11, u_isLight) * specScale;
  float causticBoost = mix(0.18, 0.14, u_isLight) * specScale;

  vec3 rimGlow = vec3(1.0) * (topCatch * topBoost * rimBand + topCatch * (topBoost * 0.32) * innerBevelBand + ambientFresnel * fresnel);
  vec3 causticColor = mix(vec3(1.0), u_accent, 0.52);
  vec3 causticGlow = causticColor * (botCaustic * causticBoost * (rimBand * 0.75 + innerBevelBand * 0.25));

  // Subtle darkening in the immediate sub-rim refraction trough on dark mode for glass thickness.
  float trough = smoothstep(0.0, 2.5 * dpr, distFromEdge) * smoothstep(7.5 * dpr, 2.5 * dpr, distFromEdge);
  rgb *= 1.0 - trough * mix(0.09, 0.03, u_isLight);

  rgb = clamp(rgb + rimGlow + causticGlow, 0.0, 1.0);
  fragColor = vec4(rgb * alpha, alpha);
}
