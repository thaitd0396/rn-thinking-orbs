package com.rnthinkingorbs

internal object ThinkingOrbsAgsl {
  const val source = """
uniform float phase;
uniform float size;
uniform float fit;
uniform float dotScale;
uniform float contentsScale;
uniform float2 origin;
uniform float3 userR0;
uniform float3 userR1;
uniform float3 userR2;
uniform float4 accent;
uniform float4 ink;

const float TAU = 6.28318530718;
const float GOLDEN = 2.399963;
const float DOT_COUNT = 160.0;

float cl(float u) {
  return clamp(u, 0.0, 1.0);
}

float3 rotYawPitch(float3 p, float ay, float ax) {
  float ca = cos(ay);
  float sa = sin(ay);
  float x = p.x * ca - p.z * sa;
  float z = p.x * sa + p.z * ca;
  float cb = cos(ax);
  float sb = sin(ax);
  float y = p.y * cb - z * sb;
  z = p.y * sb + z * cb;
  return float3(x, y, z);
}

half4 main(float2 fragCoord) {
  float N = DOT_COUNT;
  float t = phase;
  float S = size;
  float h = S * 0.5;
  float R = S * 0.3;
  half4 color = half4(0.0);

  for (int i = 0; i < 160; i++) {
    float fi = float(i);
    float y = 1.0 - (fi / (N - 1.0)) * 2.0;
    float r = sqrt(max(0.0, 1.0 - y * y));
    float th = fi * GOLDEN;
    float3 p = float3(cos(th) * r, y, sin(th) * r);
    float pol = acos(clamp(p.y, -1.0, 1.0));
    float az = atan(p.z, p.x);
    float a = sin((4.0 * az + 6.0 * pol) - (TAU * 2.0 * t));
    float b = sin((4.0 * az - 6.0 * pol) + (TAU * 2.0 * t));
    float w = cl((a * b + 1.0) / 2.0);
    float scale = 0.5 + 1.3 * w;
    float fade = 0.2 + 0.8 * w;
    float accentAmt = w > 0.9 ? 1.0 : 0.0;
    p = rotYawPitch(p, TAU * t, 0.36);
    p = float3(dot(userR0, p), dot(userR1, p), dot(userR2, p));

    float z = p.z;
    float per = 3.5 / (3.5 - z);
    float d = cl((z + 1.1) / 2.2);
    float x = h + (p.x * R) * per;
    float yy = h + (p.y * R) * per;
    float rad = dotScale * (0.4 + 1.6 * d) * per * scale;
    float alpha = (0.07 + 0.93 * pow(d, 1.55)) * fade;
    float fx = h + (x - h) * fit;
    float fy = h + (yy - h) * fit;
    float fr = rad * (0.55 + 0.45 * fit);
    if (fr > 0.05 && alpha > 0.004) {
      float2 pos = (origin + float2(fx, fy)) * contentsScale;
      float radius = fr * contentsScale;
      float dist = length(fragCoord - pos);
      float aa = max(1.0, radius * 0.08);
      float cover = 1.0 - smoothstep(radius - aa, radius, dist);
      float srcA = min(1.0, alpha) * cover;
      float4 base = mix(ink, accent, accentAmt);
      half4 src = half4(half3(base.rgb) * srcA, srcA);
      color = src + color * (1.0 - src.a);
    }
  }

  float outA = color.a;
  half3 rgb = outA > 0.0 ? color.rgb / outA : half3(0.0);
  return half4(rgb, outA);
}
"""
}
