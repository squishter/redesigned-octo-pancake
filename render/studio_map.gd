class_name StudioMap
extends SubViewport
## The studio map (studio_map.gdshader): what a facet sees in every
## direction, rendered for a board's gems to look up, again only when the
## board's lights have moved (follow). Kept inside the board's own viewport,
## it renders before the board does.

## Its size (px a side): sharp enough for the key light's brightest edge
## and the window bars at the board's closest zoom.
const PX := 512
const SHADER := preload("res://render/studio_map.gdshader")

## Its material, which takes the board's lights (key_dir, fill_dir).
var material := ShaderMaterial.new()
var _key := Vector3.ZERO
var _fill := Vector3.ZERO


func _init() -> void:
	disable_3d = true
	gui_disable_input = true
	use_hdr_2d = true
	size = Vector2i(PX, PX)
	render_target_update_mode = SubViewport.UPDATE_DISABLED
	material.shader = SHADER
	var rect := ColorRect.new()
	rect.material = material
	rect.size = Vector2(PX, PX)
	add_child(rect)


## Renders this frame if the lights (as set on `material`) differ from the
## ones it last rendered with.
func follow(key: Vector3, fill: Vector3) -> void:
	if key == _key and fill == _fill:
		return
	_key = key
	_fill = fill
	render_target_update_mode = SubViewport.UPDATE_ONCE
