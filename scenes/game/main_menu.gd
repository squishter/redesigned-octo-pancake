extends Control
## The game's menu: start a new puzzle, or pick up a saved one. A new puzzle
## is chosen in steps: the kind (gem collage or diamond kit), then its source
## (an unlocked picture type, or a photo), then only the options that source
## has (colors, photo subject, kit colors, kit size). Every puzzle keeps its own save, so
## a new one never overwrites one in progress. Each saved puzzle can be
## continued, restarted, recolored (the same picture made again in another
## unlocked theme, as a new puzzle beside it) or deleted. Collection & packs
## shows what she has and opens packs for more (with her coins and free
## picks shown beside it). Photo puzzles start from one of her photos or one
## she takes right then with the camera. Settings (how placed gems go in, the
## finale) and the generator lab, a debug mode, are at the bottom.

signal play_requested(id: String)
signal lab_requested
signal collection_requested

const GameTheme := preload("res://scenes/game/game_theme.gd")
const THUMB_PX := 220
## Restart and Delete ask again; a second tap within this long confirms.
const CONFIRM_MS := 3000

## The player's profile (SaveStore), shared with the app; set before adding.
var profile: Dictionary = {}

var _menu_scroll: ScrollContainer
var _list: VBoxContainer
var _new_panel: Control
var _settings_panel: Control
var _kind: OptionButton
var _source: OptionButton
var _about: Label
var _theme: OptionButton
var _start: Button
var _choose_photo: Button
var _take_photo_button: Button
var _new_title: Label
var _subject: OptionButton
var _kit_size: OptionButton
var _kit_colors: OptionButton
var _photo_dialog: FileDialog
var _camera: CameraCapture
## Which photo puzzle the picker is choosing a photo for.
var _photo_kind := ""
## The puzzle being recolored, or empty for a brand new one.
var _recolor: Dictionary = {}
var _busy: Control
var _busy_label: Label
var _task_id := -1
var _request: Dictionary = {}
var _result: Dictionary = {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_menu_scroll = ScrollContainer.new()
	_menu_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 40)
	_menu_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_menu_scroll)
	SafeArea.apply(_menu_scroll)
	DragScroll.attach(_menu_scroll)
	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 28)
	_menu_scroll.add_child(root)
	var eyebrow := Label.new()
	eyebrow.text = "A LITTLE SPARKLE. A LITTLE YOU."
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	eyebrow.add_theme_font_size_override("font_size", 27)
	eyebrow.add_theme_color_override("font_color", GameTheme.MINT)
	root.add_child(eyebrow)
	var illustration := TextureRect.new()
	illustration.texture = load("res://assets/ui/hero.svg")
	illustration.custom_minimum_size.y = 260
	illustration.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	illustration.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	illustration.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(illustration)

	var title := Label.new()
	title.text = "Paint With Gems"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 78)
	title.add_theme_color_override("font_color", GameTheme.GOLD)
	root.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "Make something beautiful, one gem at a time."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.add_theme_font_size_override("font_size", 32)
	subtitle.add_theme_color_override("font_color", GameTheme.TEXT_DIM)
	root.add_child(subtitle)

	var new_button := _button(root, "New puzzle", func() -> void: _open_new({}))
	new_button.custom_minimum_size.y = 156
	new_button.theme_type_variation = "PrimaryButton"

	var wallet := VBoxContainer.new()
	root.add_child(wallet)
	var coins := Label.new()
	coins.text = "%d coins · %d free pick%s" % [Packs.coins(profile), Packs.picks(profile),
			"" if Packs.picks(profile) == 1 else "s"]
	coins.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	coins.add_theme_color_override("font_color", GameTheme.GOLD)
	coins.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	coins.add_theme_font_size_override("font_size", 30)
	wallet.add_child(coins)
	var packs := _button(wallet, "Collection & packs", func() -> void: collection_requested.emit())
	if Packs.picks(profile) > 0:
		packs.text = "Collection & packs · %d free pick%s" % [Packs.picks(profile), "" if Packs.picks(profile) == 1 else "s"]
		packs.add_theme_color_override("font_color", GameTheme.GOLD)
	packs.add_theme_font_size_override("font_size", 36)

	# Choosing what to make: hidden until asked for.
	var panel := PanelContainer.new()
	panel.visible = false
	root.add_child(panel)
	_new_panel = panel
	var form := VBoxContainer.new()
	panel.add_child(form)
	_new_title = Label.new()
	form.add_child(_new_title)
	var grid := GridContainer.new()
	grid.columns = 2
	form.add_child(grid)
	# 1. What kind of puzzle.
	_kind = _options(grid, "Puzzle")
	for pair: Array in [["collage", "Gem collage"], ["kit", "Diamond kit"]]:
		_kind.add_item(pair[1])
		_kind.set_item_metadata(_kind.item_count - 1, pair[0])
	_kind.item_selected.connect(func(_i: int) -> void: _fill_sources())
	# 2. Where its picture comes from: an unlocked picture type, or a photo.
	_source = _options(grid, "Picture")
	_source.item_selected.connect(func(_i: int) -> void: _refresh_new())
	# 3. Only the options that source has.
	_theme = _options(grid, "Colors")
	# Photo collages: the subject alone (when there is a clear one), or the whole photo.
	_subject = _options(grid, "Photo")
	for pair: Array in [["auto", "Subject if there's one"], ["on", "Subject only"], ["off", "Whole photo"]]:
		_subject.add_item(pair[1])
		_subject.set_item_metadata(_subject.item_count - 1, pair[0])
	# Photo kits: her gems, or the photo's own colors in that many.
	_kit_colors = _options(grid, "Drill colors")
	for pair: Array in [[0, "My gems"], [12, "Photo's own 12 colors"], [20, "Photo's own 20 colors"],
			[30, "Photo's own 30 colors"]]:
		_kit_colors.add_item(pair[1])
		_kit_colors.set_item_metadata(_kit_colors.item_count - 1, pair[0])
	# Kits: drills on the longer side.
	_kit_size = _options(grid, "Kit size")
	for size: String in PuzzleMaker.KIT_SIZES:
		_kit_size.add_item("%s (%d)" % [PuzzleMaker.KIT_SIZES[size], KitGenerator.LONG_SIDES[size]])
		_kit_size.set_item_metadata(_kit_size.item_count - 1, size)
	_kit_size.select(1)
	_about = Label.new()
	_about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_about.add_theme_font_size_override("font_size", GameTheme.SMALL_FONT_SIZE)
	_about.add_theme_color_override("font_color", GameTheme.TEXT_DIM)
	form.add_child(_about)
	var actions := HBoxContainer.new()
	form.add_child(actions)
	_start = _button(actions, "Start", _start_making)
	# A photo source starts from one of her photos or one taken right now.
	_choose_photo = _button(actions, "Choose photo…", func() -> void: _pick_photo(_photo_mode()))
	_take_photo_button = _button(actions, "Take photo…", func() -> void: _take_photo(_photo_mode()))
	for b: Button in [_start, _choose_photo, _take_photo_button]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(actions, "Cancel", func() -> void: _new_panel.visible = false)
	_photo_dialog = FileDialog.new()
	_photo_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_photo_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_photo_dialog.use_native_dialog = true
	_photo_dialog.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp ; Photos"])
	_photo_dialog.file_selected.connect(_on_photo_picked)
	add_child(_photo_dialog)

	var saved := Label.new()
	saved.text = "Your puzzles"
	saved.add_theme_color_override("font_color", GameTheme.GOLD)
	saved.add_theme_font_size_override("font_size", 48)
	root.add_child(saved)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 470
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	DragScroll.attach(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)

	# Settings: hidden until asked for, saved as soon as they change.
	_settings_panel = PanelContainer.new()
	_settings_panel.visible = false
	root.add_child(_settings_panel)
	var settings_grid := GridContainer.new()
	settings_grid.columns = 2
	_settings_panel.add_child(settings_grid)
	_setting(settings_grid, "Placing gems", "fill_animation", GemCatalog.ANIMATIONS, "animations")
	_setting(settings_grid, "Finale", "finale", GemCatalog.FINALES, "finales")

	var footer := HBoxContainer.new()
	root.add_child(footer)
	var settings_button := _small_button(footer, "Settings", func() -> void:
		if _settings_panel.visible:
			_settings_panel.hide()
		else:
			GameTheme.appear(_settings_panel)
			_menu_scroll.ensure_control_visible.call_deferred(_settings_panel))
	settings_button.add_theme_color_override("font_color", GameTheme.TEXT_DIM)
	var lab := _small_button(footer, "Generator lab (debug)", func() -> void: lab_requested.emit())
	lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lab.add_theme_color_override("font_color", GameTheme.TEXT_DIM)

	# Covers the menu while a puzzle is being made.
	_busy = ColorRect.new()
	(_busy as ColorRect).color = Color(GameTheme.BG, 0.85)
	_busy.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_busy.mouse_filter = Control.MOUSE_FILTER_STOP
	_busy.visible = false
	add_child(_busy)
	_busy_label = Label.new()
	_busy_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_busy_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_busy_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_busy_label.add_theme_color_override("font_color", GameTheme.GOLD)
	_busy.add_child(_busy_label)

	_camera = CameraCapture.new()
	_camera.captured.connect(func(photo: Image) -> void:
		if _task_id < 0:
			_start_photo(photo, _photo_kind))
	add_child(_camera)

	_refresh_list()


