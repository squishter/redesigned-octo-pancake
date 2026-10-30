extends SceneTree
## Native current/proposed placement studies. Run with --fixed-fps 30.

const Polish := preload("res://tests/previews/placement_polish.gd")
const GameTheme := preload("res://scenes/game/game_theme.gd")
const OUTPUT := "res://build/placement-previews"
const VIEW := Vector2i(1440, 1080)
const FPS := 30.0
const STYLES := ["pop", "fly", "drop", "spin", "twinkle", "bounce", "comet", "firework", "halo"]
const INK := Color("#151a2a")
const GOLD := Color("#f3d286")
const GEM_COLOR := Color("#7760cf")
var _canvas: Control
var _title: Label
var _subtitle: Label
var _phase: Label
var _panels: Array[Dictionary] = []
var _picture: Dictionary
var _icons: GemBoard3D
var _icon: Texture2D
var _captures := 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	root.content_scale_size = VIEW
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	root.theme = GameTheme.build()
	RenderingServer.set_default_clear_color(INK)
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	_canvas = Control.new()
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(_canvas)
	_title = _label(_canvas, "", Rect2(32, 18, 1360, 50), 34, GOLD)
	_subtitle = _label(_canvas, "", Rect2(32, 72, 1360, 48), 21)
	_phase = _label(_canvas, "", Rect2(32, 1000, 1360, 52), 21, GOLD)
	_picture = _fixture()
	await _build_icon()
	for close in [false, true]:
		_build_panels(3, close)
		_title.text = "BEAM / " + ("Close view" if close else "Fitted board")
		_subtitle.text = "Same overhead light, same 0.42 s placement. Current / A: soft column / B: prismatic column."
		await _warmup()
		var folder := "beam-close" if close else "beam-fit"
		for frame in 80:
			if frame == 7:
				_launch("beam", 0)
			if frame in [36, 39, 42, 45]:
				_launch("beam", 1 + (frame - 36) / 3)
			_phase.text = "Single placement" if frame < 33 else "Fast stroke / four placements, staggered 0.10 s"
			await _frame(folder, frame)
		_validate_lands(5)
	_build_panels(2, false)
	await _warmup()
	for style: String in STYLES:
		_reset_slots()
		_title.text = style.to_upper() + " / Current and proposed polish"
		_subtitle.text = GemCatalog.ANIMATIONS[style]["about"] + "  Original path and placement timing retained."
		for frame in 50:
			if frame == 6:
				_launch(style, 0)
			if frame in [25, 28, 31]:
				_launch(style, 1 + (frame - 25) / 3)
			_phase.text = "Single placement" if frame < 24 else "Fast stroke / three placements"
			await _frame(style, frame)
		_validate_lands(4)
	print("Placement previews: %d native frames; all landing checks passed." % _captures)
	quit()


func _build_panels(count: int, close: bool) -> void:
	for panel in _panels:
		_canvas.remove_child(panel["node"])
		(panel["node"] as Node).queue_free()
	_panels.clear()
	var width := (VIEW.x - 32.0 * 2.0 - (count - 1) * 20.0) / count
	for index in count:
		var panel := Panel.new()
		panel.position = Vector2(32 + index * (width + 20), 140)
		panel.size = Vector2(width, 830)
		var box := StyleBoxFlat.new()
		box.bg_color = Color("#222b40")
		box.border_color = Color("#4c5a73")
		box.set_border_width_all(1)
		box.set_corner_radius_all(20)
		panel.add_theme_stylebox_override("panel", box)
		_canvas.add_child(panel)
		var title := "Current"
		var about := "Production animation"
		if index > 0:
			title = ["", "A / Soft column", "B / Prismatic column"][index] if count == 3 else "Proposed polish"
			about = "Feathered light / fine core" if index == 1 else "Faceted light / descending streaks"
			if count == 2:
				about = "Clearer trail / precise landing"
		_label(panel, title, Rect2(20, 18, width - 40, 46), 28, GOLD)
		_label(panel, about, Rect2(20, 65, width - 40, 44), 19)
		# Production Comet reads its viewport size. Give every comparison its
		# own viewport so "off screen" is relative to that panel, not the sheet.
		var display := SubViewportContainer.new()
		display.position = Vector2(12, 122)
		display.size = Vector2(width - 24, 620)
		display.stretch = true
		panel.add_child(display)
		var viewport := SubViewport.new()
		viewport.size = Vector2i(display.size)
		viewport.handle_input_locally = false
		display.add_child(viewport)
		var world := Control.new()
		world.size = display.size
		viewport.add_child(world)
		var board := GemBoard3D.new()
		board.size = world.size
		board.animate = false
		board.use_sensor = false
		board.input_enabled = false
		world.add_child(board)
		board.set_process(false)
		var shown := PackedByteArray()
		shown.resize(_picture["slots"].size())
		shown.fill(1)
		for i in 5:
			shown[i] = 0
		board.show_collage(_picture, shown)
		if close:
			board.focus_on(Rect2(150, 220, 100, 100))
		var overlay := SlotOverlay.new()
		overlay.board = board
		overlay.size = world.size
		world.add_child(overlay)
		var types := PackedInt32Array()
		types.resize(shown.size())
		overlay.setup(_picture, types, PackedColorArray([GEM_COLOR]), shown.duplicate())
		overlay.selected = 0
		var flights: GemFlights = GemFlights.new() if index == 0 else Polish.new()
		if index > 0:
			flights.set("treatment", "prism" if index == 2 else "soft")
		flights.board = board
		flights.size = world.size
		world.add_child(flights)
		flights.set_process(false)
		var data := {"node": panel, "board": board, "overlay": overlay, "flights": flights, "lands": []}
		flights.landed.connect(func(slot: int) -> void:
			(data["lands"] as Array).append(slot)
			board.land_slot(slot))
		_panels.append(data)
		# One real rendered gem at the bottom provides the Fly/Bounce source.
		var source := Panel.new()
		source.position = Vector2(world.size.x / 2.0 - 38, 536)
		source.size = Vector2(76, 76)
		source.add_theme_stylebox_override("panel", _source_style())
		world.add_child(source)
		var icon := TextureRect.new()
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.texture = _icon
		icon.position = Vector2(6, 6)
		icon.size = Vector2(64, 64)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		source.add_child(icon)
		_label(panel, "REAL GEM BOARD / ORIGINAL TIMING", Rect2(16, 765, width - 32, 48), 17)


