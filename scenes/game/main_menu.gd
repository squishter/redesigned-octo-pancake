extends Control
## The game's menu: start a new puzzle (an unlocked type in an unlocked
## color theme), or pick up a saved one. Every puzzle keeps its own save, so
## a new one never overwrites one in progress. Each saved puzzle can be
## continued, restarted, recolored (the same picture made again in another
## unlocked theme, as a new puzzle beside it) or deleted. Collection & packs
## shows what she has and opens packs for more (with her coins and free
## picks shown beside it). Settings (how placed gems go in, the finale) and
## the generator lab, a debug mode, are at the bottom.

signal play_requested(id: String)
signal lab_requested
signal collection_requested

const LabTheme := preload("res://scenes/dev/lab_theme.gd")
const THUMB_PX := 220
## Restart and Delete ask again; a second tap within this long confirms.
const CONFIRM_MS := 3000

## The player's profile (SaveStore), shared with the app; set before adding.
var profile: Dictionary = {}

var _list: VBoxContainer
var _new_panel: Control
var _settings_panel: Control
var _type: OptionButton
var _theme: OptionButton
var _start: Button
var _new_title: Label
var _photo_row: Control
var _photo_dialog: FileDialog
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
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 32)
	add_child(root)
	SafeArea.apply(root)

	var title := Label.new()
	title.text = "Paint With Gems"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 84)
	title.add_theme_color_override("font_color", LabTheme.GOLD)
	root.add_child(title)

	var new_button := _button(root, "New puzzle", func() -> void: _open_new({}))
	new_button.custom_minimum_size.y = LabTheme.TAP_HEIGHT * 1.3

	var wallet := HBoxContainer.new()
	root.add_child(wallet)
	var coins := Label.new()
	coins.text = "%d coins · %d free pick%s" % [Packs.coins(profile), Packs.picks(profile),
			"" if Packs.picks(profile) == 1 else "s"]
	coins.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	coins.add_theme_color_override("font_color", LabTheme.GOLD)
	wallet.add_child(coins)
	var packs := _button(wallet, "Collection & packs", func() -> void: collection_requested.emit())
	if Packs.picks(profile) > 0:
		packs.text = "Collection & packs (%d free!)" % Packs.picks(profile)
		packs.add_theme_color_override("font_color", LabTheme.GOLD)

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
	_type = _options(grid, "Picture")
	_theme = _options(grid, "Colors")
	var actions := HBoxContainer.new()
	form.add_child(actions)
	_start = _button(actions, "Start", _start_making)
	_start.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(actions, "Cancel", func() -> void: _new_panel.visible = false)
	# Or from one of her photos: colors come from the photo (snapped to her
	# gem colors), so there's no theme to pick.
	_photo_row = HBoxContainer.new()
	form.add_child(_photo_row)
	for kind: String in GemCatalog.PHOTO_MODES:
		var b := _button(_photo_row, GemCatalog.PHOTO_MODES[kind]["name"] + "…", func() -> void: _pick_photo(kind))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_photo_dialog = FileDialog.new()
	_photo_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_photo_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_photo_dialog.use_native_dialog = true
	_photo_dialog.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp ; Photos"])
	_photo_dialog.file_selected.connect(_on_photo_picked)
	add_child(_photo_dialog)

	var saved := Label.new()
	saved.text = "Your puzzles"
	saved.add_theme_color_override("font_color", LabTheme.TEXT_DIM)
	root.add_child(saved)
	var scroll := ScrollContainer.new()
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
		_settings_panel.visible = not _settings_panel.visible)
	settings_button.add_theme_color_override("font_color", LabTheme.TEXT_DIM)
	var lab := _small_button(footer, "Generator lab (debug)", func() -> void: lab_requested.emit())
	lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lab.add_theme_color_override("font_color", LabTheme.TEXT_DIM)

	# Covers the menu while a puzzle is being made.
	_busy = ColorRect.new()
	(_busy as ColorRect).color = Color(LabTheme.BG, 0.85)
	_busy.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_busy.mouse_filter = Control.MOUSE_FILTER_STOP
	_busy.visible = false
	add_child(_busy)
	_busy_label = Label.new()
	_busy_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_busy_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_busy_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_busy_label.add_theme_color_override("font_color", LabTheme.GOLD)
	_busy.add_child(_busy_label)

	_refresh_list()


