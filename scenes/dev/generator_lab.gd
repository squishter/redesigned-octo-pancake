extends Control
## Developer screen for the puzzle generators: pick a source (seeded mandala
## or a photo, picked or taken with the camera) and a mode, generate on a
## worker thread, and look at the result. Kits come in the game's sizes (up
## to X-large), with drills in the gem colors or the picture's own colors.
## Laid out for phones: the picture fills the screen (pinch to zoom, drag to
## pan, double-tap to fit), with the main actions in a bar at the bottom and
## every setting in an Options panel above it. The Lines box above the
## picture flips to the line art it was made from, without regenerating, and
## the 3D box shows collages and kits as real gems (GemBoard3D) instead of
## flat shapes. Opened from the game's menu (`show_back`), a Menu button
## goes back to it.

signal back_requested

const PreviewCanvas := preload("res://scenes/dev/preview_canvas.gd")
const LabTheme := preload("res://scenes/dev/lab_theme.gd")

var _source: OptionButton
var _variant: OptionButton
var _template: OptionButton
var _collar: OptionButton
var _silhouette: OptionButton
var _zoom: OptionButton
var _frame: OptionButton
var _theme: OptionButton
var _mode: OptionButton
var _kit_size: OptionButton
var _drill_colors: OptionButton
var _sparsity: OptionButton
var _line_style: OptionButton
var _setting: OptionButton
var _line_gems: OptionButton
var _seed: SpinBox
var _pattern: SpinBox
var _wobble: HSlider
var _detail: HSlider
var _colors: SpinBox
var _status: Label
var _summary: Label
var _show_lines: CheckBox
var _show_3d: CheckBox
var _canvas: PreviewCanvas
var _board: GemBoard3D
var _perf: PerfReadout
## The picture the 3D board should show (built when it first shows it).
var _board_picture: Dictionary = {}
var _board_stale := false
var _options_panel: Control
var _options_button: Button
var _file_dialog: FileDialog
var _camera: CameraCapture

## Show a Menu button that goes back to the game.
var show_back := false
var _photo: Image
var _task_id := -1
var _task_started := 0
var _result: Dictionary = {}


