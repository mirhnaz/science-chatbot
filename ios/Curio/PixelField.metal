#include <metal_stdlib>
using namespace metal;

// The pixel field (docs/DESIGN.md → Pixel field): the same maths as the web's
// src/client/field-worker.ts, as a SwiftUI colorEffect so the GPU draws it.
// One cell = 8 pt; each cell is a square "pixel" with a small gap.
// Scenes: 0 starfield + comet (phones), 1 atom (Trail), 2 solar system (Home),
// 3 the stamp celebration burst (from the tap point).
// `rect` is the empty space the scene must fit in (left, top, right,
// bottom); the scene never draws outside it. `fill`: background pixels
// start below a line per column (x of the split, the line left of it, the
// line right of it; 0: a gradient over the whole field, as on phones).
// A space touching the left edge puts the sun there with the orbits' left
// halves off the field; elsewhere the solar system is centred.

static float hash(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

static float2 rot(float2 p, float a) {
    float c = cos(a), s = sin(a);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

static float ringDist(float2 q, float2 ab) {
    return abs(length(q / ab) - 1.0) * min(ab.x, ab.y);
}

[[ stitchable ]] half4 pixelField(float2 position, half4 color, float2 size, float time, float scene,
                                  float intensity, float3 pointer, float3 tap, float3 fill, float4 rect,
                                  half4 dim, half4 mid, half4 lit, half4 crest,
                                  half4 p1, half4 p2, half4 p3, half4 p4) {
    const float C = 8.0;
    float2 cell = floor(position / C), center = (cell + 0.5) * C, local = fract(position / C) - 0.5;
    if (max(abs(local.x), abs(local.y)) > 0.36) return half4(0.0);
    float y01 = center.y / size.y, t = time;
    float h1 = hash(cell), h2 = hash(cell + 17.0);
    if (scene > 2.5) {
        // Scene 3, the stamp celebration: rings and sparkles from the tap
        // point (the stamp), fading over about three seconds.
        float age = tap.z, dist = length(center - tap.xy), b = 0.0;
        for (int k = 0; k < 3; k++) {
            float since = age - float(k) * 0.18;
            if (since > 0.0) b = max(b, exp(-pow(dist - since * 260.0, 2.0) / (2.8 * C * C)) * clamp(1.0 - since * 0.7, 0.0, 1.0) * step(0.25, h2));
        }
        float spark = h1 > 0.9 && dist < 26.0 * C ? (0.5 + 0.5 * sin(t * 9.0 + h2 * 40.0)) * clamp(1.0 - age * 0.45, 0.0, 1.0) * smoothstep(26.0 * C, 6.0 * C, dist) : 0.0;
        float burst = max(b, spark);
        if (burst < 0.05) return half4(0.0);
        half4 bc = burst < 0.3 ? mid : burst < 0.6 ? lit : crest;
        if (spark >= b) { float k = floor(h2 * 4.0); bc = k < 1.0 ? p1 : k < 2.0 ? p2 : k < 3.0 ? p3 : p4; }
        half a = half(intensity);
        return half4(bc.rgb * a, a);
    }
    // Below the fill line: 0 at the line, 1 at the bottom edge.
    float line = center.x < fill.x ? fill.y : fill.z;
    bool filled = line > 0.5;
    float yy = filled ? (center.y - line) / max(size.y - line, 1.0) : y01;
    float d = filled ? smoothstep(0.0, 0.3, yy) * mix(0.2, 1.0, yy * yy) : pow(smoothstep(0.45, 1.0, y01), 2.0);
    float v = h1 < d * 0.9 ? 0.18 + 0.22 * (0.5 + 0.5 * sin(t * 0.8 + h2 * 6.2832)) : 0.0;
    if (h2 > (scene < 0.5 ? 0.985 : 0.992)) v = max(v, (0.35 + 0.35 * sin(t * 2.3 + h1 * 40.0)) * smoothstep(filled ? 0.0 : 0.05, filled ? 0.15 : 0.4, yy));

    float s = 0.0, ci = 0.0, r = (rect.w - rect.y) * 0.5;
    float2 f = float2(rect.x + rect.z, rect.y + rect.w) * 0.5;
    if (r < 5.0 * C) {
    } else if (scene < 0.5) {
        float ph = fract(t / 7.0);
        float2 head = float2(mix(-0.1, 1.1, ph) * size.x, f.y + (ph - 0.5) * r * 1.2);
        float2 dir = normalize(float2(size.x * 1.2, r * 1.2)), rel = center - head;
        float along = dot(rel, -dir), perp = abs(dot(rel, float2(-dir.y, dir.x))), len = 20.0 * C;
        if (along > 0.0 && along < len && perp < C * (0.6 + 1.4 * along / len)) s = 0.85 * (1.0 - along / len);
        s = max(s, exp(-dot(rel, rel) / (2.8 * C * C)));
    } else if (scene < 1.5) {
        float a = min(r * 1.05, (rect.z - rect.x) * 0.3);
        float2 ab = float2(a, a * 0.34);
        if (length(center - f) < C * 2.2 * (1.0 + 0.08 * sin(t * 2.0))) { s = 1.0; ci = 3.0; }
        for (int i = 0; i < 3; i++) {
            float fi = float(i), ang = fi * 1.0472;
            if (ringDist(rot(center - f, -ang), ab) < 0.55 * C) s = max(s, 0.42);
            float w = t * (0.9 + 0.25 * fi) + fi * 2.1;
            if (length(center - f - rot(float2(ab.x * cos(w), ab.y * sin(w)), ang)) < 1.4 * C) { s = 1.0; ci = 1.0; }
        }
    } else {
        // The sun near the left of the space; orbits out to its right edge
        // and within its height (the left halves run off the field).
        float sun = min(4.5 * C, r - 2.0 * C);
        bool edge = rect.x < 1.0;
        float2 c = float2(edge ? rect.x + (rect.z - rect.x) * 0.06 + sun + 2.0 * C : f.x, f.y);
        float dn = length(center - c), reach = (edge ? rect.z - c.x : (rect.z - rect.x) * 0.5) - 2.0 * C;
        if (dn < sun) { s = 1.0; ci = 3.0; } else if (dn < sun + 2.0 * C) s = 0.5;
        for (int i = 0; i < 4; i++) {
            float fi = float(i), a = reach * (0.34 + 0.22 * fi);
            float2 ab = float2(a, min(a * 0.22, r - 2.0 * C));
            if (ringDist(center - c, ab) < 0.5 * C) s = max(s, 0.4);
            float w = t * (0.5 / (1.0 + 0.6 * fi)) + fi * 1.7;
            if (length(center - c - float2(ab.x * cos(w), ab.y * sin(w))) < C * (1.3 + 0.35 * fi)) { s = 1.0; ci = fi + 1.0; }
        }
    }

    if (any(center < rect.xy - C) || any(center > rect.zw + C)) { s = 0.0; ci = 0.0; }
    float age = pointer.z, pd = length(center - pointer.xy);
    float hover = exp(-pd * pd / (24.5 * C * C)) * clamp(1.0 - age * 0.6, 0.0, 1.0) * (h1 > 0.3 ? 1.0 : 0.4);
    float tapAge = tap.z, td = length(center - tap.xy);
    float ripple = exp(-pow(td - tapAge * 220.0, 2.0) / (2.8 * C * C)) * clamp(1.0 - tapAge * 0.8, 0.0, 1.0) * step(0.2, h2);
    float fx = max(hover, ripple), level = max(max(v, s), fx);
    if (level < 0.05) return half4(0.0);
    half4 col = level < 0.3 ? dim : level < 0.55 ? mid : level < 0.8 ? lit : crest;
    if (ci > 0.5 && s >= max(v, fx)) col = ci < 1.5 ? p1 : ci < 2.5 ? p2 : ci < 3.5 ? p3 : p4;
    // The scene shows fully in its space; background pixels fade in below the line.
    float fade = filled ? smoothstep(-0.02, 0.1, yy) : smoothstep(0.0, 0.3, y01);
    half alpha = half(intensity * (filled && s > 0.05 && s >= max(v, fx) ? 1.0 : fade));
    return half4(col.rgb * alpha, alpha);
}
