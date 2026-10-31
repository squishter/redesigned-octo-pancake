extends Control
## Captures the actual menu, then places gem tiles carrying its image over the cover.

signal finished

const MenuBackdrop := preload("res://scenes/game/menu_backdrop.gd")
const SHADER := preload("res://render/gem_menu_reveal.gdshader")
const DURATION := 1.0

## The live menu is reparented into the app after the reveal; it is never recreated.
var menu: Control
var _viewport: SubViewport
var _tiles: ColorRect
var _material: ShaderMaterial
var _motion: Tween
var _progress := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_viewport = SubViewport.new()
	_viewport.disable_3d = true
	_viewport.gui_disable_input = true
	_viewport.size = Vector2i(size)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	_viewport.add_child(MenuBackdrop.new())
	menu.theme = get_tree().root.theme
	menu.process_mode = Node.PROCESS_MODE_DISABLED
	_viewport.add_child(menu)
	_tiles = ColorRect.new()
	_tiles.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_tiles.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_material.set_shader_parameter("menu_texture", _viewport.get_texture())
	_material.set_shader_parameter("grid", Vector2(7, maxf(1, ceilf(size.y / maxf(size.x, 1) * 7))))
	_tiles.material = _material
	_tiles.hide()
	add_child(_tiles)
	resized.connect(_resize)
	_start.call_deferred()


func _resize() -> void:
	_viewport.size = Vector2i(size)
	_material.set_shader_parameter("grid", Vector2(7, maxf(1, ceilf(size.y / maxf(size.x, 1) * 7))))
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func _start() -> void:
	# Let containers and font measurements settle before freezing the menu image.
	for _i in 4:
		await get_tree().process_frame
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_tiles.show()
	_motion = create_tween()
	_motion.tween_method(_set_progress, 0.0, 1.0, DURATION)
	_motion.tween_callback(func() -> void: finished.emit())


func _set_progress(value: float) -> void:
	_progress = value
	_material.set_shader_parameter("progress", value)
