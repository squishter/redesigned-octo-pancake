// The board's white paper, with a faint grain (baked once per board from
// paper_grain.gdshader into "grain_tex"), lit by the key light. Lines
// the picture keeps as a metal setting (the "lines_tex" mask) are gold
// ridges that shine where their slope faces a light.
//
// On a board being played the lines are painted instead (line_paint on;
// see LinePaint and GemBoard3D.show_line_paint): "line_color_tex" holds
// each line pixel's paint color (alpha: its paint's number + 1, over 255)
// and "line_time_tex" when it gets painted (on paint_clock; far ahead while
// it's still empty). Empty lines are a faint outline, the picked paint's
// tinted; painted ones take line_finish's look, and a bright front runs
// along a line as it fills.
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
uniform bool line_paint = false;
uniform sampler2D line_color_tex : source_color, hint_default_black, filter_nearest;
uniform sampler2D line_time_tex : hint_default_black, filter_nearest;
uniform float paint_clock = 0.0;
uniform float selected_paint = -1.0;
// LINE_FINISHES in GemBoard3D: 0 metal, 1 matte, 2 glossy, 3 glitter,
// 4 pearl, 5 glow, 6 enamel, 7 holographic.
uniform int line_finish = 0;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// A painted line pixel of color `c` (linear) in the chosen finish: `n` its
// ridge's normal, `r` the view reflected off it, `m` the line mask (soft at
// the edges), `px` where it is (board units).
vec3 finish(vec3 c, vec3 n, vec3 r, float m, vec2 px, float lit) {
	float key = max(dot(r, key_dir), 0.0);
	float fill = max(dot(r, fill_dir), 0.0);
	float shade = 0.3 + 0.55 * n.y;
	if (line_finish == 1) {
		// Matte: flat paint, gently embossed, no shine.
		return c * (0.72 + 0.28 * n.y) * lit;
	}
	if (line_finish == 2) {
		// Glossy: wet paint with a crisp white highlight.
		float spec = pow(key, 48.0) + 0.4 * pow(fill, 48.0);
		return c * (0.82 + 0.18 * n.y) * lit + vec3(spec * 1.3 * light_strength);
	}
	if (line_finish == 3) {
		// Glitter: metal paint with flecks that wink as the light moves.
		vec2 cell = floor(px * 0.9);
		vec3 fn = normalize(vec3(hash12(cell) - 0.5, 0.35, hash12(cell + 17.0) - 0.5));
		vec3 fr = reflect(vec3(0.0, -1.0, 0.0), fn);
		float fleck = pow(max(dot(fr, key_dir), 0.0), 40.0) + 0.6 * pow(max(dot(fr, fill_dir), 0.0), 40.0);
		float sheen = pow(key, 14.0) + 0.5 * pow(fill, 14.0);
		return c * (0.45 + 0.5 * n.y) + mix(vec3(1.0), c, 0.35) * (sheen * 0.6 + fleck * 2.2) * light_strength;
	}
	if (line_finish == 4) {
		// Pearl: soft, pale and shifting through pastel tints with the light.
		float a = dot(r, key_dir) * 5.0 + px.x * 0.004 + px.y * 0.003;
		vec3 tint = 0.5 + 0.5 * cos(a + vec3(0.0, 2.1, 4.2));
		vec3 pale = mix(c, vec3(1.0), 0.45) * (0.78 + 0.22 * n.y);
		return mix(pale, pale * (0.8 + 0.4 * tint), 0.55) + vec3(pow(key, 6.0) * 0.35 * light_strength);
	}
	if (line_finish == 5) {
		// Glow: a lit tube, white-hot down the middle of the line.
		float core = smoothstep(0.7, 1.0, m);
		vec3 hot = c * 1.6 + 0.04;
		return mix(hot, mix(hot, vec3(1.0), 0.35), core * 0.6);
	}
	if (line_finish == 6) {
		// Enamel: glassy color, deeper at its rims, with a small bright glint.
		float rim = smoothstep(0.2, 0.95, m);
		float spec = pow(key, 30.0);
		return c * (0.55 + 0.45 * rim) * (0.85 + 0.15 * n.y) * lit + vec3(spec * 0.8 * light_strength);
	}
	if (line_finish == 7) {
		// Holographic: rainbow bands sliding over the paint as the light moves.
		float a = (px.x + px.y) * 0.03 + dot(r, key_dir) * 6.0 + dot(r, fill_dir) * 3.0;
		vec3 rainbow = 0.5 + 0.5 * cos(a + vec3(0.0, 2.1, 4.2));
		float sheen = pow(key, 10.0) + 0.5 * pow(fill, 10.0);
		return mix(c, rainbow, 0.5) * (0.55 + 0.45 * n.y) + vec3(sheen * 0.5 * light_strength);
	}
	// Metal: the gold setting's ridges, in the paint's color.
	float sheen = pow(key, 14.0) + 0.5 * pow(fill, 14.0);
	return c * shade + mix(vec3(1.0, 0.92, 0.8), c, 0.4) * sheen * light_strength;
}

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
		if (!line_paint) {
			vec3 gold = pow(metal, vec3(2.2)) * (0.3 + 0.55 * n.y) + vec3(1.0, 0.86, 0.6) * sheen * light_strength;
			col = mix(col, gold, m);
		} else {
			vec4 paint = texture(line_color_tex, UV);
			float since = paint_clock - texture(line_time_tex, UV).r;
			float painted = clamp(since / 0.12, 0.0, 1.0);
			bool picked = abs(paint.a * 255.0 - 1.0 - selected_paint) < 0.5;
			// Empty: a faint gray outline, or the picked paint's tint.
			vec3 empty = picked ? mix(col, paint.rgb * lit, 0.5) : mix(col, vec3(0.42, 0.45, 0.52) * lit, 0.45);
			vec3 full = finish(paint.rgb, n, r, m, UV * board_px, lit);
			// The bright front running along a line as it fills.
			float front = since > 0.0 ? exp(-since * 7.0) : 0.0;
			vec3 line = mix(empty, full, painted) + mix(vec3(1.0, 0.95, 0.8), paint.rgb, 0.3) * front * 1.4;
			col = mix(col, line, m);
		}
	}
	ALBEDO = col;
}
