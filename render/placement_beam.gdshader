// Feathered Soft column treatment: one quad instead of overlapping tapers.
shader_type canvas_item;
render_mode unshaded;

uniform vec4 beam_color : source_color = vec4(1.0);
uniform float energy : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	float half_width = mix(0.5, 0.21, UV.y);
	float distance_from_core = clamp(abs(UV.x - 0.5) / half_width, 0.0, 1.0);
	// Continuous counterpart of the study's 18 translucent nested tapers.
	float layer_alpha = mix(0.025, 0.055, UV.y) * energy;
	float alpha = 1.0 - pow(1.0 - layer_alpha, 18.0 * (1.0 - distance_from_core));
	vec3 tint = mix(beam_color.rgb, mix(beam_color.rgb, vec3(1.0), 0.2), UV.y);
	COLOR *= vec4(tint, alpha * beam_color.a);
}
