extends Control
## Developer screen for the puzzle generators: pick a source (seeded mandala
## or a photo) and a mode, generate on a worker thread, and look at the result.

const PreviewCanvas := preload("res://scenes/dev/preview_canvas.gd")

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
var _canvas: PreviewCanvas
var _file_dialog: FileDialog

var _photo: Image
var _task_id := -1
var _task_started := 0
var _result: Dictionary = {}


func _ready() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 16)
	add_child(root)

	var controls := HFlowContainer.new()
	root.add_child(controls)
	_source = _options(controls, "Source", ["Mandala", "Photo"])
	_variant = _options(controls, "Shape", MandalaGenerator.VARIANTS + ["random"])
	_template = _options(controls, "Petals", ["random"] + FlowerGenerator.TEMPLATES.keys())
	_collar = _options(controls, "Collar", ["random"] + HeartGenerator.COLLARS)
	_silhouette = _options(controls, "Outline", ["random"] + MandalaDesign.SILHOUETTES)
	_zoom = _options(controls, "Zoom", ["auto", "off", "on"])
	_frame = _options(controls, "Frame", ["auto", "off", "on"])
	_theme = _options(controls, "Theme", Array(Palettes.theme_names()))
	_mode = _options(controls, "Mode", ["Collage", "Kit", "Line art"])
	_kit_size = _options(controls, "Kit size", KitGenerator.BOARD_SIZES.keys())
	_sparsity = _options(controls, "Sparse", ["auto", "none", "some", "lots"])
	_line_style = _options(controls, "Lines", ["auto"] + DesignPlan.LINE_STYLES)
	_setting = _options(controls, "Setting", ["auto"] + CollageGenerator.SETTINGS)
	_line_gems = _options(controls, "Line gems", ["auto"] + _unique(GemLines.STYLES))
	_seed = _spin(controls, "Seed", 1, 999999, 1)
	_pattern = _spin(controls, "Pattern", 0, 999999, 0)
	_colors = _spin(controls, "Kit colors", 12, 40, 20)
	_wobble = _slider(controls, "Wobble", 0.0)
	_detail = _slider(controls, "Detail", 0.5)
	_button(controls, "New seed", _new_seed)
	_button(controls, "New pattern", _new_pattern)
	_button(controls, "Photo…", func() -> void: _file_dialog.popup_centered_ratio(0.8))
	_button(controls, "Generate", _generate)
	_button(controls, "Save JSON", _save)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_status)

	_canvas = PreviewCanvas.new()
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas.clip_contents = true
	root.add_child(_canvas)

	_file_dialog = FileDialog.new()
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.use_native_dialog = true
	_file_dialog.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp ; Images"])
	_file_dialog.file_selected.connect(_on_photo_selected)
	add_child(_file_dialog)

	_generate()


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
	var box := _labeled(parent, label)
	var ob := OptionButton.new()
	for item in items:
		ob.add_item(str(item).capitalize())
		ob.set_item_metadata(ob.item_count - 1, item)
	ob.item_selected.connect(func(_i: int) -> void: _generate())
	box.add_child(ob)
	return ob


func _spin(parent: Control, label: String, lo: float, hi: float, value: float) -> SpinBox:
	var box := _labeled(parent, label)
	var sb := SpinBox.new()
	sb.min_value = lo
	sb.max_value = hi
	sb.value = value
	box.add_child(sb)
	return sb


func _slider(parent: Control, label: String, value: float) -> HSlider:
	var box := _labeled(parent, label)
	var sl := HSlider.new()
	sl.min_value = 0.0
	sl.max_value = 1.0
	sl.step = 0.05
	sl.value = value
	sl.custom_minimum_size.x = 140
	sl.drag_ended.connect(func(_changed: bool) -> void: _generate())
	box.add_child(sl)
	return sl


