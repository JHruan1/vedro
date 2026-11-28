precision highp float;

#include <flutter/runtime_effect.glsl>

// Impeller ImageFilter.shader mandatory first uniform: bound pass texture size in physical px.
uniform vec2 u_size;
// Video viewport bounds in screen physical pixels: (leftPx, topPx, widthPx, heightPx).
uniform vec4 u_rect;
// Plan A AI Face Morph parameters (0.0 .. 1.0): (slimFace, bigEyes, vChin, lipTint).
uniform vec4 u_morph;

// Tracked Face #0 (normalized 0..1 inside video viewport rect):
// eyes: (reX, reY, leX, leY) where re = viewer-left eye, le = viewer-right eye.
uniform vec4 u_f0_eyes;
// lower: (noseX, noseY, mouthCenterX, mouthCenterY).
uniform vec4 u_f0_lower;
// meta: (faceW, faceH, mouthW, confidenceAlpha).
uniform vec4 u_f0_meta;

// Tracked Face #1 (same layout; meta.w == 0.0 when inactive).
uniform vec4 u_f1_eyes;
uniform vec4 u_f1_lower;
uniform vec4 u_f1_meta;

// Impeller ImageFilter.shader mandatory first sampler: live rendered Video layer texture.
uniform sampler2D u_texture;

out vec4 fragColor;

vec2 safeNorm(vec2 v, vec2 fallback) {
  float l = length(v);
  return l > 1e-4 ? (v / l) : fallback;
}

