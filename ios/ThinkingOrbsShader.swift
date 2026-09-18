enum ThinkingOrbsShader {
    static let source = """
    #include <metal_stdlib>
    using namespace metal;

    constant uint kDotCount = 160;
    constant float TAU = 6.28318530718;
    constant float GOLDEN = 2.399963f;

    struct Uniforms {
        float phase;
        float size;
        float fit;
        float dotScale;
        float contentsScale;
        float pad0;
        float2 viewport;
        float2 origin;
        float2 pad1;
        float4 userR0;
        float4 userR1;
        float4 userR2;
        float4 accent;
        float4 ink;
    };

    struct Dot {
        float2 pos;
        float radius;
        float alpha;
        float accentAmt;
        float z;
    };

    struct VSOut {
        float4 position [[position]];
        float2 uv;
        float4 color;
    };

    constant float2 kCorners[6] = {
        float2(-1.0, -1.0),
        float2( 1.0, -1.0),
        float2(-1.0,  1.0),
        float2(-1.0,  1.0),
        float2( 1.0, -1.0),
        float2( 1.0,  1.0)
    };

    static float cl(float u) {
        return clamp(u, 0.0, 1.0);
    }

    static Dot makeDot(uint i, constant Uniforms& u) {
        float N = float(kDotCount);
        float y = 1.0 - (float(i) / (N - 1.0)) * 2.0;
        float r = sqrt(max(0.0, 1.0 - y * y));
        float th = float(i) * GOLDEN;
        float3 p = float3(cos(th) * r, y, sin(th) * r);
        float pol = acos(clamp(p.y, -1.0, 1.0));
        float az = atan2(p.z, p.x);
        float t = u.phase;
        float a = sin((4.0 * az + 6.0 * pol) - (TAU * 2.0 * t));
        float b = sin((4.0 * az - 6.0 * pol) + (TAU * 2.0 * t));
        float w = cl((a * b + 1.0) / 2.0);
        float scale = 0.5 + 1.3 * w;
        float fade = 0.2 + 0.8 * w;
        float accentAmt = w > 0.9 ? 1.0 : 0.0;
        p = float3(dot(u.userR0.xyz, p), dot(u.userR1.xyz, p), dot(u.userR2.xyz, p));

        float z = p.z;
        float per = 3.5 / (3.5 - z);
        float d = cl((z + 1.1) / 2.2);
        float S = u.size;
        float h = S * 0.5;
        float R = S * 0.3;
        float x = h + (p.x * R) * per;
        float yy = h + (p.y * R) * per;
        float rad = u.dotScale * (0.4 + 1.6 * d) * per * scale;
        float alpha = (0.07 + 0.93 * pow(d, 1.55)) * fade;
        float fx = h + (x - h) * u.fit;
        float fy = h + (yy - h) * u.fit;
        float fr = rad * (0.55 + 0.45 * u.fit);

        Dot dot;
        dot.pos = (u.origin + float2(fx, fy)) * u.contentsScale;
        dot.radius = fr * u.contentsScale;
        dot.alpha = min(1.0, alpha);
        dot.accentAmt = accentAmt;
        dot.z = z;
        if (fr <= 0.05 || alpha <= 0.004) {
            dot.radius = 0.0;
            dot.alpha = 0.0;
        }
        return dot;
    }

    kernel void prepareDots(
        device Dot* dots [[buffer(0)]],
        constant Uniforms& u [[buffer(1)]]
    ) {
        for (uint i = 0; i < kDotCount; i++) {
            dots[i] = makeDot(i, u);
        }
        for (uint i = 1; i < kDotCount; i++) {
            Dot key = dots[i];
            int j = int(i) - 1;
            while (j >= 0 && dots[j].z > key.z) {
                dots[j + 1] = dots[j];
                j -= 1;
            }
            dots[j + 1] = key;
        }
    }

    vertex VSOut vertexDot(
        uint vid [[vertex_id]],
        uint iid [[instance_id]],
        const device Dot* dots [[buffer(0)]],
        constant Uniforms& u [[buffer(1)]]
    ) {
        Dot d = dots[iid];
        float2 pixel = d.pos + kCorners[vid] * d.radius;
        float2 ndc = float2(
            (pixel.x / u.viewport.x) * 2.0 - 1.0,
            1.0 - (pixel.y / u.viewport.y) * 2.0
        );
        float4 base = mix(u.ink, u.accent, d.accentAmt);
        VSOut out;
        out.position = float4(ndc, 0.0, 1.0);
        out.uv = kCorners[vid];
        out.color = float4(base.rgb, base.a * d.alpha);
        return out;
    }

    fragment float4 fragmentDot(VSOut in [[stage_in]]) {
        float dist = length(in.uv);
        float aa = max(fwidth(dist) * 1.5, 0.003);
        float cover = 1.0 - smoothstep(1.0 - aa, 1.0, dist);
        float a = in.color.a * cover;
        return float4(in.color.rgb * a, a);
    }
    """
}
