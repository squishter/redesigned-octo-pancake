// The board's light, shared by the gem, sparkle, paper and shadow shaders.
// GemBoard3D moves the lights over time and with the phone's orientation
// and sets these every frame. Directions point toward the light, in board
// space (y up toward the viewer, x right, z down the picture). Everything
// here depends on where the lights are, never on the time itself, so light
// that holds still makes still caustics.
uniform vec3 key_dir = vec3(-0.45, 0.62, -0.64);
uniform vec3 fill_dir = vec3(0.7, 0.5, 0.5);
uniform float light_strength = 1.0;
uniform vec3 paper_color = vec3(0.86, 0.84, 0.8);

// What a facet sees in direction d (unit): a dark room with faint bands
// around its walls, a key softbox (crossed by window bars), a weaker fill, a
// ring of small lamps low around it (so facets catch light from many
// sides), a soft overhead, and the white paper below.
vec3 studio(vec3 d) {
	vec3 c;
	if (d.y < 0.0) {
		c = paper_color * (0.2 + 0.4 * clamp(key_dir.y, 0.0, 1.0));
	} else {
		c = vec3(0.012, 0.012, 0.018) + vec3(0.22) * smoothstep(0.9, 1.0, d.y);
		// Faint bands around the walls, so facets at different slopes
		// (a step cut's steps) see different light.
		c += vec3(0.16) * smoothstep(0.2, 0.9, sin(asin(d.y) * 9.0)) * light_strength;
		// The lamp ring: six small lamps, turning with the key.
		float az = atan(d.z, d.x) - atan(key_dir.z, key_dir.x);
		float lamp = smoothstep(0.82, 0.97, cos(az * 3.0)) * smoothstep(0.08, 0.2, d.y) * smoothstep(0.75, 0.45, d.y);
		c += vec3(1.1, 1.05, 1.0) * lamp * light_strength;
	}
	float k = dot(d, key_dir);
	c += vec3(1.0, 0.97, 0.92) * light_strength * (9.0 * smoothstep(0.988, 0.996, k) + 1.4 * smoothstep(0.86, 0.985, k));
	// Window bars across the key.
	vec3 across = normalize(cross(key_dir, vec3(0.0, 1.0, 0.0)) + vec3(1e-4));
	float bars = smoothstep(0.06, 0.0, abs(fract(dot(d, across) * 3.0) - 0.5) - 0.38);
	c += vec3(1.2) * light_strength * bars * smoothstep(0.7, 0.93, k);
	float f = dot(d, fill_dir);
	c += vec3(0.85, 0.92, 1.0) * light_strength * (4.0 * smoothstep(0.986, 0.995, f) + 0.5 * smoothstep(0.85, 0.98, f));
	return c;
}

// How far the key light has moved the caustics: their offset and their
// phase (smooth in the light's direction, so they shift as it moves).
vec2 light_shift_of(vec3 k) {
	return k.xz / max(k.y, 0.3);
}

float light_phase_of(vec3 k) {
	return k.x * 2.1 + k.z * 1.7 + k.y * 2.6;
}

vec2 light_shift() {
	return light_shift_of(key_dir);
}

float light_phase() {
	return light_phase_of(key_dir);
}

// Stones sit a little tilted on the glue (GemBoard3D gives each one up to
// TILT_MAX_DEG in a random direction); `tilt` is the xz of its top's normal
// in board space. Direction d (toward a light, or the viewer) as that stone
// sees it: turned by the rotation that stands its normal upright.
vec3 as_tilted(vec3 d, vec2 tilt) {
	vec3 n = vec3(tilt.x, sqrt(max(1.0 - dot(tilt, tilt), 0.0)), tilt.y);
	vec3 axis = vec3(-n.z, 0.0, n.x);  // cross(n, up)
	float s = length(axis);
	if (s < 1e-5) {
		return d;
	}
	axis /= s;
	float c = n.y;
	return d * c + cross(axis, d) * s + axis * dot(axis, d) * (1.0 - c);
}

// Caustic light (bright webs) for phase t, about 0..1.
float caustic(vec2 p, float t) {
	vec2 q = mod(p * 6.2831853, 6.2831853) - 250.0;
	vec2 i = q;
	float c = 1.0;
	for (int n = 0; n < 4; n++) {
		float tt = t * (1.0 - 3.5 / float(n + 1));
		i = q + vec2(cos(tt - i.x) + sin(tt + i.y), sin(tt - i.y) + cos(tt + i.x));
		c += 1.0 / length(vec2(q.x / (sin(i.x + tt) / 0.005), q.y / (cos(i.y + tt) / 0.005)));
	}
	c /= 4.0;
	c = 1.17 - pow(c, 1.4);
	return clamp(pow(abs(c), 8.0), 0.0, 1.5);
}

// Soft light through a stone for phase t: broad bright patches, 0..1.
float glow_drift(vec2 p, float t) {
	float a = sin(p.x * 2.1 + p.y * 1.3 + t * 0.9);
	float b = sin(p.x * -1.4 + p.y * 2.4 - t * 0.7 + 1.7);
	float c = sin(p.x * 0.8 - p.y * 1.9 + t * 0.5 + 4.1);
	return pow(clamp((a + b + c) / 3.0 * 0.5 + 0.5, 0.0, 1.0), 3.0);
}
