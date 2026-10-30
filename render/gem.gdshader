// Faceted gems seen from above (see GemBoard3D). Every facet is flat, so it
// mirrors one patch of a small studio (see gem_light.gdshaderinc). Light
// also refracts into the stone, bounces off two pavilion facets (the cone
// under the crown, which the mesh doesn't model: the facet under each point
// is picked from where it is, like a kaleidoscope: sectors around a
// brilliant, nested rectangles in a step cut) and comes back out tinted by
// the gem's color, a little apart per color channel for fire. Soft light
// plays through the body as the light moves, and the rim falls dark like a
// real stone's.
// Glints are brighter than white and bloom through the board's glow.
shader_type spatial;
render_mode unshaded, cull_disabled;

#include "res://render/gem_light.gdshaderinc"

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

float hash12(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// The pavilion facet under local point p: its outward direction (xz) and a
// random number for it.
vec3 pavilion(vec2 p, vec3 n, float cut, float seed) {
	if (abs(cut - 1.0) < 0.5) {
		// Step cut: steps parallel to the nearest side, nested inward.
		vec2 q = abs(p);
		vec2 side = q.x > q.y ? vec2(sign(p.x), 0.0) : vec2(0.0, sign(p.y));
		float tier = floor(max(q.x, q.y) * 3.5);
		return vec3(side, hash12(vec2(tier + seed * 13.0, side.x * 3.0 + side.y)));
	}
	// Brilliants and the rest: 16 sectors around, turned by the crown facet
	// above so neighboring facets show different ones.
	float turn = atan(n.z, n.x) * 0.15 * step(0.05, length(n.xz));
	float a = atan(p.y, p.x) + turn;
	float sector = floor(a / (TAU / 16.0) + 0.5);
	float ang = sector * (TAU / 16.0);
	return vec3(cos(ang), sin(ang), hash12(vec2(sector + seed * 31.0, 0.37)));
}

// Where light seen through the crown comes from: in through facet n, off
// the pavilion facet below and the one across from it, and back out the top.
vec3 through(vec3 n, vec3 pav, float ior) {
	vec3 v = vec3(0.0, 1.0, 0.0);
	vec3 t = refract(-v, n, 1.0 / ior);
	vec3 side = vec3(pav.x, 0.0, pav.y);
	float jitter = pav.z - 0.5;
	float slope = radians(40.0 + 12.0 * jitter);
	vec3 np = normalize(side * sin(slope) - vec3(0.0, cos(slope), 0.0));
	vec3 t2 = reflect(t, np);
	float slope2 = radians(42.0 - 10.0 * jitter);
	vec3 np2 = normalize(-side * sin(slope2) - vec3(0.0, cos(slope2), 0.0));
	vec3 t3 = reflect(t2, np2);
	if (t3.y <= 0.0) {
		return t3;  // leaks out the bottom: the paper shows through
	}
	vec3 e = refract(t3, vec3(0.0, -1.0, 0.0), ior);
	return dot(e, e) > 0.0 ? e : reflect(t3, vec3(0.0, -1.0, 0.0));
}

void fragment() {
	vec3 n = normalize(w_normal);
	if (n.y < 0.0) {
		n = -n;
	}
	// The light ripple: as its ring passes, the light swings once round the
	// stone (its glints race over the facets) and burns brighter.
	float burn = 1.0;
	if (shine.x > 0.0) {
		float a = shine.y * TAU;
		n.xz = vec2(n.x * cos(a) - n.z * sin(a), n.x * sin(a) + n.z * cos(a));
		burn = 1.0 + 1.2 * shine.x;
	}
	vec3 v = vec3(0.0, 1.0, 0.0);
	vec3 tint = pow(COLOR.rgb, vec3(2.2));
	float ior = stone.y;
	float disp = stone.z;
	float cut = stone.w;
	float f0 = pow((ior - 1.0) / (ior + 1.0), 2.0);
	float fres = f0 + (1.0 - f0) * pow(1.0 - max(n.y, 0.0), 5.0);
	vec3 refl = studio(reflect(-v, n)) * 1.4;

	vec2 p = l_pos.xz;
	float rim = 1.0 - smoothstep(0.62, 1.02, length(p));
	vec3 inside;
	if (cut > 3.5) {
		// Cabochon: no facets inside; a soft glow that follows the light.
		vec2 toward = -key_dir.xz * 0.45;
		float glow = 1.0 - smoothstep(0.0, 0.9, length(p - toward));
		inside = tint * (0.2 + 0.9 * glow) * light_strength;
	} else {
		vec3 pav = pavilion(p, n, cut, stone.x);
		vec3 body;
		body.r = studio(through(n, pav, ior - disp)).r;
		body.g = studio(through(n, pav, ior)).g;
		body.b = studio(through(n, pav, ior + disp)).b;
		// Colored stones soak up light on the way through, deepest in the middle.
		float depth = 1.0 + 0.7 * rim;
		vec3 absorb = pow(max(tint, vec3(0.001)), vec3(depth));
		inside = absorb * (0.18 + body);
	}
	// Light playing on the underside, moving as the light moves.
	float drift = glow_drift(p * 1.3 + stone.x * 9.0 + light_shift() * 0.5, light_phase() * 1.4 + stone.x * 5.0);
	inside += tint * drift * 0.3 * light_strength;
	inside *= 0.45 + 0.55 * rim;
	if (COLOR.a < 0.5) {
		// Opaque stones (white): no light through them, just a soft glaze lit
		// by the key and fill, with a faint pearly sheen that drifts with the light.
		float lit = clamp(dot(n, key_dir), 0.0, 1.0);
		float fl = clamp(dot(n, fill_dir), 0.0, 1.0);
		float sheen = glow_drift(p * 1.1 + stone.x * 7.0 + light_shift() * 0.4, light_phase() + stone.x * 3.0);
		inside = tint * (0.3 + 0.5 * lit + 0.2 * fl) * light_strength;
		inside += vec3(0.05, 0.04, 0.07) * sheen * light_strength;
		inside *= 0.75 + 0.25 * rim;
	}

	ALBEDO = (refl * fres + inside * (1.0 - fres)) * burn;
}