## Opens the panel for a new puzzle, or (with a puzzle's meta) for
## recoloring that one in another theme: then the kind and picture are
## fixed and only the colors can change.
func _open_new(recolor: Dictionary) -> void:
	_recolor = recolor
	var unlocks: Dictionary = profile["unlocks"]
	_theme.clear()
	for th: String in GemCatalog.unlocked_themes(unlocks):
		if not recolor.is_empty() and th == recolor["theme"]:
			continue
		_theme.add_item(GemCatalog.theme_name(th))
		_theme.set_item_metadata(_theme.item_count - 1, th)
	if _theme.item_count > 0:
		_theme.select(randi() % _theme.item_count)
	if not recolor.is_empty():
		_kind.select(1 if GemCatalog.PUZZLES.get(recolor["type"], {}).get("kit", false) else 0)
	_fill_sources()
	if not recolor.is_empty():
		for i in _source.item_count:
			if _source.get_item_metadata(i) == recolor["type"]:
				_source.select(i)
	_kind.disabled = not recolor.is_empty()
	_source.disabled = not recolor.is_empty()
	_new_title.text = "Recolor this picture" if not recolor.is_empty() else "A new puzzle"
	_refresh_new()
	GameTheme.appear(_new_panel)
	_menu_scroll.ensure_control_visible.call_deferred(_new_panel)