func _source_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#28334c")
	style.border_color = GOLD
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	return style


func _reset_slots() -> void:
	for panel in _panels:
		(panel["lands"] as Array).clear()
		var overlay: SlotOverlay = panel["overlay"]
		var flights: GemFlights = panel["flights"]
		for child in flights.get_children():
			if child is CPUParticles2D:
				flights.remove_child(child)
				child.queue_free()
		if flights.get_script() == Polish:
			flights.get("_impacts").clear()
		for i in 5:
			(panel["board"] as GemBoard3D).set_slot_shown(i, false)
			overlay.placed[i] = 0
		overlay.setup(_picture, overlay.type_of, overlay.type_colors, overlay.placed)


func _launch(style: String, slot: int) -> void:
	for panel in _panels:
		var board: GemBoard3D = panel["board"]
		var flights: GemFlights = panel["flights"]
		var s: Dictionary = _picture["slots"][slot]
		(panel["overlay"] as SlotOverlay).place(slot)
		if style in ["pop", "twinkle"]:
			board.fill_slot(slot)
			(panel["lands"] as Array).append(slot)
			if style == "twinkle" or flights.get_script() == Polish:
				flights.burst(Vector2(s["x"], s["y"]), s["size"], GEM_COLOR)
		else:
			# Reset the random seed so the baseline and proposals share the path.
			seed(8271 + slot)
			var accepted := flights.send(style, slot, _icon, GemIcons.ROUND,
				Vector2(flights.size.x / 2.0, 574), 64, Vector2(s["x"], s["y"]), s["size"], 0, 0, GEM_COLOR)
			if not accepted:
				push_error("Preview flight was rejected")
				quit(1)


func _warmup() -> void:
	for _i in 5:
		await process_frame
		await RenderingServer.frame_post_draw


func _frame(folder: String, frame: int) -> void:
	for panel in _panels:
		(panel["board"] as GemBoard3D)._process(1.0 / FPS)
		(panel["flights"] as GemFlights)._process(1.0 / FPS)
	await process_frame
	await RenderingServer.frame_post_draw
	var path := OUTPUT.path_join(folder)
	if frame == 0:
		DirAccess.make_dir_recursive_absolute(path)
	var capture := root.get_texture().get_image()
	if capture == null or capture.is_empty() or capture.save_png(path.path_join("%04d.png" % frame)) != OK:
		push_error("Native frame capture failed")
		quit(1)
	_captures += 1


func _validate_lands(expected: int) -> void:
	for panel in _panels:
		var lands: Array = panel["lands"]
		var unique := {}
		for slot: int in lands:
			unique[slot] = true
		if lands.size() != expected or unique.size() != expected or (panel["flights"] as GemFlights).flying() != 0:
			push_error("A comparison lost, duplicated or delayed a gem landing")
			quit(1)


func _build_icon() -> void:
	_icons = GemBoard3D.new()
	_icons.size = Vector2(192, 192)
	_icons.position = Vector2(-10000, 0)
	_icons.margin = 0.0
	_icons.animate = false
	_icons.use_sensor = false
	_icons.set_transparent()
	_canvas.add_child(_icons)
	_icons.set_always_render()
	_icons.show_collage({"width": 100, "height": 100,
		"slots": [GemIcons.stone("round", "brilliant", GEM_COLOR, "amethyst", 1.0, 100, Vector2(50, 50))]})
	await _warmup()
	# Freeze the real rendered icon so all panels sample the same image
	# while their viewports are replaced between studies.
	var capture := _icons.get_view_texture().get_image()
	if capture == null or capture.is_empty():
		push_error("Could not render the preview's real gem icon")
		quit(1)
		return
	_icon = ImageTexture.create_from_image(capture)
	_icons.queue_free()


func _fixture() -> Dictionary:
	var slots := []
	for at: Vector2 in [Vector2(200, 265), Vector2(163, 265), Vector2(200, 302), Vector2(237, 265), Vector2(200, 228)]:
		slots.append({"x": at.x, "y": at.y, "size": 25.0, "width": 25.0, "rotation": 0.0,
			"shape": "round", "cut": "brilliant", "target_color": GEM_COLOR, "target_gem": "amethyst"})
	var colors := [Color("#3e9e97"), Color("#df9c86"), Color("#b7b1d4"), Color("#89b7a2")]
	for ring in 4:
		var count := 12 + ring * 6
		var radius := 70.0 + ring * 37.0
		for i in count:
			var angle := i * TAU / count - PI / 2.0
			var at := Vector2(200, 265) + Vector2.from_angle(angle) * radius
			slots.append({"x": at.x, "y": at.y, "size": 29.0, "width": 17.0, "rotation": angle,
				"shape": "marquise", "cut": "brilliant", "target_color": colors[ring], "target_gem": ""})
	return {"width": 400, "height": 520, "slots": slots}


func _label(parent: Node, copy: String, rect: Rect2, px: int, color := Color("#bdc7d8")) -> Label:
	var label := Label.new()
	label.text = copy
	label.position = rect.position
	label.size = rect.size
	label.add_theme_font_size_override("font_size", px)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label
