// Tiny stones (a few px across on screen) as a flat outline each
// (GemMesh.get_outline_mesh, a few triangles) instead of their faceted
// mesh: the facets come from a picture of the stone seen from above
// (GemMesh.get_facets, gathered into one texture per board), and
// gem_color() lights them just as gem.gdshader lights the mesh, at four
// points in each pixel, so a tiny stone's pixels mix its facets as 4x MSAA
// mixes the mesh's. The outline's own edges are anti-aliased like any mesh.
shader_type spatial;
render_mode unshaded, cull_disabled;

#include "res://render/gem_light.gdshaderinc"
#include "res://render/gem_body.gdshaderinc"

// The board's facet pictures, and where this layer's shape and cut sits in
// them: the UV of its -1..1 square's corner and its size.
uniform sampler2D facets : filter_linear, repeat_disable;
instance uniform vec4 facet_tile = vec4(0.0, 0.0, 1.0, 1.0);

// As in gem.gdshader; and the stone's transform for normals.
varying vec3 l_pos;
varying vec4 stone;
varying vec2 shine;
varying mat3 normal_matrix;

void vertex() {
	l_pos = VERTEX;
	normal_matrix = MODEL_NORMAL_MATRIX;
	float cut = floor(INSTANCE_CUSTOM.w + 0.01);
	stone = vec4(INSTANCE_CUSTOM.xyz, cut);
	float delay = (INSTANCE_CUSTOM.w - cut) * 2.0;
	shine = vec2(wave_pulse(delay) * wave_light, wave_phase(delay));
	float f = wave_scale(delay);
	if (f != 1.0) {
		VERTEX = scaled_about_paper(VERTEX, f, MODEL_MATRIX);
	}
}

// The stone at atlas point `at` (facet_tile applied): its color there,
// times whether it covers that point (the outline is a little rough).
vec4 shade(vec2 at, vec2 p, vec4 color) {
	vec4 facet = textureLod(facets, at, 0.0);
	vec3 n = vec3(facet.r * 2.0 - 1.0, 0.0, facet.g * 2.0 - 1.0);
	n.y = sqrt(max(1.0 - dot(n.xz, n.xz), 0.0));
	return vec4(gem_color(normalize(normal_matrix * n), p, stone, color, shine), 1.0) * facet.b;
}

void fragment() {
	// Four points in the pixel (a rotated grid), shaded and covered each, as
	// 4x MSAA would sample the stone's facets: a tiny stone's pixel blends
	// several of them, bright glints with dark ones.
	vec2 uv = l_pos.xz * 0.5 + 0.5;
	vec2 at = facet_tile.xy + uv * facet_tile.zw;
	vec2 dx = dFdx(at);
	vec2 dy = dFdy(at);
	vec2 px = dFdx(l_pos.xz);
	vec2 py = dFdy(l_pos.xz);
	vec4 sum = vec4(0.0);
	for (int k = 0; k < 4; k++) {
		vec2 o = k == 0 ? vec2(-0.125, -0.375) : k == 1 ? vec2(0.375, -0.125) : k == 2 ? vec2(0.125, 0.375)
				: vec2(-0.375, 0.125);
		sum += shade(at + o.x * dx + o.y * dy, l_pos.xz + o.x * px + o.y * py, COLOR);
	}
	ALBEDO = sum.rgb / max(sum.a, 1e-4);
}
