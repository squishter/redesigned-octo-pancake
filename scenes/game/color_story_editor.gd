class_name ColorStoryEditor
extends GameDialog
## Makes or changes one of her own color stories (CustomThemes): a name and
## 2 to GemCatalog.MAX_THEME_COLORS of the gem colors she has, in the order
## she taps them (their numbers show on the swatches). Tapping a picked
## color again takes it out. An existing story can also be deleted (a
## second tap confirms).

## A story was saved (its id), or deleted ("").
signal saved(theme_id: String)

const SWATCH := 92.0
const CONFIRM_MS := 3000

## The player's profile (SaveStore); set before opening.
var profile: Dictionary = {}

var _name: LineEdit
var _strip: HBoxContainer
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
	super("Your color story", "Pick the gem colors you love, in the order you like them.", "palette")
	preferred_height = 1900
	body.add_child(UI.label("NAME", 26, GameTheme.MINT))
	_name = LineEdit.new()
	_name.max_length = CustomThemes.MAX_NAME
	_name.placeholder_text = "My colors"
	_name.custom_minimum_size.y = GameTheme.TAP_HEIGHT
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name.add_theme_font_size_override("font_size", 36)
	body.add_child(_name)
	_count = UI.label("", 26, GameTheme.MINT)
	body.add_child(_count)
	_strip = HBoxContainer.new()
	_strip.add_theme_constant_override("separation", 8)
	_strip.custom_minimum_size.y = 56
	body.add_child(_strip)
	_note = UI.label("", 27, GameTheme.TEXT_DIM)
	body.add_child(_note)
	_palette = VBoxContainer.new()
	_palette.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(_palette)
	_save = GameTheme.button("Save color story", true)
	_save.custom_minimum_size.y = GameTheme.TAP_HEIGHT
	_save.theme_type_variation = "PrimaryButton"
	_save.pressed.connect(_on_save)
	actions.add_child(_save)
	var row := HBoxContainer.new()
	actions.add_child(row)
	_delete = _quiet(row, "Delete", _on_delete)
	_quiet(row, "Cancel", close)


## Opens the editor for a new story, or (with `theme_id`) to change that one.
func edit(theme_id := "") -> void:
	var existing := CustomThemes.find(profile, theme_id)
	_editing = theme_id if not existing.is_empty() else ""
	_picked = (existing.get("gems", []) as Array).duplicate()
	_name.text = existing.get("name", "")
	title_label.text = "Change your color story" if _editing != "" else "Your color story"
	_delete.visible = _editing != ""
	_delete.text = "Delete"
	_delete_asked = -1
	_note.text = ""
	_build_palette()
	_refresh()
	open()


## Her unlocked colors, hue by hue, as swatches to tap.
func _build_palette() -> void:
	for child in _palette.get_children():
		_palette.remove_child(child)
		child.queue_free()
	_swatches.clear()
	var have: Array = profile.get("unlocks", {}).get("colors", [])
	var colors := GemCatalog.all_colors()
	for hue: String in GemCatalog.HUE_ORDER:
		var of_hue := colors.filter(func(g: Dictionary) -> bool: return g["hue"] == hue and g["id"] in have)
		if of_hue.is_empty():
			continue
		_palette.add_child(UI.label(hue.capitalize(), 28, GameTheme.GOLD))
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 12)
		flow.add_theme_constant_override("v_separation", 12)
		_palette.add_child(flow)
		for g: Dictionary in of_hue:
			var swatch := _swatch(g["id"], g["color"], g["name"])
			flow.add_child(swatch)
			_swatches[g["id"]] = swatch


func _swatch(gem: String, color: Color, title: String) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(SWATCH, SWATCH)
	b.tooltip_text = title
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_size_override("font_size", 38)
	var ink := Color("#1b1f2e") if color.get_luminance() > 0.55 else Color.WHITE
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(state, ink)
	b.set_meta("color", color)
	b.pressed.connect(func() -> void: _toggle(gem))
	return b


func _toggle(gem: String) -> void:
	if gem in _picked:
		_picked.erase(gem)
		_note.text = ""
	elif _picked.size() >= GemCatalog.MAX_THEME_COLORS:
		_note.text = "A color story holds up to %d colors. Tap one you picked to take it out." % GemCatalog.MAX_THEME_COLORS
	else:
		_picked.append(gem)
		_note.text = ""
	_refresh()


## Swatches, the strip of picked colors, the count and whether it can be saved.
func _refresh() -> void:
	for gem: String in _swatches:
		var b: Button = _swatches[gem]
		var at := _picked.find(gem)
		b.text = str(at + 1) if at >= 0 else ""
		for state: String in ["normal", "hover", "pressed", "focus"]:
			var box := StyleBoxFlat.new()
			box.bg_color = b.get_meta("color")
			box.set_corner_radius_all(18)
			box.set_border_width_all(6 if at >= 0 else (3 if state in ["hover", "focus"] else 0))
			box.border_color = GameTheme.GOLD if at >= 0 else GameTheme.TEXT_DIM
			if state == "focus" and at < 0:
				box.draw_center = false
			b.add_theme_stylebox_override(state, box)
	for child in _strip.get_children():
		_strip.remove_child(child)
		child.queue_free()
	for gem: String in _picked:
		var chip := ColorRect.new()
		chip.color = GemCatalog.color_of(gem)
		chip.custom_minimum_size = Vector2(52, 52)
		chip.tooltip_text = GemCatalog.color_name(gem)
		_strip.add_child(chip)
	_count.text = "YOUR COLORS  ·  %d / %d" % [_picked.size(), GemCatalog.MAX_THEME_COLORS]
	var enough := _picked.size() >= CustomThemes.MIN_COLORS
	_save.disabled = not enough
	if not enough and _note.text == "":
		_note.text = "Pick at least %d colors." % CustomThemes.MIN_COLORS


func _on_save() -> void:
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
	_delete.text = "Sure?"
	get_tree().create_timer(CONFIRM_MS / 1000.0).timeout.connect(func() -> void:
		if is_instance_valid(_delete):
			_delete.text = "Delete"
			_delete_asked = -1)


func _quiet(parent: Control, text: String, action: Callable) -> Button:
	var b := GameTheme.button(text)
	b.custom_minimum_size.y = GameTheme.TAP_HEIGHT
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", GameTheme.SMALL_FONT_SIZE)
	b.theme_type_variation = "QuietButton"
	b.pressed.connect(action)
	parent.add_child(b)
	return b
