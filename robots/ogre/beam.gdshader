// Ogre's eye beam: a fake volumetric light cone (works without fog).
// Additive, brightest at the eye, fading along its length and towards its
// edges, and softened where it meets walls and the floor so there's no hard
// line. `strength` is set per robot by ogre_beam.gd (it follows the eye's
// spotlight, so blinks and flashes carry into the cone).
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.78, 0.22, 1.0);
// Overall brightness at strength 1.
uniform float intensity = 0.22;
// How the brightness falls off along the beam (higher = shorter-looking beam).
uniform float falloff = 1.6;
// Length of the cone mesh (its height), to know where along it a pixel is.
uniform float length = 3.5;
// World meters over which the beam fades out where it touches surfaces.
uniform float soft_distance = 1.5;
uniform sampler2D depth_texture : hint_depth_texture, filter_linear;
instance uniform float strength = 1.0;

varying float along;   // 0 at the eye, 1 at the far end

void vertex() {
	along = clamp(0.5 - VERTEX.y / length, 0.0, 1.0);
}

void fragment() {
	// Edges of the cone fade out (like looking through more or less fog).
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float edge = facing * facing;
	float fade = pow(1.0 - along, falloff);
	// Soft where the beam passes into geometry.
	float depth = textureLod(depth_texture, SCREEN_UV, 0.0).r;
	vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	float scene_z = -view.z / view.w;
	float soft = clamp((scene_z + VERTEX.z) / soft_distance, 0.0, 1.0);
	ALBEDO = color.rgb;
	ALPHA = clamp(intensity * strength * edge * fade * soft, 0.0, 1.0);
}
