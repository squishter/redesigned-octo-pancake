// The paper's faint grain (paper.gdshader samples it), baked once per board
// by GemBoard3D into a texture covering the board: three octaves of value
// noise, in board units, so the grain sits still on the paper. It never
// changes, so there's no need to work it out every frame.
shader_type canvas_item;
render_mode unshaded, blend_disabled;

uniform vec2 board_px = vec2(768.0, 768.0);

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = fract(sin(dot(i, vec2(127.1, 311.7))) * 43758.5453);
	float b = fract(sin(dot(i + vec2(1.0, 0.0), vec2(127.1, 311.7))) * 43758.5453);
	float c = fract(sin(dot(i + vec2(0.0, 1.0), vec2(127.1, 311.7))) * 43758.5453);
	float d = fract(sin(dot(i + vec2(1.0, 1.0), vec2(127.1, 311.7))) * 43758.5453);
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void fragment() {
	vec2 px = UV * board_px;
	float grain = noise(px * 1.3) * 0.45 + noise(px * 0.31) * 0.35 + noise(px * 0.07) * 0.2;
	COLOR = vec4(vec3(grain), 1.0);
}
