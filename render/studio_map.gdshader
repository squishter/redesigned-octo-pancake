// The studio (studio() in gem_light.gdshaderinc) as a picture: every
// direction, octahedrally mapped (oct_decode), rendered by GemBoard3D
// whenever the lights move, so gem.gdshader looks a direction up instead of
// working the studio out four times for every pixel of every stone. HDR:
// highlights go well above 1.
shader_type canvas_item;
render_mode unshaded, blend_disabled;

#include "res://render/gem_light.gdshaderinc"

void fragment() {
	COLOR = vec4(studio(oct_decode(UV * 2.0 - 1.0)), 1.0);
}
