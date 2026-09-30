// The CCTV look (game/cctv.gdshader) for a camera feed inside a window:
// wash, scanlines, rolling band, grain, vignette and a touch of lens
// fringing. Conveniently, it also hides tracking jitter.
//
// Night vision (the feed's camera also switches to CCTVFeed's infrared
// Environment, which "lights" the dark facility): brightness only, boosted
// and mapped to green phosphor, highlights burning towards white, heavy
// sensor noise and a round tube vignette.
//
// `cctv` = 0 turns the CCTV artefacts off (the Cameras app's filter toggle)
// while leaving night vision's own look.
shader_type canvas_item;


uniform vec3 tint = vec3(0.82, 1.0, 0.9);
uniform float desaturate : hint_range(0.0, 1.0) = 0.55;
uniform float scanline_strength : hint_range(0.0, 1.0) = 0.18;
uniform float scanline_count = 360.0;
uniform float grain : hint_range(0.0, 0.3) = 0.06;
uniform float vignette : hint_range(0.0, 2.0) = 0.9;
uniform float fringe : hint_range(0.0, 0.01) = 0.0015;
uniform float band_strength : hint_range(0.0, 0.3) = 0.05;
uniform float cctv : hint_range(0.0, 1.0) = 1.0;
// The feed's clock (CCTVFeed sets it once per feed frame), so grain and the
// rolling band move at the feed's frame rate, not the screen's.
uniform float feed_time = 0.0;

group_uniforms night_vision;
uniform bool night_vision = false;
uniform vec3 phosphor = vec3(0.3, 1.0, 0.4);
uniform float nv_gain = 2.0;
uniform float nv_grain : hint_range(0.0, 0.5) = 0.14;
group_uniforms;

float rand(vec2 co) {
	return fract(sin(dot(co, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = UV;
	vec2 c = uv - 0.5;
	float f = fringe * cctv;
	float r = texture(TEXTURE, uv + c * f).r;
	float g = texture(TEXTURE, uv).g;
	float b = texture(TEXTURE, uv - c * f).b;
	vec3 col = vec3(r, g, b);
	float luma = dot(col, vec3(0.299, 0.587, 0.114));
	float noise = rand(uv * 640.0 + feed_time) - 0.5;

	if (night_vision) {
		float l = pow(max(luma * nv_gain + noise * nv_grain, 0.0), 0.8);
		col = phosphor * l + vec3(0.6, 0.4, 0.6) * smoothstep(0.7, 1.3, l);
		// The intensifier tube: a round picture, fading out to the edges.
		vec2 round_c = c * vec2(TEXTURE_PIXEL_SIZE.y / TEXTURE_PIXEL_SIZE.x, 1.0);
		col *= smoothstep(0.9, 0.45, length(round_c));
	} else {
		col = mix(col, vec3(luma), desaturate * cctv) * mix(vec3(1.0), tint, cctv);
		col += noise * grain * cctv;
		col *= 1.0 - vignette * cctv * dot(c, c);
	}

	col *= 1.0 - scanline_strength * cctv * (0.5 + 0.5 * sin(uv.y * scanline_count * 3.14159));
	float band = smoothstep(0.0, 0.08, abs(fract(uv.y * 0.6 - feed_time * 0.07) - 0.5));
	col *= 1.0 - band_strength * cctv * (1.0 - band);

	COLOR = vec4(col, 1.0);
}
