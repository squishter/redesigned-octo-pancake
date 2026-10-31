shader_type canvas_item;
render_mode unshaded;

uniform sampler2D menu_texture : source_color, filter_linear;
uniform vec2 grid = vec2(7.0, 16.0);
uniform float progress : hint_range(0.0, 1.0) = 0.0;

float seed(vec2 cell) {
	return fract(sin(dot(cell, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 cell = floor(UV * grid);
	vec2 local = fract(UV * grid) - 0.5;
	float random = seed(cell);
	// Place each row left to right, then move down; keep timing free of random jitter.
	float wave = (cell.y * grid.x + cell.x) / max(grid.x * grid.y - 1.0, 1.0);
	float placed = clamp((progress - wave * 0.70) / 0.22, 0.0, 1.0);
	float ease = 1.0 - pow(1.0 - placed, 3.0);
	float scale = mix(0.18, 1.0, ease);
	float angle = (random - 0.5) * 0.48 * (1.0 - ease);
	vec2 at = (local - vec2(0.16, -0.32) * (1.0 - ease)) / scale;
	at = mat2(vec2(cos(angle), sin(angle)), vec2(-sin(angle), cos(angle))) * at;
	float edge = max(abs(at.x), abs(at.y));
	float settle = smoothstep(0.86, 1.0, progress);
	float cut = mix(0.82, 1.01, settle);
	float inside = step(edge, 0.5) * step(abs(at.x) + abs(at.y), cut);
	float alpha = inside * smoothstep(0.0, 0.06, placed);
	vec2 sample_uv = clamp((cell + at + 0.5) / grid, vec2(0.0), vec2(1.0));
	vec3 image = texture(menu_texture, sample_uv).rgb;
	// Cut facets catch the light as each tile lands, then clear to the seamless menu.
	float bevel = smoothstep(0.36, 0.49, edge);
	float light = (at.x + at.y < 0.0 ? 0.27 : -0.22) * bevel;
	float flash = sin(placed * 3.14159265) * 0.12;
	image += (vec3(light) + vec3(0.8, 0.93, 1.0) * flash) * (1.0 - settle);
	COLOR = vec4(image, alpha);
}
