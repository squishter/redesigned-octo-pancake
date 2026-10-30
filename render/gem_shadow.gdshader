// Under each stone, on the paper: its soft shadow, cast away from the key
// light by how high the stone stands, and inside it the colored light the
// stone focuses (caustics), shifting as the light moves. Drawn on a plane
// GemBoard3D.SHADOW_SPAN stone half-sizes each way (the board scales each
// plane to its stone's half-length and half-width), so local units are the
// stone's own; the plane moves toward where the shade and light fall, just
// far enough that it always holds them. With shadow_strength 0 only the
// light is left.
shader_type spatial;
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled;

#include "res://render/gem_light.gdshaderinc"

uniform float shadow_strength = 1.0;
// How far from the stone everything has faded out, in stone half-sizes
// (GemBoard3D.SHADOW_FADE), so no shadow is ever cut square.
uniform float span = 2.6;

// Per stone (INSTANCE_CUSTOM): x random 0..1, y height of its top above the
// paper (board units), zw the xz of its tilted top's normal (see as_tilted).
// COLOR is the gem color, its alpha the stone's finale delay (see
// wave_scale). The shadow falls from the true light; the light the stone
// focuses goes where its tilt sends it.
varying vec2 off;
varying vec2 focus_off;
varying vec3 key_tilted;
varying vec2 lp;
varying vec4 stone;

void vertex() {
	stone = INSTANCE_CUSTOM;
	// A finale's pulse scales the stone, but not how far its shadow falls.
	float f = wave_scale(COLOR.a);
	mat3 to_local = inverse(mat3(MODEL_MATRIX)) / f;
	vec3 lean = -vec3(key_dir.x, 0.0, key_dir.z) / max(key_dir.y, 0.25) * stone.y;
	off = (to_local * lean).xz;
	key_tilted = as_tilted(key_dir, stone.zw);
	vec3 bend = -vec3(key_tilted.x, 0.0, key_tilted.z) / max(key_tilted.y, 0.25) * stone.y;
	focus_off = (to_local * bend).xz;
	// Centered here, a plane SHADOW_SPAN each way holds the shade and the
	// focused light for any light and tilt; lp stays relative to the stone.
	VERTEX.xz += off * 1.15;
	lp = VERTEX.xz;
	if (f != 1.0) {
		VERTEX = scaled_about_paper(VERTEX, f, MODEL_MATRIX);
	}
}

void fragment() {
	float d = length(lp - off * 0.8);
	// Lighter under the tiniest stones, which barely stand off the paper.
	float small = mix(0.6, 1.0, smoothstep(1.5, 4.5, stone.y));
	float shade = (1.0 - smoothstep(0.6, 1.3, d)) * 0.36 * small * clamp(light_strength, 0.0, 1.0) * shadow_strength;
	// The light the stone gathers lands in the far half of its shadow.
	float focus = 1.0 - smoothstep(0.05, 0.85, length(lp - focus_off * 1.25));
	float edge = 1.0 - smoothstep(span * 0.7, span * 0.97, max(abs(lp.x), abs(lp.y)));
	shade *= edge;
	focus *= edge;
	if (shade < 0.004 && focus <= 0.0) {
		discard;
	}
	vec3 light = vec3(0.0);
	if (focus > 0.0) {
		float web = caustic(lp * 0.42 + stone.x * 7.0 + light_shift_of(key_tilted) * 0.25,
				light_phase_of(key_tilted) + stone.x * 9.0);
		light = pow(COLOR.rgb, vec3(2.2)) * paper_color * focus * (0.18 + 0.9 * web) * light_strength;
	}
	ALBEDO = light;
	ALPHA = shade;
}
