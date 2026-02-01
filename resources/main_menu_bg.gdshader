shader_type canvas_item;

uniform float time_scale = 0.2;
uniform vec3 color_a = vec3(0.06, 0.07, 0.09);
uniform vec3 color_b = vec3(0.18, 0.12, 0.10);
uniform vec3 color_c = vec3(0.08, 0.12, 0.20);
uniform float vignette_strength = 0.6;

float hash(vec2 p) {
    p = fract(p * vec2(123.34, 345.45));
    p += dot(p, p + 34.345);
    return fract(p.x * p.y);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    float a = hash(i);
    float b = hash(i + vec2(1.0, 0.0));
    float c = hash(i + vec2(0.0, 1.0));
    float d = hash(i + vec2(1.0, 1.0));
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

void fragment() {
    vec2 uv = UV;
    float t = TIME * time_scale;

    vec2 drift = vec2(t * 0.08, -t * 0.05);
    vec2 warp = vec2(
        sin((uv.y + t) * 6.0),
        cos((uv.x - t) * 5.0)
    ) * 0.035;
    vec2 p = uv + warp + drift;

    float n1 = noise(p * 3.0 + t * 0.5);
    float n2 = noise(p * 6.0 - t * 0.3);
    float mix1 = smoothstep(0.2, 0.8, n1);
    float mix2 = smoothstep(0.15, 0.85, n2);

    vec3 col = mix(color_a, color_b, mix1);
    col = mix(col, color_c, mix2 * 0.7);

    float vignette = 16.0 * uv.x * uv.y * (1.0 - uv.x) * (1.0 - uv.y);
    vignette = pow(vignette, 0.25);
    col *= mix(1.0, vignette, vignette_strength);

    COLOR = vec4(col, 1.0);
}
