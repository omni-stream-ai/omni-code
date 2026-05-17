#include <flutter/runtime_effect.glsl>

precision highp float;

uniform vec2 uSize;
uniform float uTime;
uniform float uIntensity;
uniform float uDarkMode;

out vec4 fragColor;

float circleMask(float dist, float radius, float feather) {
  return 1.0 - smoothstep(radius - feather, radius + feather, dist);
}

float ringMask(float dist, float radius, float halfWidth, float feather) {
  return 1.0 - smoothstep(halfWidth, halfWidth + feather, abs(dist - radius));
}

float softBand(float value, float center, float width, float feather) {
  return 1.0 - smoothstep(width, width + feather, abs(value - center));
}

float bandEdge(float value, float center, float width, float edgeWidth, float feather) {
  float d = abs(value - center);
  return 1.0 - smoothstep(edgeWidth, edgeWidth + feather, abs(d - width));
}

float hash(vec2 p) {
  return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float noise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  vec2 u = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(hash(i + vec2(0.0, 0.0)), hash(i + vec2(1.0, 0.0)), u.x),
    mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x),
    u.y
  );
}

float fbm(vec2 p) {
  float value = 0.0;
  float amplitude = 0.5;
  for (int i = 0; i < 4; i++) {
    value += amplitude * noise(p);
    p *= 2.0;
    amplitude *= 0.54;
  }
  return value;
}

mat2 rot(float a) {
  float s = sin(a);
  float c = cos(a);
  return mat2(c, -s, s, c);
}

