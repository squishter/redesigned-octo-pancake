extends RefCounted
## The player's jewel-box theme. The generator lab keeps its own theme.

const BaseTheme := preload("res://scenes/dev/lab_theme.gd")
const FONT_SIZE := 40
const SMALL_FONT_SIZE := 30
const TAP_HEIGHT := 112
const BG := Color("#14182b")
const PANEL := Color("#222940")
const FIELD := Color("#303952")
const FIELD_PRESSED := Color("#43526b")
const GOLD := Color("#f2ce88")
const TEXT := Color("#fff5e7")
const TEXT_DIM := Color("#b7c4d5")
const MINT := Color("#91dfd0")

static var _icons: Dictionary = {}


static func build() -> Theme:
	var theme := BaseTheme.build()
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var box := _button_box(false)
		if state == "hover":
			box.modulate_color = Color(1.16, 1.16, 1.12)
		elif state in ["pressed", "hover_pressed"]:
			box.modulate_color = Color(0.78, 0.85, 0.94)
		elif state == "disabled":
			box.modulate_color = Color(0.6, 0.65, 0.75, 0.48)
		theme.set_stylebox(state, "Button", box)
		theme.set_stylebox(state, "PrimaryButton", _button_box(true, box.modulate_color))
	theme.set_type_variation("PrimaryButton", "Button")
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		theme.set_color(state, "Button", TEXT)
		theme.set_color(state, "PrimaryButton", Color("#302638"))
	for state: String in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color"]:
		theme.set_color(state, "PrimaryButton", Color("#554258"))
	theme.set_color("font_disabled_color", "Button", Color("#8090a6"))
	theme.set_constant("h_separation", "Button", 18)
	theme.set_constant("icon_max_width", "Button", 54)
	theme.set_color("icon_disabled_color", "Button", Color(0.6, 0.6, 0.6, 0.5))
	var focus := StyleBoxFlat.new()
	focus.bg_color = Color.TRANSPARENT
	focus.border_color = MINT
	focus.set_border_width_all(4)
	focus.set_corner_radius_all(28)
	focus.expand_margin_left = 5
	focus.expand_margin_right = 5
	focus.expand_margin_top = 5
	focus.expand_margin_bottom = 5
	theme.set_stylebox("focus", "Button", focus)
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var color := FIELD
		if state == "hover":
			color = FIELD.lightened(0.1)
		elif state in ["pressed", "hover_pressed"]:
			color = FIELD_PRESSED
		elif state == "disabled":
			color = FIELD.darkened(0.35)
		theme.set_stylebox(state, "OptionButton", _field_box(color))
	theme.set_stylebox("focus", "OptionButton", focus)
	theme.set_stylebox("normal", "LineEdit", _field_box(FIELD))
	theme.set_stylebox("focus", "LineEdit", focus)
	theme.set_stylebox("panel", "PopupMenu", _field_box(PANEL))
	theme.set_stylebox("hover", "PopupMenu", _field_box(FIELD_PRESSED))
	var panel := StyleBoxFlat.new()
	panel.bg_color = PANEL
	panel.border_color = Color("#45526a")
	panel.set_border_width_all(2)
	panel.set_corner_radius_all(30)
	panel.set_content_margin_all(30)
	panel.shadow_color = Color(0.02, 0.04, 0.1, 0.3)
	panel.shadow_size = 12
	panel.shadow_offset = Vector2(0, 8)
	theme.set_stylebox("panel", "PanelContainer", panel)
	theme.set_color("font_color", "Label", TEXT)
	theme.set_constant("separation", "VBoxContainer", 24)
	theme.set_constant("separation", "HBoxContainer", 20)
	return theme


static func _field_box(color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.border_color = Color("#60718a")
	box.set_border_width_all(2)
	box.set_corner_radius_all(20)
	box.content_margin_left = 24
	box.content_margin_right = 24
	box.content_margin_top = 20
	box.content_margin_bottom = 20
	return box


static func _button_box(primary: bool, tint := Color.WHITE) -> StyleBoxTexture:
	var box := StyleBoxTexture.new()
	box.texture = load("res://assets/ui/button_gold.svg" if primary else "res://assets/ui/button_jewel.svg")
	box.texture_margin_left = 52
	box.texture_margin_right = 52
	box.texture_margin_top = 42
	box.texture_margin_bottom = 42
	box.content_margin_left = 36
	box.content_margin_right = 36
	box.content_margin_top = 24
	box.content_margin_bottom = 24
	box.modulate_color = tint
	return box


static func icon(glyph: String) -> Texture2D:
	if not _icons.has(glyph):
		var path := "res://assets/ui/%s.svg" % glyph
		_icons[glyph] = load(path) if ResourceLoader.exists(path) else load("res://assets/ui/gem.svg")
	return _icons[glyph]


static func glyph_for(text: String) -> String:
	var lower := text.to_lower()
	if "pack" in lower or "pick" in lower:
		return "pack"
	if "coin" in lower:
		return "coin"
	if "new puzzle" in lower or lower in ["start", "continue", "view"]:
		return "play"
	if "photo" in lower:
		return "camera"
	if "settings" in lower:
		return "settings"
	if "power" in lower:
		return "power"
	if "recolor" in lower:
		return "palette"
	if "restart" in lower:
		return "replay"
	if "delete" in lower:
		return "delete"
	if "menu" in lower or "cancel" in lower:
		return "back"
	if "collection" in lower:
		return "collection"
	return "sparkle"


static func button(text: String, primary := false) -> Button:
	var button_node := Button.new()
	button_node.text = text
	button_node.icon = icon(glyph_for(text))
	button_node.expand_icon = false
	button_node.custom_minimum_size.y = TAP_HEIGHT
	if primary:
		button_node.theme_type_variation = "PrimaryButton"
	button_node.resized.connect(func() -> void: button_node.pivot_offset = button_node.size / 2.0)
	button_node.button_down.connect(func() -> void: _press(button_node, 0.975))
	button_node.button_up.connect(func() -> void: _press(button_node, 1.0))
	return button_node


static func _press(button_node: Button, amount: float) -> void:
	if button_node.has_meta("press_tween"):
		var previous: Tween = button_node.get_meta("press_tween")
		if previous.is_valid():
			previous.kill()
	var tween := button_node.create_tween()
	button_node.set_meta("press_tween", tween)
	tween.tween_property(button_node, "scale", Vector2.ONE * amount, 0.14).set_trans(Tween.TRANS_QUAD)


static func appear(control: Control) -> void:
	if control.has_meta("appear_tween"):
		var previous: Tween = control.get_meta("appear_tween")
		if previous.is_valid():
			previous.kill()
	control.show()
	control.modulate.a = 0.0
	var tween := control.create_tween()
	control.set_meta("appear_tween", tween)
	tween.tween_property(control, "modulate:a", 1.0, 0.26).set_trans(Tween.TRANS_SINE)


static func pack_color(pack: String) -> Color:
	return {"colors": Color("#ac6da0"), "shapes": Color("#4aa89a"), "cuts": Color("#668fc4"),
		"puzzles": Color("#799859"), "features": Color("#ba7c61"), "animations": Color("#9578be"),
		"powers": Color("#d49b4e"), "all": Color("#658fac")}.get(pack, GOLD)


static func pack_glyph(pack: String) -> String:
	return {"colors": "palette", "shapes": "gem", "cuts": "gem", "puzzles": "picture",
		"features": "flourish", "animations": "sparkle", "powers": "power", "all": "collection"}.get(pack, "gem")
