// A gem drawn from its own faceted mesh (GemMesh); its look is in
// gem_body.gdshaderinc.
shader_type spatial;
render_mode unshaded, cull_disabled;

#include "res://render/gem_light.gdshaderinc"
#include "res://render/gem_body.gdshaderinc"

// Per stone (INSTANCE_CUSTOM): x random 0..1, y refractive index,
// z dispersion, w cut (its style, GemCuts.SHADER_STYLE) plus half its
// finale delay (see wave_scale). COLOR is the gem color; its alpha is 0 for
// opaque stones.
varying vec3 w_normal;
varying vec3 l_pos;
varying vec4 stone;
// The light ripple passing: how strongly (0..1), and how far through.
varying vec2 shine;

void vertex() {
	w_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	l_pos = VERTEX;
	float cut = floor(INSTANCE_CUSTOM.w + 0.01);
	stone = vec4(INSTANCE_CUSTOM.xyz, cut);
	float delay = (INSTANCE_CUSTOM.w - cut) * 2.0;
	shine = vec2(wave_pulse(delay) * wave_light, wave_phase(delay));
	float f = wave_scale(delay);
	if (f != 1.0) {
		VERTEX = scaled_about_paper(VERTEX, f, MODEL_MATRIX);
	}
}

void fragment() {
	ALBEDO = gem_color(normalize(w_normal), l_pos.xz, stone, COLOR, shine, true);
}