// Compute inverse UV displacement (in isotropic aspect-corrected space) for one tracked face.
vec2 computeFaceWarpIso(
    vec2 pIso,
    vec2 aspect,
    vec4 eyes,
    vec4 lower,
    vec4 meta,
    vec4 morph
) {
  float alpha = clamp(meta.w, 0.0, 1.0);
  if (alpha < 0.005 || meta.x < 0.015 || meta.y < 0.02) {
    return vec2(0.0);
  }

  // Fast 4-ALU AABB reject: 90%+ of background pixels skip all sqrt/length/warp math!
  vec2 approxCenter = (eyes.xy + eyes.zw + lower.zw) * (1.0 / 3.0) * aspect;
  float maxReach = max(meta.x * aspect.x, meta.y * aspect.y) * 1.15;
  vec2 deltaBox = abs(pIso - approxCenter);
  if (deltaBox.x > maxReach || deltaBox.y > maxReach) {
    return vec2(0.0);
  }

  vec2 re = eyes.xy * aspect;
  vec2 le = eyes.zw * aspect;
  vec2 nose = lower.xy * aspect;
  vec2 mouth = lower.zw * aspect;

  vec2 eyeVec = le - re;
  float iod = length(eyeVec);
  if (iod < 0.012) {
    return vec2(0.0);
  }

  vec2 uAxis = eyeVec / iod;
  vec2 vAxis = vec2(-uAxis.y, uAxis.x);
  // Ensure vAxis points downward toward mouth even if landmarks are flipped.
  if (dot(mouth - (re + le) * 0.5, vAxis) < 0.0) {
    vAxis = -vAxis;
  }

  vec2 eyeMid = (re + le) * 0.5;
  float faceW = max(meta.x * aspect.x, iod * 2.15);
  float faceH = max(meta.y * aspect.y, length(mouth - eyeMid) * 2.45);
  // Estimate horizontal head yaw (-0.75..+0.75) so turned side-profiles never warp background.
  float yaw = clamp(dot(nose - eyeMid, uAxis) / max(iod * 0.52, 0.01), -0.75, 0.75);
  float rightSideVis = clamp(1.0 - max(yaw, 0.0) * 0.65, 0.25, 1.0);
  float leftSideVis = clamp(1.0 - max(-yaw, 0.0) * 0.65, 0.25, 1.0);

  vec2 disp = vec2(0.0);

  // 1. Big Eyes (smooth C2 radial magnification centered on exact detected eye landmarks)
  float eyeAmt = clamp(morph.y, 0.0, 1.0) * alpha;
  if (eyeAmt > 0.002) {
    float eyeR = clamp(iod * 0.44, 0.018, 0.16);
    float eyeR2 = eyeR * eyeR;
    float gain = eyeAmt * 0.25;

    vec2 dR = pIso - re;
    float distR2 = dot(dR, dR);
    if (distR2 < eyeR2) {
      float fall = 1.0 - distR2 / eyeR2;
      float w = fall * fall;
      disp -= dR * (gain * w);
    }

    vec2 dL = pIso - le;
    float distL2 = dot(dL, dL);
    if (distL2 < eyeR2) {
      float fall = 1.0 - distL2 / eyeR2;
      float w = fall * fall;
      disp -= dL * (gain * w);
    }
  }

  // 2. Slim Face (smooth jawline & cheek contour inward pull toward lower-face centerline)
  float slimAmt = clamp(morph.x, 0.0, 1.0) * alpha;
  if (slimAmt > 0.002) {
    vec2 target = mouth + vAxis * (faceH * 0.12);
    float cheekRad = clamp(faceW * 0.56, 0.035, 0.34);
    float cheekRad2 = cheekRad * cheekRad;

    // Viewer-left cheek / masseter contour (around subject's right jaw)
    vec2 cheekR = eyeMid + vAxis * (faceH * 0.44) - uAxis * (faceW * 0.46);
    vec2 diffR = pIso - cheekR;
    float dR2 = dot(diffR, diffR);
    if (dR2 < cheekRad2) {
      float fall = 1.0 - dR2 / cheekRad2;
      float w = fall * fall;
      vec2 pullOut = safeNorm(cheekR - target, -uAxis);
      disp += pullOut * (faceW * 0.135 * slimAmt * rightSideVis * w);
    }

    // Viewer-right cheek / masseter contour (around subject's left jaw)
    vec2 cheekL = eyeMid + vAxis * (faceH * 0.44) + uAxis * (faceW * 0.46);
    vec2 diffL = pIso - cheekL;
    float dL2 = dot(diffL, diffL);
    if (dL2 < cheekRad2) {
      float fall = 1.0 - dL2 / cheekRad2;
      float w = fall * fall;
      vec2 pullOut = safeNorm(cheekL - target, uAxis);
      disp += pullOut * (faceW * 0.135 * slimAmt * leftSideVis * w);
    }
  }

  // 3. V-Chin / Lower Jaw Taper (gentle upward + inward lower-chin sculpting)
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
      float w = fall * fall;
      vec2 dirR = safeNorm(jawR - (mouth - vAxis * (faceH * 0.04)), -uAxis + vAxis * 0.4);
      disp += dirR * (faceW * 0.11 * chinAmt * rightSideVis * w);
    }

    vec2 jawL = mouth + vAxis * (faceH * 0.20) + uAxis * (faceW * 0.34);
    vec2 djL = pIso - jawL;
    float djL2 = dot(djL, djL);
    if (djL2 < chinR2) {
      float fall = 1.0 - djL2 / chinR2;
      float w = fall * fall;
      vec2 dirL = safeNorm(jawL - (mouth - vAxis * (faceH * 0.04)), uAxis + vAxis * 0.4);
      disp += dirL * (faceW * 0.11 * chinAmt * leftSideVis * w);
    }

    // Subtle vertical chin lift
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