## Opens the panel for a new puzzle, or (with a puzzle's meta) for
## recoloring that one in another theme.
func _open_new(recolor: Dictionary) -> void:
	_recolor = recolor
	var unlocks: Dictionary = profile["unlocks"]
	_type.clear()
	for t: String in GemCatalog.unlocked_puzzles(unlocks):
		_type.add_item(GemCatalog.puzzle_name(t))
		_type.set_item_metadata(_type.item_count - 1, t)
	_theme.clear()
	for th: String in GemCatalog.unlocked_themes(unlocks):
		if not recolor.is_empty() and th == recolor["theme"]:
			continue
		_theme.add_item(GemCatalog.theme_name(th))
		_theme.set_item_metadata(_theme.item_count - 1, th)
	if _theme.item_count > 0:
		_theme.select(randi() % _theme.item_count)
	_type.disabled = not recolor.is_empty()
	if not recolor.is_empty():
		for i in _type.item_count:
			if _type.get_item_metadata(i) == recolor["type"]:
				_type.select(i)
	_new_title.text = "Recolor this picture" if not recolor.is_empty() else "A new puzzle"
	_photo_row.visible = recolor.is_empty()
	_start.disabled = _type.item_count == 0 or _theme.item_count == 0
	_new_panel.visible = true


func _start_making() -> void:
	if _task_id >= 0 or _type.selected < 0 or _theme.selected < 0:
		return
	var type_id: String = _type.get_item_metadata(_type.selected)
	var theme_id: String = _theme.get_item_metadata(_theme.selected)
	_request = PuzzleMaker.new_request(type_id, theme_id)
	if not _recolor.is_empty():
		# The same picture: same seeds, new colors.
		_request["type"] = _recolor["type"]
		_request["seed"] = _recolor["seed"]
		_request["pattern_seed"] = _recolor["pattern_seed"]
	_new_panel.visible = false
	_busy_label.text = "Making your %s…" % GemCatalog.puzzle_name(_request["type"]).to_lower()
	_busy.visible = true
	var unlocks: Dictionary = (profile["unlocks"] as Dictionary).duplicate(true)
	_task_id = WorkerThreadPool.add_task(_make.bind(_request.duplicate(), unlocks), false, "make puzzle")


func _pick_photo(kind: String) -> void:
	_photo_kind = kind
	_photo_dialog.popup_centered_ratio(0.9)


## A photo was picked: make its puzzle, shrunk first (big phone photos
## would only slow it down).
func _on_photo_picked(path: String) -> void:
	if _task_id >= 0:
		return
	var photo := Image.load_from_file(path)
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
	if _new_panel.visible or _settings_panel.visible:
		_new_panel.visible = false
		_settings_panel.visible = false
	else:
		get_tree().quit()


func _refresh_list() -> void:
	for child in _list.get_children():
		child.queue_free()
	var puzzles: Array = profile["puzzles"]
	if puzzles.is_empty():
		var none := Label.new()
		none.text = "No puzzles yet. Start one above!"
		none.add_theme_color_override("font_color", LabTheme.TEXT_DIM)
		_list.add_child(none)
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
	detail.add_theme_font_size_override("font_size", LabTheme.SMALL_FONT_SIZE)
	detail.add_theme_color_override("font_color", LabTheme.TEXT_DIM)
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


func _options(parent: Control, label: String) -> OptionButton:
	var l := Label.new()
	l.text = label
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	parent.add_child(l)
	var ob := OptionButton.new()
	ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ob.custom_minimum_size.y = LabTheme.TAP_HEIGHT
	ob.fit_to_longest_item = false
	parent.add_child(ob)
	return ob


func _button(parent: Control, text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size.y = LabTheme.TAP_HEIGHT
	if action.is_valid():
		b.pressed.connect(action)
	parent.add_child(b)
	return b


func _small_button(parent: Control, text: String, action: Callable) -> Button:
	var b := _button(parent, text, action)
	b.add_theme_font_size_override("font_size", LabTheme.SMALL_FONT_SIZE)
	return b