## The sources for the chosen kind: her unlocked picture types of that kind,
## then a photo (always there).
func _fill_sources() -> void:
	var kit := _is_kit()
	var previous: Variant = _source.get_item_metadata(_source.selected) if _source.selected >= 0 else null
	_source.clear()
	for t: String in GemCatalog.unlocked_puzzles(profile["unlocks"]):
		if GemCatalog.PUZZLES[t].get("kit", false) == kit:
			_source.add_item(GemCatalog.PUZZLES[t].get("source", GemCatalog.puzzle_name(t)))
			_source.set_item_metadata(_source.item_count - 1, t)
	_source.add_item("A photo")
	_source.set_item_metadata(_source.item_count - 1, "photo")
	_source.select(0)
	for i in _source.item_count:
		if _source.get_item_metadata(i) == previous:
			_source.select(i)
	_refresh_new()


## Shows only the options and buttons the chosen kind and source have.
func _refresh_new() -> void:
	var kit := _is_kit()
	var photo := _is_photo()
	var recoloring := not _recolor.is_empty()
	_show_row(_theme, not photo)
	_show_row(_subject, photo and not kit)
	_show_row(_kit_colors, photo and kit)
	_show_row(_kit_size, kit and not recoloring)
	_start.visible = not photo
	_choose_photo.visible = photo
	_take_photo_button.visible = photo
	_start.disabled = _theme.item_count == 0
	var type_id: String = _photo_mode() if photo else str(_source.get_item_metadata(maxi(_source.selected, 0)))
	var info: Dictionary = GemCatalog.PUZZLES.get(type_id, GemCatalog.PHOTO_MODES.get(type_id, {}))
	_about.text = info.get("about", "")


