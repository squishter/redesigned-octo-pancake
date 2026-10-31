// The board's white paper, with a faint grain (baked once per board from
// paper_grain.gdshader into "grain_tex"), lit by the key light. Lines
// the picture keeps as a metal setting (the "lines_tex" mask) are gold
// ridges that shine where their slope faces a light.
shader_type spatial;
render_mode unshaded;

#include "res://render/gem_light.gdshaderinc"

uniform sampler2D lines_tex : hint_default_black, filter_linear;
uniform sampler2D grain_tex : hint_default_black, filter_linear, repeat_disable;
uniform vec2 board_px = vec2(768.0, 768.0);
uniform vec3 metal = vec3(0.83, 0.66, 0.32);
// The light finale's pattern (GemBoard3D.WAVE_KINDS): 0 ripple, 1 spiral,
// 2 sweep, 3 shimmer.
uniform int wave_kind = 0;

// Where on the paper (board units) a light wave is, as a delay 0..1: as
// GemBoard3D._finale_wave times the stones, so the paper lights up with
// them. -1: the paper stays as it is (a shimmer has no front to follow).
float wave_delay(vec2 p) {
	if (wave_kind == 1) {
		vec2 d = p - wave_from;
		float turn = mod(atan(d.y, d.x) + PI / 2.0, TAU) / TAU;
		return (turn + length(d) / length(board_px) * 0.3) / wave_far;
	}
	if (wave_kind == 2) {
		return p.x / max(board_px.x, 1.0) / wave_far;
	}
	if (wave_kind == 3) {
		return -1.0;
	}
	return length(p - wave_from) / wave_far;
}

void fragment() {
	float grain = texture(grain_tex, UV).r;
	float lit = 0.8 + 0.2 * clamp(key_dir.y, 0.0, 1.0);
	vec3 col = paper_color * lit * (0.95 + 0.07 * grain);
	if (wave_light > 0.0) {
		// The light wave crossing the paper.
		float delay = wave_delay(UV * board_px);
		if (delay >= 0.0) {
			col *= 1.0 + 0.12 * wave_pulse(delay);
		}
	}
	float m = texture(lines_tex, UV).r;
	if (m > 0.01) {
		vec2 texel = 1.0 / board_px;
		float gx = texture(lines_tex, UV + vec2(texel.x, 0.0)).r - texture(lines_tex, UV - vec2(texel.x, 0.0)).r;
		float gz = texture(lines_tex, UV + vec2(0.0, texel.y)).r - texture(lines_tex, UV - vec2(0.0, texel.y)).r;
		vec3 n = normalize(vec3(-gx * 1.6, 1.0, -gz * 1.6));
		vec3 r = reflect(vec3(0.0, -1.0, 0.0), n);
		float sheen = pow(max(dot(r, key_dir), 0.0), 14.0) + 0.5 * pow(max(dot(r, fill_dir), 0.0), 14.0);
		vec3 gold = pow(metal, vec3(2.2)) * (0.3 + 0.55 * n.y) + vec3(1.0, 0.86, 0.6) * sheen * light_strength;
		col = mix(col, gold, m);
	}
	ALBEDO = col;
}