vec3 paletteBlue(float t) {
  vec3 a = vec3(0.07, 0.12, 0.34);
  vec3 b = vec3(0.18, 0.38, 0.96);
  vec3 c = vec3(0.47, 0.83, 1.00);
  vec3 d = vec3(0.73, 0.45, 1.00);
  return mix(mix(a, b, smoothstep(0.0, 0.4, t)), mix(c, d, smoothstep(0.5, 1.0, t)), smoothstep(0.3, 0.9, t));
}

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  vec2 p = uv * 2.0 - 1.0;
  p.x *= uSize.x / uSize.y;

  float theme = clamp(uDarkMode, 0.0, 1.0);
  float intensity = mix(0.60, 1.0, clamp(uIntensity, 0.0, 1.0));
  float time = uTime * 6.28318530718;
  float pulse = 1.0 + 0.014 * intensity * sin(time * 1.12);

  vec2 sphere = p / pulse;
  float r = length(sphere);
  float orbMask = circleMask(r, 0.80, 0.12);
  float shellRing = ringMask(r, 0.80, 0.020, 0.034);
  float rimBand = ringMask(r, 0.75, 0.080, 0.050);

  vec2 flow = rot(0.16 * sin(time * 0.30) + 0.10) * sphere * 1.72;
  vec2 warp = vec2(
    fbm(flow + vec2(time * 0.10, -time * 0.08)),
    fbm(flow.yx * 1.04 + vec2(-time * 0.08, time * 0.12))
  );
  vec2 q = sphere + (warp - 0.5) * 0.08;
  float fogA = fbm(q * 1.28 + vec2(time * 0.04, -time * 0.03));
  float fogB = fbm(rot(0.46) * q * 1.36 - vec2(time * 0.04, time * 0.02));
  float fogC = fbm(rot(-0.34) * q * 1.10 + vec2(-time * 0.03, time * 0.04));
  float angle = atan(q.y, q.x);
  float radius = length(q);
  float liquidNoise = fbm(rot(0.28) * q * 3.20 + vec2(time * 0.05, -time * 0.04));
  float liquidNoiseB = fbm(rot(-0.34) * q * 3.60 + vec2(-time * 0.04, time * 0.05));
  float smokeVeil = fbm(rot(0.14) * q * 2.18 + vec2(time * 0.032, -time * 0.026));
  float smokePocketA = exp(-5.6 * dot(
      (q - vec2(0.22, -0.02)) * vec2(0.92, 1.34),
      (q - vec2(0.22, -0.02)) * vec2(0.92, 1.34)));
  float smokePocketB = exp(-7.2 * dot(
      (q - vec2(-0.24, 0.28)) * vec2(1.28, 0.94),
      (q - vec2(-0.24, 0.28)) * vec2(1.28, 0.94)));

  float threadWarp = fbm(rot(0.22) * sphere * 3.4 + vec2(time * 0.050, -time * 0.035));
  float threadPhase = angle * 25.0 + time * 0.42 + threadWarp * 5.8;
  float threadWaveA = 0.5 + 0.5 * sin(threadPhase);
  float threadWaveB = 0.5 + 0.5 * sin(angle * 37.0 - time * 0.34 + threadWarp * 7.4);
  float outerThreads =
      (smoothstep(0.82, 0.99, threadWaveA) * 0.72 +
       smoothstep(0.88, 1.00, threadWaveB) * 0.54) *
      rimBand *
      (0.55 + 0.45 * smoothstep(0.22, 0.90, threadWarp));
  float innerFilamentA = ringMask(
      radius,
      0.54 + 0.075 * sin(angle * 2.7 - time * 0.19) + (fogA - 0.5) * 0.060,
      0.008,
      0.020);
  float innerFilamentB = ringMask(
      radius,
      0.64 + 0.052 * sin(angle * 4.3 + time * 0.15) + (fogB - 0.5) * 0.050,
      0.006,
      0.018);
  float innerThreads = (innerFilamentA * 0.34 + innerFilamentB * 0.28) *
      smoothstep(0.12, 0.82, radius) *
      (1.0 - smoothstep(0.78, 0.92, radius));

  float streamA =
      q.y -
      0.12 +
      0.52 * sin(q.x * 1.36 - time * 0.20) +
      0.15 * sin(q.x * 3.08 + time * 0.12) +
      (fogA - 0.5) * 0.16;
  float streamB =
      q.y +
      0.06 -
      0.46 * sin((q.x + 0.20) * 1.24 + time * 0.18) +
      0.14 * cos(q.x * 2.62 - time * 0.10) +
      (fogB - 0.5) * 0.16;
  float streamC =
      radius -
      (0.24 + 0.06 * sin(angle * 2.20 - time * 0.16) + (fogC - 0.5) * 0.03);

  float ribbonWidthA =
      0.35 + smoothstep(0.20, 0.88, liquidNoise) * 0.09 + (fogA - 0.5) * 0.05;
  float ribbonWidthB =
      0.33 + smoothstep(0.18, 0.90, liquidNoiseB) * 0.08 + (fogB - 0.5) * 0.05;
  float ribbonWidthC = 0.12 + (fogC - 0.5) * 0.03;

  float ribbonA = softBand(streamA, 0.0, ribbonWidthA, 0.05);
  float ribbonB = softBand(streamB, 0.0, ribbonWidthB, 0.05);
  float ribbonC =
      softBand(streamC, 0.0, ribbonWidthC, 0.04) *
      smoothstep(-0.12, 0.62, q.x);

  vec2 lobeA1Uv = (q - vec2(-0.17, 0.02)) * vec2(1.16, 1.42);
  vec2 lobeA2Uv = (q - vec2(0.08, -0.10)) * vec2(1.20, 1.22);
  vec2 lobeB1Uv = (q - vec2(0.02, 0.18)) * vec2(1.08, 1.34);
  float lobeA = exp(-12.0 * dot(lobeA1Uv, lobeA1Uv)) +
      exp(-14.0 * dot(lobeA2Uv, lobeA2Uv));
  float lobeB = exp(-13.0 * dot(lobeB1Uv, lobeB1Uv));
  ribbonA = max(ribbonA, lobeA * 0.58);
  ribbonB = max(ribbonB, lobeB * 0.62);

  float ribbonGlowA = softBand(streamA, 0.0, ribbonWidthA * 1.04, 0.07);
  float ribbonGlowB = softBand(streamB, 0.0, ribbonWidthB * 1.04, 0.07);
  float ribbonGlowC = softBand(streamC, 0.0, ribbonWidthC * 1.10, 0.06);
  float ribbonEdgeA = bandEdge(streamA, 0.0, ribbonWidthA * 0.92, 0.024, 0.028);
  float ribbonEdgeB = bandEdge(streamB, 0.0, ribbonWidthB * 0.92, 0.024, 0.028);
  float ribbonEdgeC = bandEdge(streamC, 0.0, ribbonWidthC * 0.90, 0.018, 0.022);
  float ribbonSpecA = softBand(
      streamA,
      -ribbonWidthA * 0.16 + ((liquidNoise - 0.5) * 0.12),
      ribbonWidthA * 0.24,
      0.018);
  float ribbonSpecB = softBand(
      streamB,
      -ribbonWidthB * 0.14 + ((liquidNoiseB - 0.5) * 0.12),
      ribbonWidthB * 0.24,
      0.018);
  float ribbonSpecC = softBand(
      streamC,
      -ribbonWidthC * 0.10,
      ribbonWidthC * 0.22,
      0.016);
  float ribbonShadowA = clamp(
      softBand(streamA, ribbonWidthA * 0.18, ribbonWidthA * 0.88, 0.06) - ribbonA * 0.84,
      0.0,
      1.0);
  float ribbonShadowB = clamp(
      softBand(streamB, ribbonWidthB * 0.18, ribbonWidthB * 0.88, 0.06) - ribbonB * 0.84,
      0.0,
      1.0);
  float ribbonShadowC = clamp(
      softBand(streamC, ribbonWidthC * 0.12, ribbonWidthC * 0.84, 0.05) - ribbonC * 0.82,
      0.0,
      1.0);

  float ribbonInnerA = softBand(streamA, ribbonWidthA * 0.02, ribbonWidthA * 0.54, 0.04);
  float ribbonInnerB = softBand(streamB, ribbonWidthB * 0.02, ribbonWidthB * 0.52, 0.04);
  float ribbonInnerC = softBand(streamC, 0.0, ribbonWidthC * 0.50, 0.03);

  vec2 coreUv = (sphere - vec2(-0.03, 0.08)) * vec2(1.04, 1.22);
  float coreGlow = exp(-8.8 * dot(coreUv, coreUv));
  vec2 coreSeedUv = (sphere - vec2(-0.08, 0.03)) * vec2(1.28, 1.52);
  float coreSeed = exp(-25.0 * dot(coreSeedUv, coreSeedUv));
  vec2 coreHotUv = (sphere - vec2(-0.11, 0.01)) * vec2(1.52, 1.82);
  float coreHot = exp(-60.0 * dot(coreHotUv, coreHotUv));
  float lowerPool = exp(-5.8 * dot(
      (sphere - vec2(0.04, 0.26)) * vec2(0.92, 1.54),
      (sphere - vec2(0.04, 0.26)) * vec2(0.92, 1.54)));

  vec3 deepBase = mix(vec3(0.01, 0.04, 0.18), vec3(0.01, 0.03, 0.12), theme);
  vec3 midBlue = mix(vec3(0.04, 0.15, 0.46), vec3(0.03, 0.12, 0.38), theme);
  vec3 royalBlue = mix(vec3(0.14, 0.36, 1.00), vec3(0.12, 0.34, 0.98), theme);
  vec3 azure = mix(vec3(0.16, 0.64, 1.00), vec3(0.12, 0.58, 0.98), theme);
  vec3 cyan = mix(vec3(0.00, 0.92, 1.00), vec3(0.00, 0.86, 1.00), theme);
  vec3 violet = mix(vec3(0.50, 0.24, 1.00), vec3(0.46, 0.20, 0.98), theme);
  vec3 hotPink = mix(vec3(0.94, 0.40, 1.00), vec3(0.88, 0.34, 0.98), theme);
  vec3 lavender = mix(vec3(0.84, 0.76, 1.00), vec3(0.76, 0.68, 1.00), theme);
  vec3 pearl = vec3(0.86, 0.98, 1.00);
  vec3 milk = vec3(0.99, 1.00, 1.00);
  vec3 ribbonColorA = mix(
      mix(royalBlue, azure, 0.48),
      cyan,
      smoothstep(-0.9, 0.9, q.x + q.y * 0.34 + (liquidNoise - 0.5) * 0.28));
  ribbonColorA = mix(
      ribbonColorA,
      pearl,
      smoothstep(0.48, 0.92, liquidNoise) * 0.18);
  vec3 ribbonColorB = mix(
      mix(violet, hotPink, 0.28),
      royalBlue,
      smoothstep(-0.8, 0.8, -q.x + q.y * 0.26 + (liquidNoiseB - 0.5) * 0.24));
  ribbonColorB = mix(
      ribbonColorB,
      hotPink,
      smoothstep(0.42, 0.88, liquidNoiseB) * 0.24);
  vec3 ribbonColorC = mix(cyan, mix(lavender, hotPink, 0.28), 0.44 + (liquidNoise - 0.5) * 0.16);
  vec3 liquidA = mix(ribbonColorA * 0.94, mix(ribbonColorA, milk, 0.78),
      clamp(ribbonSpecA * 1.35 + ribbonEdgeA * 0.80, 0.0, 1.0));
  vec3 liquidB = mix(ribbonColorB * 0.94, mix(ribbonColorB, milk, 0.78),
      clamp(ribbonSpecB * 1.35 + ribbonEdgeB * 0.80, 0.0, 1.0));
  vec3 liquidC = mix(ribbonColorC * 0.90, mix(ribbonColorC, milk, 0.48),
      clamp(ribbonSpecC * 1.12 + ribbonEdgeC * 0.48, 0.0, 1.0));
  vec2 glossUv = (sphere + vec2(0.18, 0.18)) * vec2(0.92, 1.44);
  float glossArc = exp(-84.0 * pow(length(glossUv) - 0.24, 2.0));
  glossArc *= (1.0 - smoothstep(-0.10, 0.30, sphere.x));
  glossArc *= (1.0 - smoothstep(-0.12, 0.24, sphere.y));
  float fresnel = pow(smoothstep(0.18, 0.88, r), 2.0);

  vec3 orb = mix(
    deepBase,
    midBlue,
    smoothstep(-0.40, 0.42, sphere.y * 0.72)
  );
  orb *= 0.72;
  orb = mix(orb, mix(midBlue, royalBlue, 0.36), smoothstep(0.36, 0.82, smokeVeil) * 0.18);
  orb -= vec3(0.02, 0.05, 0.17) * smokePocketA * 0.28;
  orb -= vec3(0.02, 0.04, 0.15) * smokePocketB * 0.20;
  orb += mix(azure, cyan, 0.56) * coreGlow * 0.20;
  orb += mix(cyan, pearl, 0.32) * coreSeed * 0.34;
  orb += mix(milk, hotPink, 0.10) * coreHot * 0.24;
  orb += royalBlue * lowerPool * 0.05;

  orb -= vec3(0.05, 0.07, 0.14) * ribbonShadowA * 0.30;
  orb -= vec3(0.07, 0.05, 0.14) * ribbonShadowB * 0.30;
  orb -= vec3(0.03, 0.04, 0.10) * ribbonShadowC * 0.16;

  orb = mix(orb, liquidA, ribbonA * 0.70);
  orb = mix(orb, liquidB, ribbonB * 0.68);
  orb = mix(orb, liquidC, ribbonC * 0.28);

  orb += ribbonColorA * ribbonA * 0.18;
  orb += ribbonColorB * ribbonB * 0.17;
  orb += ribbonColorC * ribbonC * 0.06;
  orb += ribbonColorA * ribbonGlowA * 0.07;
  orb += ribbonColorB * ribbonGlowB * 0.07;
  orb += ribbonColorC * ribbonGlowC * 0.03;
  orb += mix(ribbonColorA, milk, 0.70) * ribbonSpecA * 0.34;
  orb += mix(ribbonColorB, milk, 0.70) * ribbonSpecB * 0.34;
  orb += mix(ribbonColorC, milk, 0.42) * ribbonSpecC * 0.14;
  orb += mix(ribbonColorA, milk, 0.42) * ribbonEdgeA * 0.24;
  orb += mix(ribbonColorB, milk, 0.42) * ribbonEdgeB * 0.24;
  orb += mix(ribbonColorC, milk, 0.28) * ribbonEdgeC * 0.10;
  orb += mix(ribbonColorA, milk, 0.24) * ribbonInnerA * 0.10;
  orb += mix(ribbonColorB, milk, 0.24) * ribbonInnerB * 0.10;
  orb += mix(ribbonColorC, milk, 0.12) * ribbonInnerC * 0.04;
  orb += mix(cyan, pearl, 0.42) * innerThreads * 0.22;
  orb += mix(lavender, milk, 0.48) * outerThreads * 0.42;
  orb += mix(milk, cyan, 0.34) * glossArc * 0.34;
  orb += mix(azure, cyan, 0.56) * fresnel * 0.18;
  orb += mix(violet, hotPink, 0.42) * fresnel * 0.08;

  orb *= 1.0 - smoothstep(0.62, 0.95, r) * 0.18;
  orb += mix(cyan, pearl, 0.30) * shellRing * (0.18 + 0.04 * intensity);
  orb += mix(lavender, milk, 0.56) * outerThreads * shellRing * 0.18;

  vec3 col = orb * orbMask;
  col = col / (1.0 + col * 0.26);
  col = pow(col, vec3(0.94));
  float alpha = max(orbMask, shellRing * 0.18);
  fragColor = vec4(col, alpha);
}
