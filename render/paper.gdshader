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

void fragment() {
	float grain = texture(grain_tex, UV).r;
	float lit = 0.8 + 0.2 * clamp(key_dir.y, 0.0, 1.0);
	vec3 col = paper_color * lit * (0.95 + 0.07 * grain);
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