func _ready() -> void:
	get_tree().root.theme = LabTheme.build()
	RenderingServer.set_default_clear_color(LabTheme.BG)
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 24)
	add_child(root)
	_avoid_cutouts(root)

	var top := HBoxContainer.new()
	root.add_child(top)
	if show_back:
		_button(top, "‹ Menu", go_back)
	_summary = Label.new()
	_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_summary.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_summary.add_theme_font_size_override("font_size", LabTheme.SMALL_FONT_SIZE)
	_summary.add_theme_color_override("font_color", LabTheme.TEXT_DIM)
	top.add_child(_summary)
	# Same picture, as its line art: tells line-art problems from gem-pattern ones.
	_show_lines = CheckBox.new()
	_show_lines.text = "Lines"
	_show_lines.custom_minimum_size.y = LabTheme.TAP_HEIGHT
	_show_lines.toggled.connect(func(on: bool) -> void:
		_canvas.line_art = on
		_refresh_view())
	top.add_child(_show_lines)
	_show_3d = CheckBox.new()
	_show_3d.text = "3D"
	_show_3d.button_pressed = true
	_show_3d.custom_minimum_size.y = LabTheme.TAP_HEIGHT
	_show_3d.toggled.connect(func(_on: bool) -> void: _refresh_view())
	top.add_child(_show_3d)
	_button(top, "Fit", func() -> void:
		_canvas.reset_view()
		_board.reset_view()).size_flags_horizontal = Control.SIZE_SHRINK_END

	_canvas = PreviewCanvas.new()
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas.clip_contents = true
	root.add_child(_canvas)
	_board = GemBoard3D.new()
	_board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_board.visible = false
	root.add_child(_board)
	# Over the board (see PerfReadout), when Readout in the Options is on.
	_perf = PerfReadout.new()
	_perf.board = _board
	_perf.position = Vector2(24.0, 150.0)
	add_child(_perf)

	# Options: hidden until asked for, and scrolls when taller than its share.
	var panel := PanelContainer.new()
	panel.visible = false
	panel.custom_minimum_size.y = get_viewport_rect().size.y * 0.5
	root.add_child(panel)
	_options_panel = panel
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	DragScroll.attach(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	var actions := HFlowContainer.new()
	list.add_child(actions)
	_button(actions, "Generate", _generate)
	_button(actions, "Photo…", func() -> void: _file_dialog.popup_centered_ratio(0.8))
	_button(actions, "Camera…", func() -> void: _camera.open())
	_button(actions, "Save JSON", _save)

	var controls := GridContainer.new()
	controls.columns = 2
	list.add_child(controls)
	# How the 3D board looks; changes show at once, nothing regenerates.
	_label(controls, "Shadows")
	var shadows := CheckBox.new()
	shadows.text = "Under each gem"
	shadows.button_pressed = true
	shadows.toggled.connect(func(on: bool) -> void: _board.shadows = on)
	_fill_row(shadows)
	controls.add_child(shadows)
	_label(controls, "Studio")
	var studio := CheckBox.new()
	studio.text = "From a map (off: per pixel)"
	studio.button_pressed = true
	studio.toggled.connect(func(on: bool) -> void: _board.studio_map = on)
	_fill_row(studio)
	controls.add_child(studio)
	_label(controls, "Readout")
	var readout := CheckBox.new()
	readout.text = "Performance"
	readout.button_pressed = PerfReadout.shown
	readout.toggled.connect(func(on: bool) -> void:
		if on != PerfReadout.shown:
			_perf.toggle())
	_fill_row(readout)
	controls.add_child(readout)
	_source = _options(controls, "Source", ["Mandala", "Photo"])
	_variant = _options(controls, "Shape", MandalaGenerator.VARIANTS + ["random"])
	_template = _options(controls, "Petals", ["random"] + FlowerGenerator.TEMPLATES.keys())
	_collar = _options(controls, "Collar", ["random"] + HeartGenerator.COLLARS)
	_silhouette = _options(controls, "Outline", ["random"] + MandalaDesign.SILHOUETTES)
	_zoom = _options(controls, "Zoom", ["auto", "off", "on"])
	_frame = _options(controls, "Frame", ["auto", "off", "on"])
	_theme = _options(controls, "Theme", Array(Palettes.theme_names()))
	_mode = _options(controls, "Mode", ["Collage", "Kit", "Line art"])
	# The game's kit sizes: drills on the longer side.
	_kit_size = _options(controls, "Kit size", KitGenerator.LONG_SIDES.keys())
	# Gem colors (k-means, snapped to the starter gems) or the picture's own
	# colors (as many as Kit colors), each cell mapped straight to the nearest
	# as the game's photo kits do.
	_drill_colors = _options(controls, "Drill colors", ["gems", "photo"])
	_sparsity = _options(controls, "Sparse", ["auto", "none", "some", "lots"])
	_line_style = _options(controls, "Lines", ["auto"] + DesignPlan.LINE_STYLES)
	_setting = _options(controls, "Setting", ["auto"] + CollageGenerator.SETTINGS)
	_line_gems = _options(controls, "Line gems", ["auto"] + _unique(GemLines.STYLES))
	_seed = _spin(controls, "Seed", 1, 999999, 1)
	_pattern = _spin(controls, "Pattern", 0, 999999, 0)
	_colors = _spin(controls, "Kit colors", 12, 40, 20)
	_wobble = _slider(controls, "Wobble", 0.0)
	_detail = _slider(controls, "Detail", 0.5)

	# Everything the last run reported.
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size.x = 200
	_status.add_theme_font_size_override("font_size", LabTheme.SMALL_FONT_SIZE)
	_status.add_theme_color_override("font_color", LabTheme.TEXT_DIM)
	list.add_child(_status)

	# The main actions, where thumbs reach.
	var bar := HBoxContainer.new()
	root.add_child(bar)
	for b in [_button(bar, "New seed", _new_seed), _button(bar, "New pattern", _new_pattern)]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_options_button = _button(bar, "Options", _toggle_options)
	_options_button.toggle_mode = true

	_file_dialog = FileDialog.new()
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.use_native_dialog = true
	_file_dialog.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp ; Images"])
	_file_dialog.file_selected.connect(_on_photo_selected)
	add_child(_file_dialog)

	_camera = CameraCapture.new()
	_camera.captured.connect(_use_photo)
	add_child(_camera)

	_generate()


## Back to the game (a picture being made finishes first: its worker writes here).
func go_back() -> void:
	if _camera.visible:
		_camera.close()
		return
	if not show_back:
		return
	if _task_id >= 0:
		WorkerThreadPool.wait_for_task_completion(_task_id)
		_task_id = -1
	back_requested.emit()


## Keeps the layout clear of notches and rounded corners.
func _avoid_cutouts(root: Control) -> void:
	var safe := DisplayServer.get_display_safe_area()
	var window := Vector2(DisplayServer.window_get_size())
	if safe.size.x <= 0 or window.x <= 0.0:
		return
	var px := get_viewport_rect().size / window
	var top := safe.position.y * px.y
	var bottom := (window.y - safe.end.y) * px.y
	root.offset_top = maxf(root.offset_top, top)
	root.offset_bottom = minf(root.offset_bottom, -bottom)


## Shows the 3D board or the flat canvas: the board for collages and kits
## while 3D is on (unless the line art is showing).
func _refresh_view() -> void:
	var on_board := _show_3d.button_pressed and not _show_lines.button_pressed and not _board_picture.is_empty()
	_board.visible = on_board
	_canvas.visible = not on_board
	if on_board and _board_stale:
		_board_stale = false
		if _board_picture.has("slots"):
			_board.show_collage(_board_picture)
		else:
			_board.show_kit(_board_picture)


func _toggle_options() -> void:
	_options_panel.visible = _options_button.button_pressed


## Shows a short line above the picture and the full text in the options.
func _say(summary: String, details := "") -> void:
	_summary.text = summary
	_status.text = details if details != "" else summary


func _new_seed() -> void:
	_seed.value = randi_range(1, 999999)
	_generate()


## Same lines, another gem collage.
func _new_pattern() -> void:
	_pattern.value = randi_range(1, 999999)
	_generate()


static func _unique(items: Array) -> Array:
	var out := []
	for item in items:
		if not item in out:
			out.append(item)
	return out


func _options(parent: Control, label: String, items: Array) -> OptionButton:
	_label(parent, label)
	var ob := OptionButton.new()
	for item in items:
		ob.add_item(str(item).capitalize())
		ob.set_item_metadata(ob.item_count - 1, item)
	ob.item_selected.connect(func(_i: int) -> void: _generate())
	_fill_row(ob)
	ob.fit_to_longest_item = false
	parent.add_child(ob)
	return ob


func _spin(parent: Control, label: String, lo: float, hi: float, value: float) -> SpinBox:
	_label(parent, label)
	var sb := SpinBox.new()
	sb.min_value = lo
	sb.max_value = hi
	sb.value = value
	sb.select_all_on_focus = true
	sb.value_changed.connect(func(_v: float) -> void: _generate())
	_fill_row(sb)
	var row := HBoxContainer.new()
	row.add_child(sb)
	for step: float in [-1.0, 1.0]:
		var b := _button(row, "−" if step < 0.0 else "+", func() -> void: sb.value += step)
		b.custom_minimum_size.x = LabTheme.TAP_HEIGHT
	parent.add_child(row)
	return sb


func _slider(parent: Control, label: String, value: float) -> HSlider:
	_label(parent, label)
	var sl := HSlider.new()
	sl.min_value = 0.0
	sl.max_value = 1.0
	sl.step = 0.05
	sl.value = value
	sl.drag_ended.connect(func(_changed: bool) -> void: _generate())
	_fill_row(sl)
	parent.add_child(sl)
	return sl


func _button(parent: Control, text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size.y = LabTheme.TAP_HEIGHT
	b.pressed.connect(action)
	parent.add_child(b)
	return b


func _label(parent: Control, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	parent.add_child(l)


## A settings row's control takes the rest of the row, at tap height.
func _fill_row(c: Control) -> void:
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.custom_minimum_size.y = LabTheme.TAP_HEIGHT


func _selected(ob: OptionButton) -> Variant:
	return ob.get_item_metadata(ob.selected)


func _on_photo_selected(path: String) -> void:
	var img := PhotoLoader.open(path)
	if img == null or img.is_empty():
		_say("Couldn't load %s" % path)
		return
	_use_photo(img)


## A photo picked or taken: the source from now on.
func _use_photo(img: Image) -> void:
	_photo = img
	_source.select(1)
	_generate()


func _generate() -> void:
	if _task_id >= 0:
		return  # one at a time; the current job finishes first
	var use_photo: bool = _source.selected == 1
	if use_photo and _photo == null:
		_say("Pick a photo first.")
		return
	var job := {
		"photo": _photo if use_photo else null,
		"seed": int(_seed.value),
		"variant": _selected(_variant),
		"template": _selected(_template),
		"collar": _selected(_collar),
		"silhouette": _selected(_silhouette),
		"zoom": _selected(_zoom),
		"frame": _selected(_frame),
		"theme": _selected(_theme),
		"wobble": _wobble.value,
		"detail": _detail.value,
		"mode": _selected(_mode),
		"kit_size": _selected(_kit_size),
		"colors": int(_colors.value),
		"drill_colors": _selected(_drill_colors),
		"sparsity": {"auto": -1.0, "none": 0.0, "some": 0.3, "lots": 0.6}[_selected(_sparsity)],
		"line_style": _selected(_line_style),
		"setting": _selected(_setting),
		"line_gems": _selected(_line_gems),
		"pattern_seed": int(_pattern.value),
	}
	_say("Generating…")
	_task_started = Time.get_ticks_msec()
	_task_id = WorkerThreadPool.add_task(_run_job.bind(job), false, "generate picture")


## Runs on a worker thread; touches no nodes.
func _run_job(job: Dictionary) -> void:
	var opts := {
		"seed": job["seed"],
		"variant": job["variant"],
		"template": job["template"],
		"collar": job["collar"],
		"silhouette": job["silhouette"],
		"theme": job["theme"],
		"wobble": job["wobble"],
		"detail": job["detail"],
		"sparsity": job["sparsity"],
		"line_style": job["line_style"],
		"setting": job["setting"],
		"pattern_seed": job["pattern_seed"],
	}
	if job["line_gems"] != "auto":
		opts["line_gems"] = job["line_gems"]
	if job["zoom"] != "auto":
		opts["zoom"] = job["zoom"] == "on"
	if job["frame"] != "auto":
		opts["frame"] = job["frame"] == "on"
	var photo: Image = job["photo"]
	# The line art is made once and kept, so the Lines box can show it.
	var lines := PhotoLineArt.generate(photo, opts) if photo else PictureSources.mandala_lines(job["seed"], opts)
	var out := {"mode": job["mode"], "lines": lines}
	match job["mode"]:
		"Collage":
			out["picture"] = (PictureSources.photo_collage(photo, opts, lines) if photo
					else PictureSources.mandala_collage(job["seed"], opts, lines))
		"Kit":
			var src: Image = photo if photo else PictureSources.mandala_image(job["seed"], opts, lines)
			var kit_options := {"size": KitGenerator.board_long(src, KitGenerator.LONG_SIDES[job["kit_size"]]),
					"colors": job["colors"], "seed": job["seed"]}
			if job["drill_colors"] == "photo":
				kit_options.merge({"direct": true, "exact": true, "dither": PuzzleMaker.PHOTO_OWN_DITHER,
						"cleanup": false}, true)
			out["picture"] = KitGenerator.generate(src, kit_options)
	_result = out


func _process(_delta: float) -> void:
	if _task_id < 0 or not WorkerThreadPool.is_task_completed(_task_id):
		return
	WorkerThreadPool.wait_for_task_completion(_task_id)
	_task_id = -1
	var ms := Time.get_ticks_msec() - _task_started
	var out := _result
	var art: Dictionary = out["lines"]
	_canvas.set_line_art(art["mask"], art["width"], art["height"])
	match out.get("mode"):
		"Collage":
			var p: Dictionary = out["picture"]
			_canvas.show_collage(p)
			_show_on_board(p)
			var empty := 0
			var fills := {}
			for r in p["regions"]:
				if r["empty"]:
					empty += 1
				fills[r["fill"]] = fills.get(r["fill"], 0) + 1
			var flower := ""
			if p["source"].has("template"):
				flower = ", %s petals%s" % [p["source"]["template"], " (free-form)" if p["source"].get("free_form") else ""]
			if p["source"].has("heart"):
				var heart: Dictionary = p["source"]["heart"]
				flower = ", %s heart, %s collar, %s" % [heart["shape"], heart["collar"], " + ".join(PackedStringArray(heart["patterns"]))]
			if p["source"].has("butterfly"):
				var b: Dictionary = p["source"]["butterfly"]
				flower = ", %s wings, %s border, fore %s, hind %s" % [b["shape"], b["border"],
						" + ".join(PackedStringArray(b["fore"])), " + ".join(PackedStringArray(b["hind"]))]
			if p["source"].has("mandala"):
				var md: Dictionary = p["source"]["mandala"]
				flower = ", %d-fold, %s outline, extras %s%s" % [md["folds"], md["silhouette"],
						" + ".join(PackedStringArray(md["extras"])), ", zoomed in" if md["zoom"] else ""]
			if p["source"].has("snowflake"):
				var f: Dictionary = p["source"]["snowflake"]
				flower = ", %s center, %s arms, %s tips, between %s, details %s" % [f["center"], f["arm"], f["tip"],
						" + ".join(PackedStringArray(f["between"])), " + ".join(PackedStringArray(f["details"]))]
			if p["source"].has("frame"):
				var fr: Dictionary = p["source"]["frame"]
				flower += ", %s frame (%s band, %s corners), %s background" % [fr["shape"], fr["band"], fr["corner"],
						fr["background"]]
			var patterns := {}
			for r in p["regions"]:
				if r["kind"] == "area":
					patterns[r["style"]] = patterns.get(r["style"], 0) + 1
			var setting: String = p["setting"]
			if setting == "gems":
				setting = "gem lines (%s, %s colors, %d bold)" % [p["line_gems"], p["line_colors"], p["bold_lines"]]
			if p["dropped"] > 0:
				setting += ", %d left out for stone count" % p["dropped"]
			_say("Collage · %d stones · %d gem types · pattern %d · %d ms" % [p["slots"].size(), p["gem_types"],
					p["pattern_seed"], ms], ("Collage%s: %s, pattern %d, %d regions (%d too thin), %d slots, %d gem types, "
					+ "%.0f%% avg coverage, lines %s, fills %s, patterns %s%s%s — %d ms") % [
				flower, setting, p["pattern_seed"], p["regions"].size(), empty, p["slots"].size(), p["gem_types"],
				CollageGenerator.mean_coverage(p) * 100.0, p["line_style"], fills, patterns,
				", sizes shrink inward" if p["radial_size"] else "", ", tiered" if p["tiers"] else "", ms])
		"Kit":
			var k: Dictionary = out["picture"]
			_canvas.show_kit(k)
			_show_on_board(k)
			_say("Kit: %d×%d, %d %s colors — %d ms" % [k["width"], k["height"], k["palette"].size(),
					"own" if k["palette"][0]["gem_color_id"] == null else "gem", ms])
		_:
			_canvas.show_lines(art["mask"], art["width"], art["height"])
			_show_on_board({})
			_say("Line art %d×%d — %d ms" % [art["width"], art["height"], ms])


## Hands a collage or kit to the 3D board (empty for none).
func _show_on_board(picture: Dictionary) -> void:
	_board_picture = picture
	_board_stale = true
	_refresh_view()


func _save() -> void:
	if not _result.has("picture"):
		_say("Nothing to save in this mode.")
		return
	DirAccess.make_dir_recursive_absolute("user://generated")
	var path := "user://generated/%s_%d.json" % [str(_result["mode"]).to_lower(), Time.get_unix_time_from_system()]
	var err := PatternIO.save(_result["picture"], path)
	_say("Saved %s" % ProjectSettings.globalize_path(path) if err == OK else "Save failed: %s" % error_string(err))
