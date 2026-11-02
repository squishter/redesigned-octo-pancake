class_name ColorStoryEditor
extends GameDialog
## Makes or changes one of her own color stories (CustomThemes): a name and
## CustomThemes.MIN_COLORS to GemCatalog.MAX_THEME_COLORS of the gem colors she has, in the order
## she taps them (their numbers show on the swatches). Tapping a picked
## color again takes it out. An existing story can also be deleted (a
## second tap confirms).

## A story was saved (its id), or deleted ("").
signal saved(theme_id: String)

const CONFIRM_MS := 3000

## The player's profile (SaveStore); set before opening.
var profile: Dictionary = {}

var _name: LineEdit
var _strip: GridContainer
var _search: LineEdit
var _hue: OptionButton
var _empty: Label
var _clear: Button
var _reverse: Button
var _groups := {}
var _count: Label
var _note: Label
var _palette: VBoxContainer
var _save: Button
var _delete: Button
var _swatches := {}  # gem id -> Button
var _picked: Array = []
var _editing := ""
var _delete_asked := -1


func _init() -> void:
	super("Create a color story", "Bring your favorite gem colors together.", "palette")
	preferred_height = 1980
	subtitle_label.hide()
	pinned.show()
	pinned.add_theme_constant_override("separation", 8)
	body.add_theme_constant_override("separation", 20)
	actions.add_theme_constant_override("separation", 12)
	body.add_child(UI.label("NAME", 26, GameTheme.MINT))
	_name = LineEdit.new()
	_name.max_length = CustomThemes.MAX_NAME
	_name.placeholder_text = "My colors"
	_name.custom_minimum_size.y = GameTheme.TAP_HEIGHT
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name.add_theme_font_size_override("font_size", 36)
	body.add_child(_name)
	body.add_child(UI.label("Optional. Leave blank for an automatic name.", 25, GameTheme.TEXT_DIM))
	var selection := UI.panel(false, 16)
	pinned.add_child(selection)
	var selected := VBoxContainer.new()
	selected.add_theme_constant_override("separation", 10)
	selection.add_child(selected)
	_count = UI.label("", 25, GameTheme.MINT)
	selected.add_child(_count)
	_strip = GridContainer.new()
	_strip.columns = 4
	_strip.add_theme_constant_override("h_separation", 8)
	_strip.add_theme_constant_override("v_separation", 8)
	selected.add_child(_strip)
	var tools := HBoxContainer.new()
	selected.add_child(tools)
	_reverse = _quiet(tools, "Reverse order", _reverse_colors)
	_clear = _quiet(tools, "Clear colors", _clear_colors)
	for button: Button in [_reverse, _clear]:
		button.custom_minimum_size.y = 80
	_reverse.icon = GameTheme.icon("replay")
	_clear.icon = GameTheme.icon("close")
	_note = UI.label("", 25, GameTheme.TEXT_DIM)
	# Reserve two lines even when the status changes between one and two lines.
	_note.custom_minimum_size.y = 80
	_note.max_lines_visible = 2
	pinned.add_child(_note)
	body.add_child(UI.label("ADD FROM YOUR GEM COLORS", 26, GameTheme.MINT))
	_search = LineEdit.new()
	_search.placeholder_text = "Search colors by name"
	_search.clear_button_enabled = true
	_search.custom_minimum_size.y = GameTheme.TAP_HEIGHT
	_search.add_theme_font_size_override("font_size", 30)
	_search.text_changed.connect(func(_text: String) -> void: _filter_palette())
	body.add_child(_search)
	_hue = OptionButton.new()
	_hue.custom_minimum_size.y = GameTheme.TAP_HEIGHT
	_hue.add_theme_font_size_override("font_size", 30)
	_hue.add_item("All color families")
	for hue: String in GemCatalog.HUE_ORDER:
		_hue.add_item(hue.capitalize())
	_hue.item_selected.connect(func(_index: int) -> void: _filter_palette())
	body.add_child(_hue)
	_empty = UI.label("", 28, GameTheme.TEXT_DIM)
	body.add_child(_empty)
	_palette = VBoxContainer.new()
	_palette.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(_palette)
	_save = GameTheme.button("Save color story", true)
	_save.custom_minimum_size.y = 96
	_save.theme_type_variation = "PrimaryButton"
	_save.pressed.connect(_on_save)
	actions.add_child(_save)
	var row := HBoxContainer.new()
	actions.add_child(row)
	_delete = _quiet(row, "Delete story", _on_delete)
	_quiet(row, "Cancel", close)


## Opens the editor for a new story, or (with `theme_id`) to change that one.
func edit(theme_id := "") -> void:
	var existing := CustomThemes.find(profile, theme_id)
	_editing = theme_id if not existing.is_empty() else ""
	_picked = (existing.get("gems", []) as Array).duplicate()
	_name.text = existing.get("name", "")
	title_label.text = "Edit color story" if _editing != "" else "Create a color story"
	_delete.visible = _editing != ""
	_delete.text = "Delete story"
	_delete_asked = -1
	_note.text = ""
	_search.text = ""
	_hue.select(0)
	_build_palette()
	_refresh()
	body_scroll.scroll_vertical = 0
	open()


