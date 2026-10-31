extends SceneTree
## Identical production-board renders with old and corrected normal transforms.
## xvfb-run -a godot --rendering-method mobile -s res://tests/render_gem_normals.gd

const PANEL := Vector2i(900, 600)
var _out := "res://build/gem-normal-renders"


func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
	_render.call_deferred()


func _render() -> void:
	DirAccess.make_dir_recursive_absolute(_out)
	var board := GemBoard3D.new()
	board.size = PANEL
	board.animate = false
	board.use_sensor = false
	board.input_enabled = false
	board._flares = false
	root.add_child(board)
	var slot := {"shape": "emerald", "cut": "step", "x": 110.0, "y": 70.0, "rotation": -0.18,
			"size": 170.0, "width": 68.0, "target_color": Color("#8acbd9"), "target_gem": "aquamarine"}
	var picture := {"width": 220, "height": 140, "slots": [slot]}
	var before := var_to_bytes(picture)
	board.show_collage(picture)
	board.set_process(false)
	board._viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var original := FileAccess.get_file_as_string("res://render/gem.gdshader")
	var angles := [-135.0, -45.0, 45.0]
	for angle in angles.size():
		var az := deg_to_rad(angles[angle])
		var el := deg_to_rad(50.0)
		var key := Vector3(cos(az) * cos(el), sin(el), sin(az) * cos(el))
		var fill := Vector3(cos(az + 2.6) * cos(0.6), sin(0.6), sin(az + 2.6) * cos(0.6))
		var images := []
		for fixed in [false, true]:
			var shader := Shader.new()
			shader.code = original if fixed else original.replace(
					"transpose(inverse(mat3(MODEL_MATRIX)))", "MODEL_NORMAL_MATRIX")
			board._gem_material.shader = shader
			board._gem_material.set_shader_parameter("studio_map", board._studio.get_texture())
			for material: ShaderMaterial in board._materials() + [board._studio.material]:
				material.set_shader_parameter("key_dir", key)
				material.set_shader_parameter("fill_dir", fill)
			board._studio.follow(key, fill)
			for i in 4:
				await process_frame
				await RenderingServer.frame_post_draw
			var img := board.get_view_texture().get_image()
			img.save_png(_out.path_join("angle-%d-%s.png" % [angle + 1, "after" if fixed else "before"]))
			images.append(img)
		await _comparison(images, angle + 1, angles[angle])
	assert(var_to_bytes(picture) == before, "Lighting renders must not change puzzle geometry")
	print("Lighting comparisons saved to ", ProjectSettings.globalize_path(_out))
	quit()


func _comparison(images: Array, index: int, angle: float) -> void:
	var canvas := SubViewport.new()
	canvas.disable_3d = true
	canvas.size = Vector2i(PANEL.x * 2, PANEL.y + 128)
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(canvas)
	var background := ColorRect.new()
	background.color = Color("#f4eee6")
	background.size = canvas.size
	canvas.add_child(background)
	for i in 2:
		var rect := TextureRect.new()
		rect.texture = ImageTexture.create_from_image(images[i])
		rect.position = Vector2(i * PANEL.x, 72.0)
		rect.size = PANEL
		canvas.add_child(rect)
		_label(canvas, "AFTER  /  Corrected normals" if i else "BEFORE  /  Original normals",
				Vector2(i * PANEL.x + 32, 22), 27)
	_label(canvas, "Emerald, step cut  /  2.5:1 proportions  /  Light angle %d: %.0f° azimuth, 50° elevation" % [index, angle],
			Vector2(32, PANEL.y + 88), 23)
	for i in 3:
		await process_frame
		await RenderingServer.frame_post_draw
	canvas.get_texture().get_image().save_png(_out.path_join("angle-%d-before-after.png" % index))
	canvas.queue_free()


func _label(parent: Node, text: String, at: Vector2, font_size: int) -> void:
	var label := Label.new()
	label.text = text
	label.position = at
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("#302c36"))
	parent.add_child(label)