func _button(parent: Control, text: String, action: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.pressed.connect(action)
	parent.add_child(b)


func _labeled(parent: Control, text: String) -> HBoxContainer:
	var box := HBoxContainer.new()
	var l := Label.new()
	l.text = text
	box.add_child(l)
	parent.add_child(box)
	return box


func _selected(ob: OptionButton) -> Variant:
	return ob.get_item_metadata(ob.selected)


func _on_photo_selected(path: String) -> void:
	var img := Image.load_from_file(path)
	if img == null or img.is_empty():
		_status.text = "Couldn't load %s" % path
		return
	_photo = img
	_source.select(1)
	_generate()


func _generate() -> void:
	if _task_id >= 0:
		return  # one at a time; the current job finishes first
	var use_photo: bool = _source.selected == 1
	if use_photo and _photo == null:
		_status.text = "Pick a photo first."
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
		"sparsity": {"auto": -1.0, "none": 0.0, "some": 0.3, "lots": 0.6}[_selected(_sparsity)],
		"line_style": _selected(_line_style),
		"setting": _selected(_setting),
		"line_gems": _selected(_line_gems),
		"pattern_seed": int(_pattern.value),
	}
	_status.text = "Generating…"
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
	var out := {"mode": job["mode"]}
	match job["mode"]:
		"Collage":
			out["picture"] = PictureSources.photo_collage(photo, opts) if photo else PictureSources.mandala_collage(job["seed"], opts)
		"Kit":
			var src: Image = photo if photo else PictureSources.mandala_image(job["seed"], opts)
			out["picture"] = KitGenerator.generate(src, {"size": job["kit_size"], "colors": job["colors"], "seed": job["seed"]})
		_:
			out["lines"] = PhotoLineArt.generate(photo, opts) if photo else PictureSources.mandala_lines(job["seed"], opts)
	_result = out


func _process(_delta: float) -> void:
	if _task_id < 0 or not WorkerThreadPool.is_task_completed(_task_id):
		return
	WorkerThreadPool.wait_for_task_completion(_task_id)
	_task_id = -1
	var ms := Time.get_ticks_msec() - _task_started
	var out := _result
	match out.get("mode"):
		"Collage":
			var p: Dictionary = out["picture"]
			_canvas.show_collage(p)
			var empty := 0
			var fills := {}
			for r in p["regions"]:
				if r["empty"]:
					empty += 1
				fills[r["fill"]] = fills.get(r["fill"], 0) + 1
			var flower := ""
			if p["source"].has("template"):
				flower = ", %s petals" % p["source"]["template"]
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
				setting = "gem lines (%s, %s colors)" % [p["line_gems"], p["line_colors"]]
			_status.text = ("Collage%s: %s, pattern %d, %d regions (%d too thin), %d slots, %d gem types, "
					+ "%.0f%% avg coverage, lines %s, fills %s, patterns %s%s%s — %d ms") % [
				flower, setting, p["pattern_seed"], p["regions"].size(), empty, p["slots"].size(), p["gem_types"],
				CollageGenerator.mean_coverage(p) * 100.0, p["line_style"], fills, patterns,
				", sizes shrink inward" if p["radial_size"] else "", ", tiered" if p["tiers"] else "", ms]
		"Kit":
			var k: Dictionary = out["picture"]
			_canvas.show_kit(k)
			_status.text = "Kit: %d×%d, %d colors — %d ms" % [k["width"], k["height"], k["palette"].size(), ms]
		_:
			var l: Dictionary = out["lines"]
			_canvas.show_lines(l["mask"], l["width"], l["height"])
			_status.text = "Line art %d×%d — %d ms" % [l["width"], l["height"], ms]


func _save() -> void:
	if not _result.has("picture"):
		_status.text = "Nothing to save in this mode."
		return
	DirAccess.make_dir_recursive_absolute("user://generated")
	var path := "user://generated/%s_%d.json" % [str(_result["mode"]).to_lower(), Time.get_unix_time_from_system()]
	var err := PatternIO.save(_result["picture"], path)
	_status.text = "Saved %s" % ProjectSettings.globalize_path(path) if err == OK else "Save failed: %s" % error_string(err)
