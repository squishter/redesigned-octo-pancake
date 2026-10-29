// Under each stone, on the paper: its soft shadow, cast away from the key
// light by how high the stone stands, and inside it the colored light the
// stone focuses (caustics), shifting as the light moves. Drawn on a plane
// SPAN stone half-sizes across (the board scales each plane to its stone's
// half-length and half-width), so local units are the stone's own. With
// shadow_strength 0 only the light is left.
shader_type spatial;
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled;

#include "res://render/gem_light.gdshaderinc"

uniform float shadow_strength = 1.0;
// Half the plane's width, in stone half-sizes: everything fades out before
// its edge, so no shadow is ever cut square.
uniform float span = 2.2;

// Per stone (INSTANCE_CUSTOM): x random 0..1, y height of its top above the
// paper (board units). COLOR is the gem color.
varying vec2 off;
varying vec2 lp;
varying vec4 stone;

void vertex() {
	stone = INSTANCE_CUSTOM;
	lp = VERTEX.xz;
	vec3 lean = -vec3(key_dir.x, 0.0, key_dir.z) / max(key_dir.y, 0.25) * stone.y;
	off = (inverse(mat3(MODEL_MATRIX)) * lean).xz;
}

void fragment() {
	float d = length(lp - off * 0.8);
	float shade = (1.0 - smoothstep(0.6, 1.3, d)) * 0.42 * clamp(light_strength, 0.0, 1.0) * shadow_strength;
	// The light the stone gathers lands in the far half of its shadow.
	float focus = 1.0 - smoothstep(0.05, 0.85, length(lp - off * 1.25));
	float edge = 1.0 - smoothstep(span * 0.7, span * 0.97, max(abs(lp.x), abs(lp.y)));
	shade *= edge;
	focus *= edge;
	if (shade < 0.004 && focus <= 0.0) {
		discard;
	}
	vec3 light = vec3(0.0);
	if (focus > 0.0) {
		float web = caustic(lp * 0.42 + stone.x * 7.0 + light_shift() * 0.25, light_phase() + stone.x * 9.0);
		light = pow(COLOR.rgb, vec3(2.2)) * paper_color * focus * (0.18 + 0.9 * web) * light_strength;
	}
	ALBEDO = light;
	ALPHA = shade;
}