func _is_kit() -> bool:
	return _kind.get_item_metadata(maxi(_kind.selected, 0)) == "kit"


func _is_photo() -> bool:
	return _source.selected >= 0 and _source.get_item_metadata(_source.selected) == "photo"


## The photo puzzle (GemCatalog.PHOTO_MODES) for the chosen kind.
func _photo_mode() -> String:
	return "photo_kit" if _is_kit() else "photo_collage"


func _start_making() -> void:
	if _task_id >= 0 or _source.selected < 0 or _theme.selected < 0 or _is_photo():
		return
	var type_id: String = _source.get_item_metadata(_source.selected)
	var theme_id: String = _theme.get_item_metadata(_theme.selected)
	_request = PuzzleMaker.new_request(type_id, theme_id)
	_request["kit_size"] = _kit_size.get_item_metadata(maxi(_kit_size.selected, 0))
	if not _recolor.is_empty():
		# The same picture: same seeds, new colors.
		_request["type"] = _recolor["type"]
		_request["seed"] = _recolor["seed"]
		_request["pattern_seed"] = _recolor["pattern_seed"]
		_request["kit_size"] = _recolor.get("kit_size", _request["kit_size"])
	_new_panel.visible = false
	_busy_label.text = "Making your %s…" % GemCatalog.puzzle_name(_request["type"]).to_lower()
	_busy.visible = true
	var unlocks: Dictionary = (profile["unlocks"] as Dictionary).duplicate(true)
	_task_id = WorkerThreadPool.add_task(_make.bind(_request.duplicate(), unlocks), false, "make puzzle")


func _pick_photo(kind: String) -> void:
	_photo_kind = kind
	_photo_dialog.popup_centered_ratio(0.9)


func _take_photo(kind: String) -> void:
	_photo_kind = kind
	_camera.open()


## A photo was picked: make its puzzle, shrunk first (big phone photos
## would only slow it down).
func _on_photo_picked(path: String) -> void:
	if _task_id >= 0:
		return
	var photo := PhotoLoader.open(path)
	if photo == null or photo.is_empty():
		_busy_label.text = "Couldn't open that photo."
		_busy.visible = true
		get_tree().create_timer(1.5).timeout.connect(func() -> void: _busy.visible = false)
		return
	_start_photo(photo, _photo_kind)


## Makes a puzzle of `kind` (see GemCatalog.PHOTO_MODES) from `photo`.
func _start_photo(photo: Image, kind: String) -> void:
	var longest := maxi(photo.get_width(), photo.get_height())
	if longest > PuzzleMaker.PHOTO_MAX:
		var k := float(PuzzleMaker.PHOTO_MAX) / longest
		photo.resize(maxi(1, int(photo.get_width() * k)), maxi(1, int(photo.get_height() * k)), Image.INTERPOLATE_LANCZOS)
	_request = PuzzleMaker.new_request(kind, "")
	_request["photo"] = photo
	_request["subject"] = _subject.get_item_metadata(maxi(_subject.selected, 0))
	_request["kit_colors"] = _kit_colors.get_item_metadata(maxi(_kit_colors.selected, 0))
	_request["kit_size"] = _kit_size.get_item_metadata(maxi(_kit_size.selected, 0))
	_new_panel.visible = false
	_busy_label.text = "Making your %s…" % GemCatalog.puzzle_name(kind).to_lower()
	_busy.visible = true
	var unlocks: Dictionary = (profile["unlocks"] as Dictionary).duplicate(true)
	_task_id = WorkerThreadPool.add_task(_make.bind(_request, unlocks), false, "make photo puzzle")