// Compute natural rose-coral lip tint strictly inside detected mouth ellipse (teeth protected!).
vec3 applyFaceLipTint(
    vec3 rgb,
    vec2 sampleIso,
    vec2 aspect,
    vec4 eyes,
    vec4 lower,
    vec4 meta,
    float lipStrength
) {
  float alpha = clamp(meta.w, 0.0, 1.0);
  if (lipStrength < 0.005 || alpha < 0.005 || meta.z < 0.01) {
    return rgb;
  }

  // Fast 2-ALU mouth AABB reject: 98%+ of pixels exit immediately!
  vec2 mouth = lower.zw * aspect;
  float maxLipReach = max(meta.z * aspect.x * 0.72, meta.x * aspect.x * 0.28);
  vec2 dMouth = abs(sampleIso - mouth);
  if (dMouth.x > maxLipReach || dMouth.y > maxLipReach) {
    return rgb;
  }

  vec2 re = eyes.xy * aspect;
  vec2 le = eyes.zw * aspect;
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
  if (r2 >= 1.35) {
    return rgb;
  }

  float ovalMask = 1.0 - smoothstep(0.45, 1.25, r2);
  float luma = dot(rgb, vec3(0.299, 0.587, 0.114));
  float maxC = max(rgb.r, max(rgb.g, rgb.b));
  float minC = min(rgb.r, min(rgb.g, rgb.b));
  float sat = maxC - minC;

  // Lip pigment gate: require warm red dominance & exclude bright desaturated teeth + dark cavities.
  float warmGate = smoothstep(0.015, 0.095, rgb.r - rgb.g);
  float teethProtect = 1.0 - smoothstep(0.56, 0.74, luma) * (1.0 - smoothstep(0.05, 0.16, sat));
  float darkProtect = smoothstep(0.06, 0.16, luma);
  float mask = clamp(ovalMask * warmGate * teethProtect * darkProtect * alpha, 0.0, 1.0);

  // Soft Douyin rose-berry glaze (blended multiplicatively + slight warm sheen so lip texture stays intact)
  vec3 roseTone = vec3(0.92, 0.36, 0.44);
  vec3 glazed = mix(rgb, rgb * mix(vec3(1.0), roseTone * 1.18, 0.72) + vec3(0.055, -0.012, 0.004), 0.75);
  return mix(rgb, clamp(glazed, 0.0, 1.0), mask * lipStrength * 0.72);
}

void main() {
  vec2 safeSize = max(u_size, vec2(1.0));
  vec2 posPx = FlutterFragCoord().xy;

  // ImageFiltered renders the child subtree into a child-sized offscreen texture
  // (u_size ~= u_rect.zw) where FlutterFragCoord() is local [0..u_size] across Metal,
  // Vulkan, and OpenGL ES. Only treat as root-pass coordinates if u_size is clearly
  // larger than u_rect.zw and fully contains u_rect (never falsely shift on notched screens!).
  bool childSized = abs(safeSize.x - u_rect.z) <= 6.0 && abs(safeSize.y - u_rect.w) <= 6.0;
  bool inRootPass = !childSized &&
      (u_rect.z > 1.0 && u_rect.w > 1.0) &&
      (u_rect.x + u_rect.z <= safeSize.x + 12.0) &&
      (u_rect.y + u_rect.w <= safeSize.y + 12.0) &&
      (u_rect.x >= -12.0) &&
      (u_rect.y >= -12.0);
  vec2 originPx = inRootPass ? u_rect.xy : vec2(0.0);
  vec2 viewSizePx = inRootPass ? u_rect.zw : safeSize;

  vec2 uv = (posPx - originPx) / max(viewSizePx, vec2(1.0));
  if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
    vec2 passUv = clamp(posPx / safeSize, vec2(0.5) / safeSize, vec2(1.0) - vec2(0.5) / safeSize);
    fragColor = texture(u_texture, passUv);
  } else {
    vec2 aspect = vec2(viewSizePx.x / max(viewSizePx.y, 1.0), 1.0);
    vec2 pIso = uv * aspect;

    vec2 totalDispIso = computeFaceWarpIso(pIso, aspect, u_f0_eyes, u_f0_lower, u_f0_meta, u_morph)
        + computeFaceWarpIso(pIso, aspect, u_f1_eyes, u_f1_lower, u_f1_meta, u_morph);

    vec2 warpedUv = clamp(uv + totalDispIso / aspect, vec2(0.001), vec2(0.999));
    vec2 samplePx = originPx + warpedUv * viewSizePx;
    vec2 texUv = clamp(samplePx / safeSize, vec2(0.5) / safeSize, vec2(1.0) - vec2(0.5) / safeSize);

    vec4 texel = texture(u_texture, texUv);
    vec3 rgb = texel.a > 1e-4 ? clamp(texel.rgb / texel.a, 0.0, 1.0) : vec3(0.0);

    if (u_morph.w > 0.005) {
      vec2 sampleIso = warpedUv * aspect;
      rgb = applyFaceLipTint(rgb, sampleIso, aspect, u_f0_eyes, u_f0_lower, u_f0_meta, u_morph.w);
      rgb = applyFaceLipTint(rgb, sampleIso, aspect, u_f1_eyes, u_f1_lower, u_f1_meta, u_morph.w);
    }

    fragColor = vec4(rgb * texel.a, texel.a);
  }
}