## Her unlocked colors, hue by hue, as swatches to tap.
func _build_palette() -> void:
	for child in _palette.get_children():
		_palette.remove_child(child)
		child.queue_free()
	_swatches.clear()
	_groups.clear()
	var have: Array = profile.get("unlocks", {}).get("colors", [])
	var colors := GemCatalog.all_colors()
	for hue: String in GemCatalog.HUE_ORDER:
		var of_hue := colors.filter(func(g: Dictionary) -> bool: return g["hue"] == hue and g["id"] in have)
		if of_hue.is_empty():
			continue
		var group := VBoxContainer.new()
		group.add_theme_constant_override("separation", 12)
		_palette.add_child(group)
		_groups[hue] = group
		group.add_child(UI.label(hue.capitalize(), 28, GameTheme.GOLD))
		var flow := ColorStorySwatches.flow()
		group.add_child(flow)
		for g: Dictionary in of_hue:
			var gem: String = g["id"]
			var swatch := ColorStorySwatches.tile(gem, true)
			swatch.toggle_mode = true
			swatch.pressed.connect(func() -> void: _toggle(gem))
			flow.add_child(swatch)
			_swatches[gem] = swatch
	_filter_palette()


func _filter_palette() -> void:
	var query := _search.text.strip_edges().to_lower()
	var family := "" if _hue.selected == 0 else str(GemCatalog.HUE_ORDER[_hue.selected - 1])
	var matches := 0
	for hue: String in _groups:
		var group: VBoxContainer = _groups[hue]
		var found := false
		for b: Button in group.get_child(1).get_children():
			b.visible = (family == "" or family == hue) and (query == "" or query in b.tooltip_text.to_lower())
			found = found or b.visible
			if b.visible:
				matches += 1
		group.visible = found
	_empty.visible = matches == 0
	_empty.text = ("Find more gem colors in Collection & packs." if _swatches.is_empty()
		else "No colors match. Try another name or color family.")
	contain_focus.call_deferred()


func _clear_colors() -> void:
	_picked.clear()
	_note.text = ""
	_refresh()


func _reverse_colors() -> void:
	_picked.reverse()
	_refresh()


func _toggle(gem: String) -> void:
	if gem in _picked:
		_picked.erase(gem)
	elif _picked.size() < GemCatalog.MAX_THEME_COLORS:
		_picked.append(gem)
	_refresh()


## Swatches, the strip of picked colors, the count and whether it can be saved.
func _refresh() -> void:
	var full := _picked.size() >= GemCatalog.MAX_THEME_COLORS
	for gem: String in _swatches:
		var b: Button = _swatches[gem]
		var at := _picked.find(gem)
		b.set_pressed_no_signal(at >= 0)
		(b.find_child("Order", true, false) as Label).text = str(at + 1) if at >= 0 else ""
		# Keep every swatch tappable so a tap at the limit explains how to make room.
		b.modulate.a = 0.5 if full and at < 0 else 1.0
	for child in _strip.get_children():
		_strip.remove_child(child)
		child.queue_free()
	for i in GemCatalog.MAX_THEME_COLORS:
		if i >= _picked.size():
			_strip.add_child(ColorStorySwatches.empty_slot(i + 1))
			continue
		var gem: String = _picked[i]
		var chip := ColorStorySwatches.tile(gem, true, true)
		(chip.find_child("Order", true, false) as Label).text = "%d  ×" % (i + 1)
		chip.tooltip_text = "Tap to remove " + GemCatalog.color_name(gem)
		chip.pressed.connect(func() -> void: _toggle(gem))
		_strip.add_child(chip)
	_count.text = "%d / %d COLORS  ·  MINIMUM %d" % [_picked.size(), GemCatalog.MAX_THEME_COLORS, CustomThemes.MIN_COLORS]
	_clear.disabled = _picked.is_empty()
	_reverse.disabled = _picked.size() < 2
	var valid := CustomThemes.valid_gems(_picked) and _picked.all(func(g: String) -> bool: return _swatches.has(g))
	var room := _editing != "" or CustomThemes.list(profile).size() < CustomThemes.MAX_THEMES
	_save.disabled = not valid or not room
	if not room:
		_note.text = "You have %d color stories. Edit or delete one to make room." % CustomThemes.MAX_THEMES
	elif not valid:
		_note.text = "Choose %d–%d of your gem colors to save this story." % [CustomThemes.MIN_COLORS, GemCatalog.MAX_THEME_COLORS]
	elif full:
		_note.text = "All %d colors selected. Remove a color before adding another." % GemCatalog.MAX_THEME_COLORS
	else:
		_note.text = "Ready to save. You can add %d more colors." % (GemCatalog.MAX_THEME_COLORS - _picked.size())
	_note.tooltip_text = _note.text
	contain_focus.call_deferred()


func _on_save() -> void:
	_refresh()
	if _save.disabled:
		return
	var id := CustomThemes.save(profile, _name.text, _picked, _editing)
	if id == "":
		_note.text = "That story couldn't be saved. You have %d already." % CustomThemes.list(profile).size()
		return
	SaveStore.save_profile(profile)
	close()
	saved.emit(id)


## Deletes the story being changed, on a second tap within CONFIRM_MS.
func _on_delete() -> void:
	var now := Time.get_ticks_msec()
	if _delete_asked >= 0 and now - _delete_asked < CONFIRM_MS:
		CustomThemes.remove(profile, _editing)
		SaveStore.save_profile(profile)
		close()
		saved.emit("")
		return
	_delete_asked = now
	_delete.text = "Confirm delete"
	get_tree().create_timer(CONFIRM_MS / 1000.0).timeout.connect(func() -> void:
		if is_instance_valid(_delete):
			_delete.text = "Delete story"
			_delete_asked = -1)


func _quiet(parent: Control, text: String, action: Callable) -> Button:
	var b := GameTheme.button(text)
	b.custom_minimum_size.y = 96
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", 28)
	b.add_theme_constant_override("icon_max_width", 32)
	b.theme_type_variation = "QuietButton"
	b.pressed.connect(action)
	parent.add_child(b)
	return b