## Runs on a worker thread; touches no nodes.
func _make(request: Dictionary, unlocks: Dictionary) -> void:
	_result = PuzzleMaker.make(request, unlocks)


func _process(_delta: float) -> void:
	if _task_id < 0 or not WorkerThreadPool.is_task_completed(_task_id):
		return
	WorkerThreadPool.wait_for_task_completion(_task_id)
	_task_id = -1
	var picture := _result
	_result = {}
	if picture.is_empty() or picture.get("slots", []).is_empty():
		_busy_label.text = "That one didn't work out. Try again?"
		get_tree().create_timer(1.5).timeout.connect(func() -> void: _busy.visible = false)
		return
	var meta := SaveStore.add_puzzle(profile, picture)
	SaveStore.save_thumbnail(meta["id"], Thumbnail.render(picture, PackedByteArray()))
	play_requested.emit(meta["id"])


## Android's back button: leaves the panel, else the game.
func go_back() -> void:
	if _task_id >= 0:
		return
	if _camera.visible:
		_camera.close()
	elif _new_panel.visible or _settings_panel.visible:
		_new_panel.visible = false
		_settings_panel.visible = false
	else:
		get_tree().quit()


func _refresh_list() -> void:
	for child in _list.get_children():
		child.queue_free()
	var puzzles: Array = profile["puzzles"]
	if puzzles.is_empty():
		var welcome := PanelContainer.new()
		welcome.custom_minimum_size.y = 310
		_list.add_child(welcome)
		var box := VBoxContainer.new()
		box.alignment = BoxContainer.ALIGNMENT_CENTER
		welcome.add_child(box)
		var art := TextureRect.new()
		art.texture = GameTheme.icon("picture")
		art.custom_minimum_size.y = 100
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		box.add_child(art)
		var none := Label.new()
		none.text = "Your next beautiful thing starts here."
		none.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		none.add_theme_font_size_override("font_size", 36)
		box.add_child(none)
		var tip := Label.new()
		tip.text = "Start a puzzle above. Come back whenever you like."
		tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tip.add_theme_font_size_override("font_size", 28)
		tip.add_theme_color_override("font_color", GameTheme.TEXT_DIM)
		box.add_child(tip)
		return
	for meta: Dictionary in puzzles:
		_list.add_child(_card(meta))


func _card(meta: Dictionary) -> Control:
	var card := PanelContainer.new()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	card.add_child(row)
	var thumb := TextureRect.new()
	thumb.custom_minimum_size = Vector2(THUMB_PX, THUMB_PX)
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	thumb.texture = SaveStore.load_thumbnail(meta["id"])
	row.add_child(thumb)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	var heading := Label.new()
	heading.text = GemCatalog.puzzle_name(meta["type"])
	info.add_child(heading)
	var detail := Label.new()
	var total := maxi(1, int(meta["total"]))
	var state := "Finished" if meta["done"] else "%d%% placed" % int(100.0 * meta["filled"] / total)
	var colors: String = "From your photo" if GemCatalog.PHOTO_MODES.has(meta["type"]) else GemCatalog.theme_name(
			meta["theme"])
	detail.text = "%s · %s · %s" % [colors, state, _ago(meta["updated"])]
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_theme_font_size_override("font_size", GameTheme.SMALL_FONT_SIZE)
	detail.add_theme_color_override("font_color", GameTheme.TEXT_DIM)
	info.add_child(detail)
	var buttons := HFlowContainer.new()
	info.add_child(buttons)
	var id: String = meta["id"]
	_small_button(buttons, "View" if meta["done"] else "Continue", func() -> void: play_requested.emit(id))
	var restart := _small_button(buttons, "Restart", Callable())
	restart.pressed.connect(_confirmed.bind(restart, func() -> void: _restart(meta)))
	# Photo puzzles take their colors from the photo, so they don't recolor.
	if not GemCatalog.PHOTO_MODES.has(meta["type"]):
		_small_button(buttons, "Recolor", func() -> void: _open_new(meta))
	var delete := _small_button(buttons, "Delete", Callable())
	delete.pressed.connect(_confirmed.bind(delete, func() -> void:
		SaveStore.delete_puzzle(profile, id)
		_refresh_list()))
	return card


