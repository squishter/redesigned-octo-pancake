// Star sparkles: when one of a stone's two brightest facets turns the key
// (or fill) light straight up at the viewer, a four-point star flares over
// it. Each stone has its own facets (from its random number), so as the
// light moves the stars come and go across the board. Planes for dark
// stones collapse to nothing, so only the few flaring ones cost anything.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, depth_test_disabled, cull_disabled;

#include "res://render/gem_light.gdshaderinc"

// Per stone (INSTANCE_CUSTOM): x random 0..1, yz the xz of its tilted top's
// normal (see as_tilted), w its finale delay (see wave_scale). COLOR is the
// gem color.
varying float glint;
varying vec2 lp;

// Facet k's flare, with the lights and viewer as the tilted stone sees them.
float flare(float r, float k, vec3 key, vec3 fill, vec3 eye) {
	float turn = r * 6.2831853 + k * 2.4;
	float tilt = radians(14.0 + 28.0 * fract(r * 7.13 + k * 0.37));
	vec3 n = vec3(cos(turn) * sin(tilt), cos(tilt), sin(turn) * sin(tilt));
	vec3 up = reflect(-eye, n);
	return pow(max(dot(up, key), 0.0), 700.0) + 0.6 * pow(max(dot(up, fill), 0.0), 700.0);
}

void vertex() {
	float r = INSTANCE_CUSTOM.x;
	vec2 tilt = INSTANCE_CUSTOM.yz;
	vec3 key = as_tilted(key_dir, tilt);
	vec3 fill = as_tilted(fill_dir, tilt);
	vec3 eye = as_tilted(vec3(0.0, 1.0, 0.0), tilt);
	glint = max(flare(r, 0.0, key, fill, eye), flare(r, 1.0, key, fill, eye)) * light_strength;
	lp = VERTEX.xz;
	// On a facet, not dead center.
	VERTEX.xz += vec2(cos(r * 91.0), sin(r * 91.0)) * 0.22;
	float f = wave_scale(INSTANCE_CUSTOM.w);
	if (f != 1.0) {
		VERTEX = scaled_about_paper(VERTEX, f, MODEL_MATRIX);
	}
	if (glint < 0.03) {
		VERTEX = vec3(0.0);
	}
}

void fragment() {
	vec2 p = lp;
	float rays = exp(-abs(p.y) * 28.0) * exp(-abs(p.x) * 2.2) + exp(-abs(p.x) * 28.0) * exp(-abs(p.y) * 2.2);
	vec2 q = vec2(p.x + p.y, p.x - p.y) * 0.7071;
	rays += 0.4 * (exp(-abs(q.y) * 36.0) * exp(-abs(q.x) * 4.0) + exp(-abs(q.x) * 36.0) * exp(-abs(q.y) * 4.0));
	float core = exp(-dot(p, p) * 22.0);
	vec3 tint = mix(vec3(1.0), pow(COLOR.rgb, vec3(2.2)), 0.25);
	ALBEDO = tint * min(glint, 1.5) * (rays * 1.6 + core * 2.2);
}
