//
//  Crayon.metal
//  ScaleSync
//
//  The hand-drawn wobble. Every drawn thing (feet, bars, lines, glyphs) is
//  displaced by a smooth value noise, the same idea as the mockups' SVG
//  feTurbulence + feDisplacementMap. The noise is a pure function of
//  position, so the wobble is stable and never animates.
//

#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

static float hash(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}

static float valueNoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + float2(1, 0)), u.x),
               mix(hash(i + float2(0, 1)), hash(i + float2(1, 1)), u.x), u.y);
}

/// - amount: peak displacement in points.
/// - scale: size of one wobble in points (larger is gentler).
[[ stitchable ]] float2 crayon(float2 position, float amount, float scale) {
    float2 p = position / scale;
    float dx = valueNoise(p) + 0.5 * valueNoise(p * 2.03 + 5.2) - 0.75;
    float dy = valueNoise(p + float2(17.3, 9.1)) + 0.5 * valueNoise(p * 2.03 + 11.7) - 0.75;
    return position + float2(dx, dy) * amount;
}
