// The CCTV look (game/cctv.gdshader) for a camera feed inside a window:
// wash, scanlines, rolling band, grain, vignette and a touch of lens
// fringing. Conveniently, it also hides tracking jitter.
shader_type canvas_item;


uniform vec3 tint = vec3(0.82, 1.0, 0.9);
uniform float desaturate : hint_range(0.0, 1.0) = 0.55;
uniform float scanline_strength : hint_range(0.0, 1.0) = 0.18;
uniform float scanline_count = 360.0;
uniform float grain : hint_range(0.0, 0.3) = 0.06;
uniform float vignette : hint_range(0.0, 2.0) = 0.9;
uniform float fringe : hint_range(0.0, 0.01) = 0.0015;
uniform float band_strength : hint_range(0.0, 0.3) = 0.05;

float rand(vec2 co) {
	return fract(sin(dot(co, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = UV;
	vec2 c = uv - 0.5;
	float r = texture(TEXTURE, uv + c * fringe).r;
	float g = texture(TEXTURE, uv).g;
	float b = texture(TEXTURE, uv - c * fringe).b;
	vec3 col = vec3(r, g, b);

	float luma = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, vec3(luma), desaturate) * tint;

	col *= 1.0 - scanline_strength * (0.5 + 0.5 * sin(uv.y * scanline_count * 3.14159));
	float band = smoothstep(0.0, 0.08, abs(fract(uv.y * 0.6 - TIME * 0.07) - 0.5));
	col *= 1.0 - band_strength * (1.0 - band);
	col += (rand(uv * 640.0 + TIME) - 0.5) * grain;
	col *= 1.0 - vignette * dot(c, c);

	COLOR = vec4(col, 1.0);
}
