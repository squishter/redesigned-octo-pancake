extends SceneTree
## Captures the actual play screen after reopening an existing puzzle.
## Run with a real renderer and an isolated XDG_DATA_HOME.
## godot -s res://tests/render_saved_gem_proportions.gd -- --out=/tmp/saved-gems.png

const PlayScreen := preload("res://scenes/game/play_screen.gd")
var _out := "res://build/saved-gem-proportions/after.png"
var _before := ""


func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		if arg.begins_with("--before="):
			_before = arg.trim_prefix("--before=")
	_render.call_deferred()


func _render() -> void:
	root.content_scale_size = Vector2i(1080, 2400)
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	root.theme = PlayScreen.GameTheme.build()
	RenderingServer.set_default_clear_color(PlayScreen.GameTheme.BG)
	var screen := SubViewport.new()
	screen.size = Vector2i(1080, 2400)
	screen.disable_3d = true
	screen.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(screen)
	var profile := SaveStore.upgrade({})
	var slots := []
	var shapes := ["heart", "hexagon", "star", "triangle"]
	var gems := ["ruby", "sapphire", "sunflower", "amethyst"]
	for row in shapes.size():
		for column in 2:
			slots.append({"id": slots.size(), "region": 0, "shape": shapes[row],
					"cut": GemCuts.for_shape(shapes[row])[0], "x": 120.0 + column * 180.0, "y": 130.0 + row * 145.0,
					"size": 100.0, "width": 40.0, "rotation": SlotPacker.upright(shapes[row]),
					"target_color": GemCatalog.color_of(gems[row]), "target_gem": gems[row]})
	var picture := {"type": "collage", "width": 420, "height": 700, "slots": slots}
	var meta := SaveStore.add_puzzle(profile, picture)
	SaveStore.save_progress(meta["id"], PackedByteArray([1, 0, 1, 0, 1, 0, 1, 0]))
	var play := PlayScreen.new()
	play.theme = root.theme
	play.profile = profile
	play.puzzle_id = meta["id"]
	screen.add_child(play)
	for board: GemBoard3D in [play._board, play._icons]:
		board.animate = false
		board.use_sensor = false
		board.light_time = 0.0
		board.update_light()
	for i in 12:
		await process_frame
		await RenderingServer.frame_post_draw
	await create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(_out.get_base_dir())
	var after := screen.get_texture().get_image()
	after.resize(540, 1200, Image.INTERPOLATE_LANCZOS)
	after.save_png(_out)
	if _before != "":
		await _comparison(Image.load_from_file(_before), after)
	print("Saved-puzzle screen rendered to ", ProjectSettings.globalize_path(_out))
	quit()


func _comparison(before: Image, after: Image) -> void:
	# Keep the comparison focused on the picker and the demonstration board.
	before = before.get_region(Rect2i(0, 0, before.get_width(), mini(700, before.get_height())))
	after = after.get_region(Rect2i(0, 0, after.get_width(), mini(700, after.get_height())))
	var canvas := SubViewport.new()
	canvas.disable_3d = true
	canvas.size = Vector2i(after.get_width() * 2, after.get_height() + 64)
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(canvas)
	var background := ColorRect.new()
	background.color = Color("#f4eee6")
	background.size = canvas.size
	canvas.add_child(background)
	for i in 2:
		var rect := TextureRect.new()
		rect.texture = ImageTexture.create_from_image(before if i == 0 else after)
		rect.position = Vector2(i * after.get_width(), 64.0)
		rect.size = after.get_size()
		canvas.add_child(rect)
		var label := Label.new()
		label.text = "Before / current main" if i == 0 else "After / saved proportions"
		label.position = Vector2(i * after.get_width() + 16, 12)
		label.add_theme_font_size_override("font_size", 25)
		label.add_theme_color_override("font_color", Color("#302c36"))
		canvas.add_child(label)
	for i in 3:
		await process_frame
		await RenderingServer.frame_post_draw
	canvas.get_texture().get_image().save_png(_out.get_base_dir().path_join("before-after.png"))