## A settings row choosing `key` among the unlocked entries of `catalog`
## (unlock list `unlocked`), saved as soon as it changes.
func _setting(parent: Control, label: String, key: String, catalog: Dictionary, unlocked: String) -> void:
	var ob := _options(parent, label)
	var settings: Dictionary = profile["settings"]
	for id: String in catalog:
		if id in profile["unlocks"].get(unlocked, []):
			ob.add_item(catalog[id]["name"])
			ob.set_item_metadata(ob.item_count - 1, id)
			if id == settings.get(key, ""):
				ob.select(ob.item_count - 1)
	ob.item_selected.connect(func(i: int) -> void:
		settings[key] = ob.get_item_metadata(i)
		SaveStore.save_profile(profile))


## Runs `action` on a second tap within CONFIRM_MS; the first asks "Sure?".
func _confirmed(b: Button, action: Callable) -> void:
	var now := Time.get_ticks_msec()
	if b.has_meta("asked") and now - int(b.get_meta("asked")) < CONFIRM_MS:
		action.call()
		return
	var label := b.text
	b.set_meta("asked", now)
	b.text = "Sure?"
	get_tree().create_timer(CONFIRM_MS / 1000.0).timeout.connect(func() -> void:
		if is_instance_valid(b):
			b.text = label
			b.remove_meta("asked"))


func _restart(meta: Dictionary) -> void:
	var id: String = meta["id"]
	SaveStore.save_progress(id, PackedByteArray())
	meta["filled"] = 0
	meta["done"] = false
	meta["updated"] = int(Time.get_unix_time_from_system())
	SaveStore.save_profile(profile)
	var picture := SaveStore.load_picture(id)
	if not picture.is_empty():
		SaveStore.save_thumbnail(id, Thumbnail.render(picture, PackedByteArray()))
	_refresh_list()


static func _ago(unix: int) -> String:
	var s := int(Time.get_unix_time_from_system()) - unix
	if s < 90:
		return "just now"
	if s < 3600 * 1.5:
		return "%d min ago" % (s / 60)
	if s < 86400 * 1.5:
		return "%d h ago" % roundi(s / 3600.0)
	return "%d days ago" % roundi(s / 86400.0)


## A labeled row in a two-column grid; _show_row shows or hides both halves.
func _options(parent: Control, label: String) -> OptionButton:
	var l := Label.new()
	l.text = label
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	parent.add_child(l)
	var ob := OptionButton.new()
	ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ob.custom_minimum_size.y = GameTheme.TAP_HEIGHT
	ob.fit_to_longest_item = false
	ob.set_meta("label", l)
	parent.add_child(ob)
	return ob


func _show_row(c: Control, on: bool) -> void:
	c.visible = on
	(c.get_meta("label") as Control).visible = on


func _button(parent: Control, text: String, action: Callable) -> Button:
	var b := GameTheme.button(text)
	b.custom_minimum_size.y = GameTheme.TAP_HEIGHT
	if action.is_valid():
		b.pressed.connect(action)
	parent.add_child(b)
	return b


func _small_button(parent: Control, text: String, action: Callable) -> Button:
	var b := _button(parent, text, action)
	b.add_theme_font_size_override("font_size", GameTheme.SMALL_FONT_SIZE)
	return b
